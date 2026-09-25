--!strict
-- EyeAdaptation: auto-exposure after Unreal's eye adaptation, plus the scene
-- probe it meters with. Walking out of a dark interior into noon sun blooms and
-- then settles; stepping under an arch opens up the shade. Client only.
--
-- 	local EyeAdaptation = require(path.to.EyeAdaptation)
-- 	EyeAdaptation.start({
-- 		albedo = { crate = Color3.fromRGB(150, 110, 70) }, -- optional measured albedos
-- 		ignore = function() return { workspace.Enemies } end, -- optional
-- 	})
-- 	EyeAdaptation.setEnabled(false) -- eases back to the base exposure
--
-- Roblox gives scripts no access to the rendered image, so the view's
-- brightness is estimated from the scene: rays through a 7 x 5 grid of screen
-- points (5 per frame, round-robin, so a full sweep every 7 frames) hit
-- surfaces whose albedo and sun exposure are known; a ray that reaches the sky
-- counts as sky. The log-average of those luminances, centre-weighted like
-- Unreal's default metering, sets the target:
-- 	adapt = clamp(-log2(average / reference) * strength, minEv, maxEv)
-- easing at 0.9 stops/s when the view got darker (the eye opening up is
-- slower, as in Unreal) and 1.8 stops/s when it got brighter. strength 0.55:
-- full correction looks like a camera's auto-exposure, not an eye.
--
-- Albedo, in order: an entry of `albedo` keyed by the name of the hit part or
-- any ancestor model (a trailing _<number> is ignored, so "tree_3" finds
-- "tree"); for Terrain, `terrainAlbedo[material]` or else
-- Terrain:GetMaterialColor(material); a part with a SurfaceAppearance (its
-- texture cannot be read at run time) uses `fallbackAlbedo`; anything else its
-- Part.Color. Measure albedos offline (mean of the colour map) for the models
-- that fill most of the view; the rest are close enough.
--
-- Exposure. This is the one writer of Lighting.ExposureCompensation in the post
-- stack: it writes base + grade + extra + adapt, where base is whatever someone
-- else last wrote (a lighting preset, a day/night script: followed, never
-- fought), grade is the Lighting attribute ForgeGUIGradeExposure published by
-- ColourGrade, and extra is the optional `extraExposure()` callback. The first
-- value found is recorded as ForgeGUIEyeAdaptationPrior_ExposureCompensation;
-- stop() puts the latest base back and removes the attribute. A preset applied
-- mid-run records our adapted value as its ForgeGUIPrior_; that record is
-- rewritten to the base underneath, so the preset's clear() still restores.
--
-- Rays skip every player's character, anything `ignore()` returns, water, and
-- parts at least 90 % transparent (colliders would otherwise read as black
-- walls that block the sun). Cost: 5 view rays plus up to 5 sun rays a frame.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local EyeAdaptation = {}

export type Hit = { position: Vector3, normal: Vector3, albedo: Color3, instance: Instance }
export type Options = {
	enabled: boolean?, -- auto-exposure on (default true); off still applies the grade's exposure
	albedo: { [string]: Color3 }?, -- model or part name -> measured albedo (sRGB)
	terrainAlbedo: { [Enum.Material]: Color3 }?, -- terrain material -> albedo; default the material colour
	fallbackAlbedo: Color3?, -- for textured meshes without an entry (default mid grey)
	ignore: (() -> { Instance })?, -- extra instances the rays skip
	extraExposure: (() -> number)?, -- any other exposure offset, in stops
	key: number?, -- scene luminance the base exposure is tuned for (default 0.42)
	strength: number?, -- share of the difference corrected (default 0.55)
	minEv: number?, -- default -0.7
	maxEv: number?, -- default 1.3
}

local GRID_X, GRID_Y = 7, 5
local RAYS_PER_FRAME = 5
local REACH = 900
local SPEED_UP, SPEED_DOWN = 0.9, 1.8 -- stops per second
local SKY_LUMINANCE = 1.1 -- relative to a sunlit white surface
local SKY_SHARE = 0.55 -- sky counts for less: the eye meters the ground
local AMBIENT_SHARE = 0.28 -- light on a shaded surface, as a share of the sun
local NIGHT_LIGHT = 0.12 -- moonlight, relative
local SUN_RAY = 400
local INVISIBLE = 0.9 -- parts at least this transparent are looked through
local MAX_SKIPS = 4
local FILTER_REFRESH = 1 -- seconds
local PRIOR_KEY = "ForgeGUIEyeAdaptationPrior_ExposureCompensation"
local GRADE_ATTR = "ForgeGUIGradeExposure"

local DEFAULTS = { key = 0.42, strength = 0.55, minEv = -0.7, maxEv = 1.3 }
local MID_GREY = Color3.fromRGB(128, 128, 128)

local opts: Options = {}
local enabled = true
local samples: { number } = table.create(GRID_X * GRID_Y, DEFAULTS.key)
local weights: { number } = {}
local cursor = 0
local adapt = 0
local started = false
local connection: RBXScriptConnection? = nil
local exposure = { base = 0, written = nil :: number?, ownsPrior = false, active = false }

-- Centre-weighted metering: the middle of the screen counts about 3x the edges.
for gy = 0, GRID_Y - 1 do
	for gx = 0, GRID_X - 1 do
		local u = (gx + 0.5) / GRID_X - 0.5
		local v = (gy + 0.5) / GRID_Y - 0.5
		table.insert(weights, math.exp(-(u * u + v * v) * 5))
	end
end

-- Probe --------------------------------------------------------------------------------

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true
local lastFilter = -math.huge

local function refreshFilter()
	local now = os.clock()
	if now - lastFilter < FILTER_REFRESH then
		return
	end
	lastFilter = now
	local list: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	local extra = opts.ignore
	if extra then
		for _, instance in extra() do
			table.insert(list, instance)
		end
	end
	params.FilterDescendantsInstances = list
end

-- "tree_3" -> "tree": the name a placed copy was cloned from.
local function kitName(name: string): string
	return (string.gsub(name, "_%d+$", ""))
end

local function partAlbedo(part: BasePart): Color3
	local known = opts.albedo
	if known then
		local node: Instance? = part
		while node and node ~= Workspace do
			local found = known[node.Name] or known[kitName(node.Name)]
			if found then
				return found
			end
			node = node.Parent
		end
	end
	if part:FindFirstChildOfClass("SurfaceAppearance") then
		return opts.fallbackAlbedo or MID_GREY
	end
	return part.Color
end

function EyeAdaptation.albedoOf(result: RaycastResult): Color3
	local instance = result.Instance
	if instance == Workspace.Terrain then
		local measured = opts.terrainAlbedo
		local found = measured and measured[result.Material]
		if found then
			return found
		end
		local ok, colour = pcall(function()
			return Workspace.Terrain:GetMaterialColor(result.Material)
		end)
		return if ok then colour else (opts.fallbackAlbedo or MID_GREY)
	end
	return partAlbedo(instance :: BasePart)
end

-- The first visible surface along a ray, looking through invisible parts.
local function castVisible(origin: Vector3, direction: Vector3): RaycastResult?
	refreshFilter()
	local unit, remaining, from = direction.Unit, direction.Magnitude, origin
	for _ = 0, MAX_SKIPS do
		local result = Workspace:Raycast(from, unit * remaining, params)
		if not result then
			return nil
		end
		local instance = result.Instance
		if instance == Workspace.Terrain or (instance :: BasePart).Transparency < INVISIBLE then
			return result
		end
		remaining -= (result.Position - from).Magnitude + 0.05
		from = result.Position + unit * 0.05
		if remaining <= 0 then
			return nil
		end
	end
	return nil
end

function EyeAdaptation.cast(origin: Vector3, direction: Vector3): Hit?
	local result = castVisible(origin, direction)
	if not result then
		return nil
	end
	local hit: Hit = {
		position = result.Position,
		normal = result.Normal,
		albedo = EyeAdaptation.albedoOf(result),
		instance = result.Instance :: Instance,
	}
	return hit
end

-- Whether the sun reaches `point` (nudged off its surface along `normal`).
function EyeAdaptation.sunlit(point: Vector3, normal: Vector3): boolean
	local sun = Lighting:GetSunDirection()
	if sun.Y <= 0 or normal:Dot(sun) <= 0 then
		return false
	end
	return castVisible(point + normal * 0.3, sun * SUN_RAY) == nil
end

function EyeAdaptation.luma(c: Color3): number
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

-- Metering -------------------------------------------------------------------------------

local function sunStrength(): number
	return math.clamp(Lighting:GetSunDirection().Y * 4, 0, 1)
end

-- The relative luminance one grid ray sees.
local function measure(camera: Camera, index: number): number
	local gx, gy = index % GRID_X, index // GRID_X
	local size = camera.ViewportSize
	local ray = camera:ViewportPointToRay((gx + 0.5) / GRID_X * size.X, (gy + 0.5) / GRID_Y * size.Y)
	local hit = EyeAdaptation.cast(ray.Origin, ray.Direction * REACH)
	local sun = sunStrength()
	if not hit then
		return math.max(SKY_LUMINANCE * sun, NIGHT_LIGHT) * SKY_SHARE
	end
	local lit = 0
	if sun > 0 and EyeAdaptation.sunlit(hit.position, hit.normal) then
		lit = math.max(hit.normal:Dot(Lighting:GetSunDirection()), 0)
	end
	local light = sun * (lit + AMBIENT_SHARE) + NIGHT_LIGHT * (1 - sun)
	return math.max(EyeAdaptation.luma(hit.albedo) * light, 1e-3)
end

-- The centre-weighted log-average of the latest samples. Stand where the base
-- exposure looks right and read this to calibrate `key` for your scene.
function EyeAdaptation.average(): number
	local total, weight = 0, 0
	for i, value in samples do
		total += math.log(math.max(value, 1e-3), 2) * weights[i]
		weight += weights[i]
	end
	return 2 ^ (total / weight)
end

-- The adaptation (stops) a given average luminance asks for, at a sun strength 0..1.
function EyeAdaptation.targetFor(average: number, sun: number): number
	local reference = (opts.key or DEFAULTS.key) * math.max(sun, 0.3)
	local k = opts.strength or DEFAULTS.strength
	local low, high = opts.minEv or DEFAULTS.minEv, opts.maxEv or DEFAULTS.maxEv
	return math.clamp(-math.log(math.max(average, 1e-6) / reference, 2) * k, low, high)
end

-- Exposure -------------------------------------------------------------------------------

-- Another ForgeGUI module (LightingPresets, SkyboxPresets) that borrowed this
-- property while our layer was on it recorded our layered value as its prior.
-- Hand it the value underneath, so its clear() returns the real original.
local FOREIGN_PRIORS = { "ForgeGUIPrior_", "ForgeGUISkyboxPrior_" }
local function correctForeignPriors(instance: Instance, property: string, layered: any, underneath: any)
	if underneath == nil then
		return
	end
	for _, prefix in FOREIGN_PRIORS do
		local key = prefix .. property
		if instance:GetAttribute(key) == layered then
			instance:SetAttribute(key, underneath)
		end
	end
end

local function writeExposure()
	local current = Lighting.ExposureCompensation
	if not exposure.active then
		exposure.ownsPrior = Lighting:GetAttribute(PRIOR_KEY) == nil
		if exposure.ownsPrior then
			Lighting:SetAttribute(PRIOR_KEY, current)
		end
		exposure.base, exposure.active = current, true
	elseif exposure.written ~= nil and current ~= exposure.written then
		correctForeignPriors(Lighting, "ExposureCompensation", exposure.written, exposure.base)
		exposure.base = current -- someone else wrote it: follow them
	end
	local grade = Lighting:GetAttribute(GRADE_ATTR)
	local extra = opts.extraExposure
	local value = exposure.base
		+ (if type(grade) == "number" then grade else 0)
		+ (if extra then extra() else 0)
		+ adapt
	if math.abs(current - value) > 1e-4 then
		Lighting.ExposureCompensation = value
	end
	exposure.written = Lighting.ExposureCompensation
end

local function releaseExposure()
	if not exposure.active then
		return
	end
	if exposure.written ~= nil and Lighting.ExposureCompensation == exposure.written then
		Lighting.ExposureCompensation = exposure.base
	end
	if exposure.ownsPrior then
		Lighting:SetAttribute(PRIOR_KEY, nil)
	end
	exposure.active, exposure.written, exposure.ownsPrior = false, nil, false
end

-- One frame. Public so tests and custom loops can drive it.
function EyeAdaptation.step(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local target = 0
	if enabled then
		for _ = 1, RAYS_PER_FRAME do
			samples[cursor + 1] = measure(camera, cursor)
			cursor = (cursor + 1) % (GRID_X * GRID_Y)
		end
		target = EyeAdaptation.targetFor(EyeAdaptation.average(), sunStrength())
	end
	local speed = if target > adapt then SPEED_UP else SPEED_DOWN
	local stepSize = speed * dt
	adapt += math.clamp(target - adapt, -stepSize, stepSize)
	writeExposure()
end

-- The current adaptation, in stops.
function EyeAdaptation.adaptation(): number
	return adapt
end

function EyeAdaptation.setEnabled(on: boolean)
	enabled = on ~= false
end

-- Puts back a prior left by a session that never stopped (or seen by a fresh require).
local function restoreStale()
	local stale = Lighting:GetAttribute(PRIOR_KEY)
	if type(stale) == "number" then
		Lighting.ExposureCompensation = stale
	end
	Lighting:SetAttribute(PRIOR_KEY, nil)
end

function EyeAdaptation.start(options: Options?)
	opts = options or {}
	enabled = opts.enabled ~= false
	lastFilter = -math.huge
	if started then
		return
	end
	started = true
	restoreStale()
	connection = RunService.RenderStepped:Connect(EyeAdaptation.step)
end

function EyeAdaptation.stop()
	started = false
	local c = connection
	if c then
		c:Disconnect()
		connection = nil
	end
	releaseExposure()
	restoreStale()
	adapt, cursor = 0, 0
	samples = table.create(GRID_X * GRID_Y, opts.key or DEFAULTS.key)
end

return EyeAdaptation
