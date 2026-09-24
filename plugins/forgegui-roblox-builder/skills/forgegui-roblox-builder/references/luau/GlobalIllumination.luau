--!strict
-- GlobalIllumination: approximated one-bounce light near the camera, client side.
-- Ship as a ModuleScript required by one LocalScript:
--   local GI = require(ReplicatedStorage.GlobalIllumination)
--   GI.start({ level = 1 })   -- 0 off, 0.5 low, 1 high; GI.setLevel(x) later
--   GI.stop()                 -- destroys what it made, hands the ambients back
--
-- Roblox has no bounce light: a wall's shaded side is lit by the flat ambients
-- whatever it stands on, and a roofed passage gets the same sky light as an open
-- square. This module approximates both with what Roblox does offer: raycasts,
-- cheap unshadowed lights and the three global ambient properties.
--
-- 1. Ground bounce (every PROBE_STEP): rays over the lower hemisphere round the
--    camera focus find the ground and walls nearby; each hit's albedo times the
--    light it receives (sun if it reaches the point, plus sky) is what it
--    bounces. The average drives Lighting.ColorShift_Bottom, so shaded sides
--    glow warm over sand, white-blue over snow, green over grass. The albedo
--    comes from the terrain material (an injectable material -> colour map with
--    approximate defaults, times Terrain:GetMaterialColor), a `ForgeGUIAlbedo`
--    Color3 attribute on a part or any ancestor, an `albedoOf` callback, or
--    Part.Color. A SurfaceAppearance's texture cannot be read at run time, so a
--    generated mesh with no attribute falls back to `fallbackAlbedo`.
-- 2. Sky openness: rays over the upper hemisphere measure how much sky is
--    open. OutdoorAmbient follows it, so alleys, arches and rooms darken the way
--    ambient occlusion darkens them in other engines. Measured: Roblox's own sky
--    light hardly dims inside a narrow roofed passage, and extra hidden geometry
--    changed nothing; this probe (and PassageShade for baked interiors) is the fix.
-- 3. Colour bleed ("instant radiosity"): a grid of rays traced from the sun onto
--    the area round the camera. Each sunlit hit with something within
--    RECEIVER_REACH to light (a wall, doorway, overhang) becomes a hemisphere
--    SpotLight on the surface, in the patch's colour and strength, so a sunlit
--    street throws warm light up under balconies and a red awning tints the wall
--    beside it. Cells snap to a world grid so lights do not swim, ease in and
--    out, and the strongest cells win the budget (24 low / 64 high). Lights are
--    cheap: 128 unshadowed SpotLights cost no measurable frame time.
--
-- Ownership: bounce lights are Attachments under Workspace.Terrain carrying
-- ForgeGUIGlobalIllumination = true; stop() destroys only those. Lighting's
-- Ambient, OutdoorAmbient and ColorShift_Bottom are borrowed: their values are
-- recorded as ForgeGUIPrior_<Property> (only if no other ForgeGUI module has
-- already recorded one, so the first recorder keeps the true original) and
-- stop() puts the base values back. The base follows the place: if something
-- else (a day/night cycle, LightingPresets.apply) writes one of the three while
-- GI runs, GI adopts that as the new base instead of fighting it. For a cycle
-- that writes every frame, pass `getBase` and stop the cycle writing them.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GlobalIllumination = {}

export type Base = { ambient: Color3, outdoor: Color3, bottom: Color3 }
export type Options = {
	level: number?, -- 0 off, < 0.75 low, otherwise high (default 1)
	albedo: { [Enum.Material]: Color3 }?, -- terrain texture means; merged over the defaults
	fallbackAlbedo: Color3?, -- a textured mesh with no ForgeGUIAlbedo attribute
	albedoOf: ((BasePart) -> Color3?)?, -- your own lookup, tried before the attribute
	referenceAlbedo: Color3?, -- the ground the place's base ColorShift_Bottom was tuned on
	bounceLevel: number?, -- bounce luma to use when the base ColorShift_Bottom is black
	getSunColour: (() -> Color3)?, -- default Lighting.ColorShift_Top
	getBase: (() -> Base)?, -- the un-bounced ambients, for games with a day/night cycle
	ignore: (() -> { Instance })?, -- extra instances rays pass through (NPC folders, FX)
	getFocus: (() -> Vector3)?, -- default Workspace.CurrentCamera.Focus.Position
	manual: boolean?, -- true: no Heartbeat connection; call GI.step(dt) yourself
}

type Quality = { cell: number, extent: number, budget: number, cellsPerFrame: number }
type Vpl = { attachment: Attachment, light: SpotLight, brightness: number, target: number }
type Candidate = { key: string, position: Vector3, normal: Vector3, colour: Color3, strength: number, score: number }
type Hit = { position: Vector3, normal: Vector3, albedo: Color3 }

local OWNED_ATTR = "ForgeGUIGlobalIllumination"
local PRIOR_PREFIX = "ForgeGUIPrior_"
local PRESET_ATTR = "ForgeGUIPreset" -- LightingPresets' marker: it owns the priors while applied
local ALBEDO_ATTR = "ForgeGUIAlbedo"
local BORROWED = { "Ambient", "OutdoorAmbient", "ColorShift_Bottom" }

local LOW: Quality = { cell = 10, extent = 4, budget = 24, cellsPerFrame = 24 }
local HIGH: Quality = { cell = 6, extent = 7, budget = 64, cellsPerFrame = 48 }
local PROBE_STEP = 0.25
local DOWN_RAYS, UP_RAYS = 28, 16
local PROBE_REACH, SKY_REACH, SUN_RAY = 60, 140, 400
local RECEIVER_REACH = 14 -- how near something must be for a patch's bounce to matter
local VPL_RANGE, VPL_ANGLE, VPL_GAIN = 16, 170, 0.55
local VPL_MIN = 0.06 -- weaker patches are not worth a light
local FADE_RATE, AMBIENT_RATE = 4, 1.5 -- per second
local SWEEP_REST = 0.3 -- seconds between finished sweeps
local AMBIENT_STEP = 0.1 -- ambients ease slowly: 10 writes a second are enough
local BRIGHTNESS_STEP = 0.004 -- smaller light changes are not written
local SKY_LEVEL = 0.35 -- sky light on a surface, as a share of the sun
local INVISIBLE = 0.9 -- parts at least this transparent are looked through (colliders)
local MAX_SKIPS = 4
local COLOUR_EPSILON = 1.5 / 255 -- a write this far from ours came from someone else

local rgb = Color3.fromRGB
-- Approximate means of the default Roblox terrain textures (sRGB), before the
-- material colour tint. Estimates, not measurements of every texture pack:
-- pass `albedo` with measured means when the place uses custom MaterialVariants.
local DEFAULT_ALBEDO: { [Enum.Material]: Color3 } = {
	[Enum.Material.Sand] = rgb(201, 178, 146),
	[Enum.Material.Sandstone] = rgb(184, 164, 142),
	[Enum.Material.Rock] = rgb(150, 145, 140),
	[Enum.Material.Limestone] = rgb(200, 190, 170),
	[Enum.Material.Ground] = rgb(153, 125, 98),
	[Enum.Material.Mud] = rgb(96, 86, 79),
	[Enum.Material.Salt] = rgb(220, 217, 212),
	[Enum.Material.Slate] = rgb(120, 118, 115),
	[Enum.Material.Basalt] = rgb(80, 78, 78),
	[Enum.Material.Grass] = rgb(90, 120, 60),
	[Enum.Material.LeafyGrass] = rgb(80, 110, 55),
	[Enum.Material.Snow] = rgb(235, 240, 245),
	[Enum.Material.Glacier] = rgb(190, 215, 230),
	[Enum.Material.Ice] = rgb(200, 220, 235),
	[Enum.Material.Asphalt] = rgb(80, 80, 82),
	[Enum.Material.Concrete] = rgb(160, 158, 152),
	[Enum.Material.Pavement] = rgb(150, 148, 142),
	[Enum.Material.Cobblestone] = rgb(130, 125, 118),
	[Enum.Material.Brick] = rgb(150, 90, 70),
	[Enum.Material.WoodPlanks] = rgb(140, 105, 70),
}
local NEUTRAL_ALBEDO = rgb(150, 140, 125)

local config = {
	albedo = DEFAULT_ALBEDO,
	fallbackAlbedo = NEUTRAL_ALBEDO,
	referenceAlbedo = NEUTRAL_ALBEDO,
	bounceLevel = 0.3,
}
local opts: Options = {}
local level = 1
local vpls: { [string]: Vpl } = {}
local pool: { Vpl } = {}
local candidates: { Candidate } = {}
local sweep: { Vector2 } = {}
local sweepCentre = Vector3.zero
local downDirs: { Vector3 } = {}
local upDirs: { Vector3 } = {}
local bounce, skyOpen = Color3.new(0.5, 0.45, 0.4), 1
local base: Base? = nil
local written: Base? = nil
local shown: Base? = nil
local wrotePriors: { string } = {}
local connection: RBXScriptConnection? = nil
local sweepRest, sinceProbe, sinceAmbient = 0, PROBE_STEP, AMBIENT_STEP
local running = false

-- Colour helpers ---------------------------------------------------------------------------

local function luma(c: Color3): number
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

local function scale(c: Color3, k: number): Color3
	return Color3.new(c.R * k, c.G * k, c.B * k)
end

local function multiply(a: Color3, b: Color3): Color3
	return Color3.new(a.R * b.R, a.G * b.G, a.B * b.B)
end

local function clampColour(c: Color3): Color3
	return Color3.new(math.clamp(c.R, 0, 1), math.clamp(c.G, 0, 1), math.clamp(c.B, 0, 1))
end

-- `c`'s hue and saturation at the brightness (luma) `target`.
local function withLuma(c: Color3, target: number): Color3
	return clampColour(scale(c, target / math.max(luma(c), 1e-3)))
end

local function differs(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) > COLOUR_EPSILON or math.abs(a.G - b.G) > COLOUR_EPSILON or math.abs(a.B - b.B) > COLOUR_EPSILON
end

-- Probe: what a ray sees -----------------------------------------------------------------

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true
local lastFilter = -math.huge

-- Characters move, and the light they bounce is not worth the flicker.
local function refreshFilter()
	local now = os.clock()
	if now - lastFilter < 1 then
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

local function partAlbedo(part: BasePart): Color3
	local custom = opts.albedoOf
	local found = if custom then custom(part) else nil
	if found then
		return found
	end
	local node: Instance? = part
	while node and node ~= Workspace do
		local value = node:GetAttribute(ALBEDO_ATTR)
		if typeof(value) == "Color3" then
			return value
		end
		node = node.Parent
	end
	if part:FindFirstChildOfClass("SurfaceAppearance") then
		return config.fallbackAlbedo
	end
	return part.Color
end

local function albedoOf(result: RaycastResult): Color3
	if result.Instance == Workspace.Terrain then
		local mean = config.albedo[result.Material]
		if not mean then
			return config.fallbackAlbedo
		end
		return multiply(mean, Workspace.Terrain:GetMaterialColor(result.Material))
	end
	return partAlbedo(result.Instance :: BasePart)
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

local function cast(origin: Vector3, direction: Vector3): Hit?
	local result = castVisible(origin, direction)
	if not result then
		return nil
	end
	return { position = result.Position, normal = result.Normal, albedo = albedoOf(result) }
end

local function sunlit(point: Vector3, normal: Vector3): boolean
	local sun = Lighting:GetSunDirection()
	if sun.Y <= 0 or normal:Dot(sun) <= 0 then
		return false
	end
	return castVisible(point + normal * 0.3, sun * SUN_RAY) == nil
end

-- A Fibonacci spiral over a hemisphere (sign -1: below, 1: above), cosine-weighted.
local function hemisphere(count: number, sign: number): { Vector3 }
	local list = {}
	local golden = math.pi * (3 - math.sqrt(5))
	for i = 0, count - 1 do
		local y = math.sqrt((i + 0.5) / count)
		local r = math.sqrt(1 - y * y)
		local a = golden * i
		table.insert(list, Vector3.new(math.cos(a) * r, sign * y, math.sin(a) * r))
	end
	return list
end

local function quality(): Quality?
	if level <= 0.01 then
		return nil
	end
	return if level < 0.75 then LOW else HIGH
end

local function sunStrength(): number
	return Lighting.Brightness * math.clamp(Lighting:GetSunDirection().Y * 4, 0, 1)
end

local function sunColour(): Color3
	local getter = opts.getSunColour
	local colour = if getter then getter() else Lighting.ColorShift_Top
	return if luma(colour) < 0.05 then Color3.new(1, 0.95, 0.88) else colour
end

-- 1 + 2. Ground bounce and sky openness ------------------------------------------------------

local function probe(focus: Vector3)
	local origin = focus + Vector3.new(0, 2.5, 0)
	local sun, total, weight = sunStrength(), Vector3.zero, 0
	for _, dir in downDirs do
		local hit = cast(origin, dir * PROBE_REACH)
		if hit then
			local lit = 0
			if sun > 0 and sunlit(hit.position, hit.normal) then
				lit = math.max(hit.normal:Dot(Lighting:GetSunDirection()), 0)
			end
			local received = sun * lit + sun * SKY_LEVEL + 0.15
			local w = -dir.Y -- nearer straight down counts more, as for a surface facing the floor
			total += Vector3.new(hit.albedo.R, hit.albedo.G, hit.albedo.B) * received * w
			weight += w
		end
	end
	if weight > 0 then
		local avg = total / weight
		bounce = Color3.new(avg.X, avg.Y, avg.Z)
	end
	local open, all = 0, 0
	for _, dir in upDirs do
		all += dir.Y
		if not castVisible(origin, dir * SKY_REACH) then
			open += dir.Y
		end
	end
	skyOpen = if all > 0 then open / all else 1
end

-- 3. Colour bleed -------------------------------------------------------------------------------

local function releaseVpl(key: string)
	local vpl = vpls[key]
	vpls[key] = nil
	vpl.light.Enabled = false
	table.insert(pool, vpl)
end

local function takeVpl(): Vpl
	local reused = table.remove(pool)
	if reused then
		reused.brightness = 0
		reused.light.Enabled = true
		return reused
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "ForgeGUI_GIBounce"
	attachment:SetAttribute(OWNED_ATTR, true)
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Top
	light.Angle = VPL_ANGLE
	light.Range = VPL_RANGE
	light.Shadows = false
	light.Brightness = 0
	light.Parent = attachment
	attachment.Parent = Workspace.Terrain
	return { attachment = attachment, light = light, brightness = 0, target = 0 }
end

-- How much there is round a patch for its bounce to land on (0..1).
local function receivers(position: Vector3, normal: Vector3): number
	local a = if math.abs(normal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	local t1 = normal:Cross(a).Unit
	local t2 = normal:Cross(t1)
	local found = 0
	for _, t in { t1, -t1, t2, -t2 } do
		if castVisible(position + normal * 1.2, (t + normal * 0.45).Unit * RECEIVER_REACH) then
			found += 1
		end
	end
	return found / 4
end

local function traceCell(cell: Vector2, q: Quality, sun: Vector3, strength: number, tint: Color3)
	local centre = Vector3.new(sweepCentre.X + cell.X * q.cell, sweepCentre.Y, sweepCentre.Z + cell.Y * q.cell)
	local hit = cast(centre + sun * 300, -sun * 600)
	if not hit then
		return
	end
	local cos = hit.normal:Dot(sun)
	local power = luma(hit.albedo) * cos * strength * VPL_GAIN
	if cos <= 0.05 or power < VPL_MIN then
		return
	end
	local near = receivers(hit.position, hit.normal)
	if near <= 0 then
		return -- open ground: the ground-bounce ambient already carries it
	end
	table.insert(candidates, {
		key = ("%d,%d"):format(math.floor(centre.X / q.cell + 0.5), math.floor(centre.Z / q.cell + 0.5)),
		position = hit.position + hit.normal * 0.6,
		normal = hit.normal,
		colour = multiply(hit.albedo, tint),
		strength = power,
		score = power * (0.25 + 0.75 * near),
	})
end

local function place(vpl: Vpl, c: Candidate)
	local a = if math.abs(c.normal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	local tangent = c.normal:Cross(a).Unit
	vpl.attachment.WorldCFrame = CFrame.fromMatrix(c.position, tangent, c.normal)
	vpl.target = c.strength
	vpl.light.Color = withLuma(c.colour, 0.85)
end

local function commit(q: Quality)
	table.sort(candidates, function(a: Candidate, b: Candidate)
		return a.score > b.score
	end)
	local chosen: { [string]: Candidate } = {}
	for i = 1, math.min(#candidates, q.budget) do
		chosen[candidates[i].key] = candidates[i]
	end
	for key, vpl in vpls do
		if not chosen[key] then
			vpl.target = 0
		end
	end
	for key, c in chosen do
		local vpl = vpls[key] or takeVpl()
		vpls[key] = vpl
		place(vpl, c)
	end
	table.clear(candidates)
end

local function startSweep(focus: Vector3, q: Quality)
	sweepCentre = Vector3.new(math.floor(focus.X / q.cell + 0.5) * q.cell, focus.Y, math.floor(focus.Z / q.cell + 0.5) * q.cell)
	table.clear(sweep)
	for x = -q.extent, q.extent do
		for z = -q.extent, q.extent do
			table.insert(sweep, Vector2.new(x, z))
		end
	end
end

local function fadeVpls(dt: number)
	local k = 1 - math.exp(-FADE_RATE * dt)
	for key, vpl in vpls do
		vpl.brightness += (vpl.target - vpl.brightness) * k
		if vpl.target <= 0 and vpl.brightness < 0.01 then
			releaseVpl(key)
		elseif math.abs(vpl.light.Brightness - vpl.brightness) > BRIGHTNESS_STEP then
			vpl.light.Brightness = vpl.brightness
		end
	end
end

local function stepVpls(focus: Vector3, q: Quality?, dt: number)
	local strength = sunStrength()
	if not q or strength <= 0.05 then
		table.clear(sweep)
		table.clear(candidates)
		for _, vpl in vpls do
			vpl.target = 0
		end
		fadeVpls(dt)
		return
	end
	if #sweep == 0 then
		if #candidates > 0 then
			commit(q)
			sweepRest = SWEEP_REST
		end
		sweepRest -= dt
		if sweepRest <= 0 then
			startSweep(focus, q)
		end
	end
	local sun, tint = Lighting:GetSunDirection(), sunColour()
	for _ = 1, math.min(q.cellsPerFrame, #sweep) do
		traceCell(table.remove(sweep) :: Vector2, q, sun, strength, tint)
	end
	fadeVpls(dt)
end

-- Ambients ------------------------------------------------------------------------------------

local function readLighting(): Base
	return { ambient = Lighting.Ambient, outdoor = Lighting.OutdoorAmbient, bottom = Lighting.ColorShift_Bottom }
end

-- Someone else wrote one of our properties since our last write: that is the new base.
local function currentBase(): Base
	local getter = opts.getBase
	if getter then
		return getter()
	end
	local b = base or readLighting()
	local last = written
	if last then
		local now = readLighting()
		b = {
			ambient = if differs(now.ambient, last.ambient) then now.ambient else b.ambient,
			outdoor = if differs(now.outdoor, last.outdoor) then now.outdoor else b.outdoor,
			bottom = if differs(now.bottom, last.bottom) then now.bottom else b.bottom,
		}
	end
	base = b
	return b
end

local function target(b: Base, on: boolean): Base
	if not on then
		return b
	end
	local baseLevel = luma(b.bottom)
	if baseLevel < 0.02 then
		baseLevel = config.bounceLevel -- the place never set a bounce colour
	end
	local sun = math.max(sunStrength(), 0.3)
	local reference = luma(config.referenceAlbedo) * sun * (0.85 + SKY_LEVEL)
	local ratio = math.clamp(luma(bounce) / math.max(reference, 1e-3), 0.35, 1.6)
	local bottom = withLuma(bounce, baseLevel * ratio)
	return {
		bottom = bottom,
		outdoor = clampColour(scale(b.outdoor, 0.45 + 0.55 * skyOpen):Lerp(bottom, 0.12 * skyOpen)),
		ambient = clampColour(b.ambient:Lerp(bottom, 0.18 * (1 - skyOpen))),
	}
end

local function applyAmbients(on: boolean, dt: number)
	local want = target(currentBase(), on)
	local k = 1 - math.exp(-AMBIENT_RATE * dt)
	local from = shown or want
	local nextShown: Base = {
		ambient = from.ambient:Lerp(want.ambient, k),
		outdoor = from.outdoor:Lerp(want.outdoor, k),
		bottom = from.bottom:Lerp(want.bottom, k),
	}
	shown = nextShown
	Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.ColorShift_Bottom = nextShown.ambient, nextShown.outdoor, nextShown.bottom
	written = readLighting() -- what the engine stored, after its own quantisation
end

-- Lifecycle -------------------------------------------------------------------------------------

local function rememberPriors()
	table.clear(wrotePriors)
	for _, property in BORROWED do
		local key = PRIOR_PREFIX .. property
		if Lighting:GetAttribute(key) == nil then
			Lighting:SetAttribute(key, (Lighting :: any)[property])
			table.insert(wrotePriors, key)
		end
	end
end

local function configure(options: Options)
	opts = options
	local merged = table.clone(DEFAULT_ALBEDO)
	local custom = options.albedo
	if custom then
		for material, colour in custom do
			merged[material] = colour
		end
	end
	config.albedo = merged
	config.fallbackAlbedo = options.fallbackAlbedo or NEUTRAL_ALBEDO
	config.referenceAlbedo = options.referenceAlbedo or NEUTRAL_ALBEDO
	config.bounceLevel = options.bounceLevel or 0.3
	lastFilter = -math.huge
end

-- One frame of work. Heartbeat calls it after start(); with `manual` you call it.
function GlobalIllumination.step(dt: number)
	if not running then
		return
	end
	local getter = opts.getFocus
	local camera = Workspace.CurrentCamera
	local focus = if getter then getter() elseif camera then camera.Focus.Position else nil
	if not focus then
		return
	end
	local q = quality()
	sinceProbe += dt
	if q and sinceProbe >= PROBE_STEP then
		sinceProbe = 0
		probe(focus)
	end
	stepVpls(focus, q, dt)
	sinceAmbient += dt
	if sinceAmbient >= AMBIENT_STEP then
		applyAmbients(q ~= nil, sinceAmbient)
		sinceAmbient = 0
	end
end

function GlobalIllumination.setLevel(value: number)
	level = math.clamp(if value == value then value else 1, 0, 1)
end

-- Idempotent: a second start only updates the options.
function GlobalIllumination.start(options: Options?)
	local given: Options = options or {}
	configure(given)
	GlobalIllumination.setLevel(given.level or level)
	if running then
		return
	end
	running = true
	downDirs, upDirs = hemisphere(DOWN_RAYS, -1), hemisphere(UP_RAYS, 1)
	base, written, shown = readLighting(), nil, nil
	sinceProbe, sinceAmbient = PROBE_STEP, AMBIENT_STEP
	rememberPriors()
	Lighting:SetAttribute(OWNED_ATTR, true)
	if not given.manual then
		connection = RunService.Heartbeat:Connect(GlobalIllumination.step)
	end
end

-- Destroys every bounce light it made and hands the ambients back. Idempotent.
function GlobalIllumination.stop(): boolean
	if not running then
		return false
	end
	running = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
	for _, child in Workspace.Terrain:GetChildren() do
		if child:GetAttribute(OWNED_ATTR) == true then
			child:Destroy()
		end
	end
	table.clear(vpls)
	table.clear(pool)
	table.clear(sweep)
	table.clear(candidates)
	local b = currentBase()
	Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.ColorShift_Bottom = b.ambient, b.outdoor, b.bottom
	-- While a LightingPresets look is applied its clear() still needs the true original.
	if Lighting:GetAttribute(PRESET_ATTR) == nil then
		for _, key in wrotePriors do
			Lighting:SetAttribute(key, nil)
		end
	end
	table.clear(wrotePriors)
	Lighting:SetAttribute(OWNED_ATTR, nil)
	base, written, shown = nil, nil, nil
	return true
end

-- Live numbers for tuning in play: bounce colour, sky openness, lights in use.
function GlobalIllumination.stats(): { [string]: any }
	local lit = 0
	for _ in vpls do
		lit += 1
	end
	return { running = running, level = level, bounce = bounce, skyOpen = skyOpen, lights = lit, pooled = #pool, sweepLeft = #sweep }
end

GlobalIllumination.DEFAULT_ALBEDO = DEFAULT_ALBEDO

return GlobalIllumination
