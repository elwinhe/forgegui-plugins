--!strict
-- CameraFx: camera motion blur, frame blending and a resting depth of field, all
-- through ONE DepthOfFieldEffect, updated once a frame after every camera writer
-- (RenderPriority.Last). Client only: require it from a LocalScript.
--
-- 	local CameraFx = require(path.to.CameraFx)
-- 	CameraFx.start({ motionBlur = 0.5, frameBlending = 0.5, depthOfField = true })
-- 	CameraFx.setMotionBlur(0) -- the player's slider, 0..1
-- 	CameraFx.stop()
--
-- Why a depth of field and not a BlurEffect. Unreal's camera motion blur smears
-- each pixel along its own screen velocity, so the character the camera orbits
-- stays sharp while the world sweeping past smears. Roblox has no velocity
-- buffer, but for an orbiting camera screen speed depends on depth alone: a
-- point at distance d from a lens orbiting a pivot f studs away at w rad/s moves
-- at w * |1 - f / d| across the screen. That is zero at the pivot and grows in
-- front of and behind it: exactly the shape of a depth of field focused on the
-- pivot. So while the camera turns (or the pivot rushes along) the effect
-- tightens its in-focus band round the pivot and raises near and far blur to
-- the smear Unreal would draw:
-- 	smear (share of screen width) = amount * screen speed / (30 * hFov)
-- with Unreal's defaults: amount 0.5, a 30 fps reference frame, at most 5 % of
-- the screen. No dead zone: a slow pan smears faintly, a whip smears hard. A
-- short attack/release smoothing stops mouse jitter flickering it, and a frame
-- where the camera jumps (a cut, a respawn) is dropped instead of flashing. A
-- full-screen BlurEffect was the first attempt and was retired: it blurs the
-- subject too, which reads as a smudged lens rather than motion.
--
-- Frame blending: the blur this frame is the average of the motion over the
-- last 1, 3 or 6 frames (Off / Low / High), the way blended frames accumulate a
-- shutter: a flick leaves a short trail instead of a one-frame pulse. It costs
-- nothing on the GPU; it is arithmetic on two numbers.
--
-- Resting depth of field: the focus follows the camera-to-subject distance with
-- a wide in-focus band, so the player and anything near stays sharp and only
-- the distance softens. The far blur fades out as the camera closes in on the
-- subject (a first-person camera gets none). During a cinematic shot (the
-- `cinematic` callback returns a point) the focus moves to that point with a
-- stronger far blur that eases back afterwards.
--
-- Ownership. There is one depth of field per view: a second enabled one stacks.
-- So the module adopts the place's DepthOfFieldEffect if it has one (Lighting
-- first, then the camera), tagging it ForgeGUICameraFxAdopted = true and
-- recording each property it drives as ForgeGUICameraFxPrior_<Property> (a
-- prefix distinct from LightingPresets' ForgeGUIPrior_, so neither module's
-- clear restores the other's values). With none, it creates one under the
-- current camera tagged ForgeGUICameraFx = true; LightingPresets only scans
-- Lighting, so it never adopts ours. stop() destroys only what carries the
-- owned tag and puts adopted properties back to the last value anyone else
-- wrote (so a preset applied mid-run survives; its ForgeGUIPrior_ record of
-- our driven value is rewritten to the value underneath). stop() on a fresh require (the
-- Studio MCP's execute_luau gets fresh module instances) still sweeps the
-- attributes, so a crashed session can be cleaned up.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CameraFx = {}

export type Look = { far: number, radius: number }
export type Options = {
	motionBlur: number?, -- amount 0..1 (0 off); Unreal's default 0.5
	frameBlending: number?, -- 0 off (1 frame), 0.5 low (3), 1 high (6)
	depthOfField: boolean?, -- the resting blur; motion blur works without it
	-- A cinematic shot's subject and optional look; nil when no shot is running.
	cinematic: (() -> (Vector3?, Look?))?,
	-- The play pivot; default Camera.Focus.Position (what the default camera orbits).
	subject: (() -> Vector3?)?,
	-- True while a modal, pause menu or cut-scene should get no motion blur.
	isSuppressed: (() -> boolean)?,
}

type Layer = { instance: Instance, property: string, base: any, written: any, ownsPrior: boolean }

local RENDER_NAME = "ForgeGUICameraFx"
local OWNED_ATTR = "ForgeGUICameraFx"
local ADOPTED_ATTR = "ForgeGUICameraFxAdopted"
local PRIOR_PREFIX = "ForgeGUICameraFxPrior_"
local DRIVEN = { "Enabled", "FocusDistance", "InFocusRadius", "NearIntensity", "FarIntensity" }

local PLAY: Look = { far = 0.1, radius = 38 }
local SHOT: Look = { far = 0.25, radius = 24 }
local CLOSE_FROM, CLOSE_TO = 2.5, 8 -- camera-to-subject studs over which the far blur fades in
local FOCUS_RATE, LOOK_RATE = 8, 3 -- per second
local FOCUS_SNAP = 60 -- a focus jump this big (a cut) is taken at once
local MAX_FOCUS, MAX_RADIUS = 200, 50 -- DepthOfFieldEffect's own limits

-- Unreal's motion blur defaults (r.MotionBlur.TargetFPS, Max, Amount).
local TARGET_FPS = 30
local MAX_SMEAR = 0.05 -- share of the screen width
local DEFAULT_AMOUNT = 0.5
local SMEAR_INTENSITY = 0.9 -- a full 5 % smear maps to this intensity (1 is Roblox's heaviest)
local FAR_DEPTH, FAR_MIN = 3, 60 -- the background: max(3f, 60) studs
local NEAR_DEPTH, NEAR_MIN = 0.6, 3 -- what passes between lens and pivot: max(0.6f, 3)
local SHARP_SHARE, SHARP_MIN = 0.35, 2 -- the sharp band round the pivot while moving: +-(0.35f + 2)
local MOVING_FULL = 0.15 -- motion intensity at which the band is fully closed
local ATTACK_RATE, RELEASE_RATE = 24, 12 -- per second: the shutter smoothing
local CUT_ANGLE, CUT_DISTANCE = math.rad(50), 40 -- per-frame jumps treated as cuts
local MIN_DT, MAX_DT = 1 / 240, 0.1
local EPSILON = 1e-3
local BLEND_LOW, BLEND_HIGH = 3, 6

local settings = { amount = DEFAULT_AMOUNT, blend = 0.5, rest = true }
local callbacks: Options = {}
local started = false

local dof: DepthOfFieldEffect? = nil
local activeCamera: Camera? = nil
local cameraConnection: RBXScriptConnection? = nil
local layers: { Layer } = {}
local focus = 12
local far, radius = 0, PLAY.radius
local motionFar, motionNear = 0, 0
local lastLook: Vector3? = nil
local lastPivot: Vector3? = nil
local history: { Vector2 } = {} -- recent (far, near) motion targets, newest last

-- Borrowed properties --------------------------------------------------------------

local function borrow(instance: Instance, property: string): Layer
	local key = PRIOR_PREFIX .. property
	local value = (instance :: any)[property]
	local ownsPrior = instance:GetAttribute(key) == nil
	if ownsPrior then
		instance:SetAttribute(key, value)
	end
	return { instance = instance, property = property, base = value, written = nil, ownsPrior = ownsPrior }
end

-- A property of an instance this module created: no prior, nothing to restore.
local function ownedLayer(instance: Instance, property: string): Layer
	return { instance = instance, property = property, base = nil, written = nil, ownsPrior = false }
end

local function same(a: any, b: any): boolean
	if type(a) == "number" and type(b) == "number" then
		return math.abs(a - b) <= EPSILON
	end
	return a == b
end

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

-- Writes only on a real change; a value someone else wrote meanwhile becomes the base.
local function write(layer: Layer, value: any)
	local target = layer.instance :: any
	local current = target[layer.property]
	if layer.written ~= nil and current ~= layer.written then
		correctForeignPriors(layer.instance, layer.property, layer.written, layer.base)
		layer.base = current
		if layer.ownsPrior then
			layer.instance:SetAttribute(PRIOR_PREFIX .. layer.property, current)
		end
	end
	if not same(current, value) then
		target[layer.property] = value
		current = target[layer.property]
	end
	layer.written = current
end

local function release(layer: Layer)
	local target = layer.instance :: any
	if layer.written ~= nil then
		correctForeignPriors(layer.instance, layer.property, layer.written, layer.base)
	end
	if layer.base ~= nil and layer.written ~= nil and target[layer.property] == layer.written then
		target[layer.property] = layer.base
	end
	if layer.ownsPrior then
		layer.instance:SetAttribute(PRIOR_PREFIX .. layer.property, nil)
	end
end

-- The effect -------------------------------------------------------------------------

local function findPlaceDof(camera: Camera): DepthOfFieldEffect?
	for _, parent in { Lighting :: Instance, camera :: Instance } do
		for _, child in parent:GetChildren() do
			if child:IsA("DepthOfFieldEffect") and child:GetAttribute(OWNED_ATTR) ~= true then
				return child
			end
		end
	end
	return nil
end

local function resolveDof(camera: Camera): DepthOfFieldEffect
	for _, child in camera:GetChildren() do
		if child:IsA("DepthOfFieldEffect") and child:GetAttribute(OWNED_ATTR) == true then
			for _, property in DRIVEN do
				table.insert(layers, ownedLayer(child, property))
			end
			return child
		end
	end
	local adopted = findPlaceDof(camera)
	if adopted then
		adopted:SetAttribute(ADOPTED_ATTR, true)
		for _, property in DRIVEN do
			table.insert(layers, borrow(adopted, property))
		end
		return adopted
	end
	local made = Instance.new("DepthOfFieldEffect")
	made.Name = "ForgeGUI_CameraFx"
	made.NearIntensity = 0
	made.FarIntensity = 0
	made.Enabled = false
	made:SetAttribute(OWNED_ATTR, true)
	made.Parent = camera
	for _, property in DRIVEN do
		table.insert(layers, ownedLayer(made, property))
	end
	return made
end

local function drive(property: string, value: any)
	for _, layer in layers do
		if layer.property == property then
			write(layer, value)
			return
		end
	end
end

local function releaseDof()
	for _, layer in layers do
		release(layer)
	end
	local effect = dof
	if effect then
		if effect:GetAttribute(OWNED_ATTR) == true then
			effect:Destroy()
		else
			effect:SetAttribute(ADOPTED_ATTR, nil)
		end
	end
	layers, dof = {}, nil
end

local function changeCamera(camera: Camera?)
	if camera == activeCamera then
		return
	end
	releaseDof()
	activeCamera = camera
	focus, far, radius, motionFar, motionNear = 12, 0, PLAY.radius, 0, 0
	lastLook, lastPivot, history = nil, nil, {}
end

local function currentDof(camera: Camera): DepthOfFieldEffect
	changeCamera(camera)
	local effect = dof
	if effect and (effect.Parent == Lighting or effect.Parent == camera) then
		return effect
	end
	releaseDof()
	local resolved = resolveDof(camera)
	dof = resolved
	return resolved
end

-- Resting depth of field ------------------------------------------------------------

local function lensTarget(camera: Camera): (Vector3, Look, number)
	local cinematic = callbacks.cinematic
	if cinematic then
		local point, look = cinematic()
		if point then
			return point, look or SHOT, 1
		end
	end
	local subject = callbacks.subject
	local pivot = (subject and subject()) or camera.Focus.Position
	local distance = (camera.CFrame.Position - pivot).Magnitude
	return pivot, PLAY, math.clamp((distance - CLOSE_FROM) / (CLOSE_TO - CLOSE_FROM), 0, 1)
end

local function stepFocus(camera: Camera, pivot: Vector3, look: Look, strength: number, dt: number)
	local target = math.clamp((camera.CFrame.Position - pivot).Magnitude, 0, MAX_FOCUS)
	if math.abs(target - focus) > FOCUS_SNAP then
		focus = target
	else
		focus += (target - focus) * (1 - math.exp(-FOCUS_RATE * dt))
	end
	local k = 1 - math.exp(-LOOK_RATE * dt)
	local restFar = if settings.rest then look.far * strength else 0
	far += (restFar - far) * k
	radius = math.min(MAX_RADIUS, radius + (look.radius - radius) * k)
end

-- Motion blur ----------------------------------------------------------------------------

local function horizontalFov(camera: Camera): number
	local size = camera.ViewportSize
	local aspect = if size.Y > 0 then size.X / size.Y else 16 / 9
	return 2 * math.atan(math.tan(math.rad(camera.FieldOfView) / 2) * aspect)
end

-- Screen speed (rad/s) to Unreal's smear, then to a depth-of-field intensity.
function CameraFx.intensityFor(speed: number, amount: number, hFov: number): number
	local smear = math.min(MAX_SMEAR, amount * speed / (TARGET_FPS * hFov))
	return SMEAR_INTENSITY * smear / MAX_SMEAR
end

local function suppressed(): boolean
	local check = callbacks.isSuppressed
	return check ~= nil and check()
end

-- This frame's far and near motion intensities (0 on a cut or a hitch).
local function motionTarget(camera: Camera, pivot: Vector3, dt: number): (number, number)
	local look = camera.CFrame.LookVector
	local previousLook, previousPivot = lastLook, lastPivot
	lastLook, lastPivot = look, pivot
	if settings.amount <= 0 or not previousLook or not previousPivot or dt > MAX_DT or suppressed() then
		return 0, 0
	end
	local turned = math.acos(math.clamp(look:Dot(previousLook), -1, 1))
	local shifted = (pivot - previousPivot).Magnitude
	if turned > CUT_ANGLE or shifted > CUT_DISTANCE then
		motionFar, motionNear = 0, 0
		table.clear(history) -- a cut starts a new shutter
		return 0, 0
	end
	local frame = math.max(dt, MIN_DT)
	local turnRate, pivotSpeed = turned / frame, shifted / frame
	local f = math.max(focus, 1)
	local farDepth, nearDepth = math.max(f * FAR_DEPTH, FAR_MIN), math.max(f * NEAR_DEPTH, NEAR_MIN)
	-- w * |1 - f/d| for the orbit, plus the pivot's own travel seen at that depth.
	local farSpeed = turnRate * math.abs(1 - f / farDepth) + pivotSpeed / farDepth
	local nearSpeed = turnRate * math.abs(1 - f / nearDepth) + pivotSpeed / nearDepth
	local hFov = horizontalFov(camera)
	return CameraFx.intensityFor(farSpeed, settings.amount, hFov), CameraFx.intensityFor(nearSpeed, settings.amount, hFov)
end

-- Frames averaged for a frame-blending level (0 / 0.5 / 1 = Off / Low / High).
function CameraFx.blendFrames(level: number): number
	if level <= 0.01 then
		return 1
	end
	return if level < 0.75 then BLEND_LOW else BLEND_HIGH
end

local function accumulate(targetFar: number, targetNear: number): (number, number)
	table.insert(history, Vector2.new(targetFar, targetNear))
	local keep = CameraFx.blendFrames(settings.blend)
	while #history > keep do
		table.remove(history, 1)
	end
	local sum = Vector2.zero
	for _, sample in history do
		sum += sample
	end
	return sum.X / #history, sum.Y / #history
end

local function smooth(current: number, target: number, dt: number): number
	local rate = if target > current then ATTACK_RATE else RELEASE_RATE
	local value = current + (target - current) * (1 - math.exp(-rate * dt))
	return if value < 0.005 then 0 else value
end

-- Frame ----------------------------------------------------------------------------------

-- One frame. Public so tests and custom render loops can drive it.
function CameraFx.step(camera: Camera?, dt: number)
	changeCamera(camera)
	if not camera then
		return
	end
	currentDof(camera)
	local pivot, look, strength = lensTarget(camera)
	stepFocus(camera, pivot, look, strength, dt)
	local targetFar, targetNear = accumulate(motionTarget(camera, pivot, dt))
	motionFar, motionNear = smooth(motionFar, targetFar, dt), smooth(motionNear, targetNear, dt)

	-- While moving, the sharp band closes round the pivot so only it stays crisp.
	local moving = math.clamp(math.max(motionFar, motionNear) / MOVING_FULL, 0, 1)
	local sharp = math.min(MAX_RADIUS, focus * SHARP_SHARE + SHARP_MIN)
	local farIntensity = math.max(far, motionFar)
	local on = farIntensity > EPSILON or motionNear > EPSILON
	drive("Enabled", on)
	if not on then
		return
	end
	drive("FocusDistance", focus)
	drive("InFocusRadius", radius + (sharp - radius) * moving)
	drive("FarIntensity", farIntensity)
	drive("NearIntensity", motionNear)
end

-- Settings -------------------------------------------------------------------------------

local function unit(value: any, fallback: number): number
	return if type(value) == "number" and value == value then math.clamp(value, 0, 1) else fallback
end

function CameraFx.setMotionBlur(amount: number)
	settings.amount = unit(amount, DEFAULT_AMOUNT)
end

function CameraFx.setFrameBlending(level: number)
	settings.blend = unit(level, 0.5)
end

function CameraFx.setDepthOfField(on: boolean)
	settings.rest = on ~= false
end

-- The effect being driven (nil before the first frame).
function CameraFx.effect(): DepthOfFieldEffect?
	return dof
end

-- The current motion intensities (far, near), for tests and debug overlays.
function CameraFx.motion(): (number, number)
	return motionFar, motionNear
end

-- Start / stop -----------------------------------------------------------------------------

local function restoreAttributes(child: Instance)
	for key, value in child:GetAttributes() do
		if string.sub(key, 1, #PRIOR_PREFIX) == PRIOR_PREFIX then
			local property = string.sub(key, #PRIOR_PREFIX + 1)
			pcall(function()
				(child :: any)[property] = value
			end)
			child:SetAttribute(key, nil)
		end
	end
	child:SetAttribute(ADOPTED_ATTR, nil)
end

-- Cleans up after a session that never called stop() (or a fresh require).
local function sweep()
	local parents: { Instance } = { Lighting }
	local camera = Workspace.CurrentCamera
	if camera then
		table.insert(parents, camera)
	end
	for _, parent in parents do
		for _, child in parent:GetChildren() do
			if child:GetAttribute(OWNED_ATTR) == true then
				child:Destroy()
			elseif child:GetAttribute(ADOPTED_ATTR) == true then
				restoreAttributes(child)
			end
		end
	end
end

function CameraFx.start(options: Options?)
	local opts: Options = options or {}
	callbacks = opts
	settings.amount = unit(opts.motionBlur, DEFAULT_AMOUNT)
	settings.blend = unit(opts.frameBlending, 0.5)
	settings.rest = opts.depthOfField ~= false
	if started then
		return
	end
	started = true
	sweep() -- leftovers from a session that never stopped
	cameraConnection = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		changeCamera(Workspace.CurrentCamera)
	end)
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Last.Value, function(dt: number)
		local camera = Workspace.CurrentCamera
		CameraFx.step(camera, dt)
	end)
end

function CameraFx.stop()
	if started then
		RunService:UnbindFromRenderStep(RENDER_NAME)
		started = false
	end
	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end
	releaseDof()
	activeCamera = nil
	sweep()
	focus, far, radius, motionFar, motionNear = 12, 0, PLAY.radius, 0, 0
	lastLook, lastPivot, history = nil, nil, {}
end

return CameraFx
