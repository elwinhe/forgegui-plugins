--!strict
-- FireLight: firelight that flickers and throws moving shadows, plus a soft
-- smoke plume and bright embers that drift downwind, on every fire near the
-- camera. Client side.
--   local Fire = require(ReplicatedStorage.FireLight)
--   Fire.start({ shadowLevel = 0.5, getGust = function() return myWind.gust end })
--   Fire.setShadowLevel(1) / Fire.stop()
--
-- A fire source is any BasePart or Attachment tagged `ForgeGUIFire`
-- (CollectionService). Optional attribute FireScale (0.5..3, default 1) sizes
-- the plume and embers. The light is the first PointLight on the source (or on
-- the part an Attachment source sits on); with none, FireLight makes its own.
--
-- How this relates to ParticleRecipes: the `embers` recipe is the static,
-- always-on part of a fire (embers + dark smoke) and replicates from the server.
-- FireLight is the client-side upgrade layered on top while a fire is near: a
-- lighter plume replaces the recipe's `smoke` emitter (switched off while active,
-- its Enabled restored after), brighter embers join the recipe's, and the light
-- flickers. Use both: the recipe for how a fire looks from far away or with this
-- module off, FireLight for the close-up.
--
-- - Flicker: layered noise plus the odd gutter, never a clean sine; the draught
--   (wind gust and strength) lifts it and the ember rate.
-- - Shadows: only the nearest few lights cast them (setShadowLevel: 0 off,
--   < 0.75 low = 4, else high = 8). Measured: 16 shadowed PointLights cost
--   <= 0.5 ms a frame; unshadowed lights are effectively free.
-- - Smoke drift: the plume and embers use WindAffectsDrag, so they lean with
--   workspace.GlobalWind. Keep GlobalWind in step with your own wind and every
--   fire leans the same way as the grass and cloth.
-- Budget: at most `maxActive` fires (nearest first) within `range` are upgraded,
-- re-chosen twice a second; emitters are made once per fire and reused.
--
-- Ownership: emitters, attachments and lights it makes carry
-- ForgeGUIFireLight = true and are the only things stop() destroys. A borrowed
-- light's Brightness, Range and Shadows (and a recipe smoke emitter's Enabled)
-- are recorded as ForgeGUIPrior_<Property> before the first write and put back
-- when the fire leaves range or on stop().

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FireLight = {}

export type Options = {
	tag: string?, -- default "ForgeGUIFire"
	range: number?, -- default 140 studs from the camera
	maxActive: number?, -- default 10
	shadowLevel: number?, -- 0 off, < 0.75 low (4 lights), else high (8); default 0.5
	textures: { smoke: string?, ember: string? }?, -- default engine particle textures
	createLight: boolean?, -- false: fires without a PointLight get none (default true)
	lightColor: Color3?, -- for lights FireLight makes itself
	lightBrightness: number?, -- default 2
	lightRange: number?, -- default 18
	getGust: (() -> number)?, -- 0..1 gustiness of your wind; default 0
	getWind: (() -> Vector3)?, -- default workspace.GlobalWind
	isPaused: (() -> boolean)?, -- true stops emission (pause menus)
	getFocus: (() -> Vector3)?, -- default the camera position
	manual: boolean?, -- true: no Heartbeat connection; call Fire.step(dt) yourself
}

type Fire = {
	source: Instance,
	holder: Attachment,
	light: PointLight?,
	borrowedLight: boolean,
	brightness: number,
	range: number,
	scale: number,
	seed: number,
	smoke: ParticleEmitter?,
	embers: ParticleEmitter?,
	active: boolean,
}
type Candidate = { fire: Fire, distance: number }

local OWNED_ATTR = "ForgeGUIFireLight"
local PRIOR_PREFIX = "ForgeGUIPrior_"
local DEFAULT_TAG = "ForgeGUIFire"
local LEAVE_MARGIN = 15 -- hysteresis on the range
local PICK_STEP = 0.5
local SMOKE_RATE, EMBER_RATE = 5, 7
local SHADOW_BUDGET = { low = 4, high = 8 }
local WIND_REFERENCE = 20 -- studs/s of wind that counts as a strong draught
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local LIGHT_PROPS = { "Brightness", "Range", "Shadows" }

local opts: Options = {}
local fires: { [Instance]: Fire } = {}
local activeList: { Fire } = {}
local connections: { RBXScriptConnection } = {}
local shadowLevel = 0.5
local sincePick = PICK_STEP
local running = false

local function kp(t: number, v: number): NumberSequenceKeypoint
	return NumberSequenceKeypoint.new(t, v)
end

local function own(instance: Instance)
	instance:SetAttribute(OWNED_ATTR, true)
end

local function remember(instance: Instance, property: string)
	local key = PRIOR_PREFIX .. property
	if instance:GetAttribute(key) == nil then
		instance:SetAttribute(key, (instance :: any)[property])
	end
end

local function restore(instance: Instance, property: string)
	local key = PRIOR_PREFIX .. property
	local value = instance:GetAttribute(key)
	if value ~= nil then
		(instance :: any)[property] = value
		instance:SetAttribute(key, nil)
	end
end

-- Emitters ------------------------------------------------------------------------------

local function emitter(holder: Attachment, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	own(e)
	e.Rate = 0
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = holder
	return e
end

-- A soft plume that starts hidden in the flame and spreads as it rises. The
-- engine's soft smoke reads as real smoke; painted sprites with dark outlines
-- read as a cartoon cloud up close.
local function makeSmoke(fire: Fire): ParticleEmitter
	local s = fire.scale
	local textures = opts.textures
	return emitter(fire.holder, {
		Name = "ForgeGUI_FireSmoke", Texture = textures and textures.smoke or TEX_SMOKE,
		EmissionDirection = Enum.NormalId.Top,
		Color = ColorSequence.new(Color3.fromRGB(176, 166, 156), Color3.fromRGB(214, 208, 200)),
		Size = NumberSequence.new({ kp(0, 0.8 * s), kp(0.5, 2.6 * s), kp(1, 4.8 * s) }),
		Transparency = NumberSequence.new({ kp(0, 1), kp(0.15, 0.8), kp(0.6, 0.88), kp(1, 1) }),
		Lifetime = NumberRange.new(3.5, 5.5), Speed = NumberRange.new(2.5, 4.5), SpreadAngle = Vector2.new(8, 8),
		Acceleration = Vector3.new(0, 1.1, 0), Drag = 0.35, WindAffectsDrag = true,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-14, 14), LightInfluence = 0.85, ZOffset = -0.4,
	})
end

-- Bright embers flung up and carried off downwind. A streak texture wants
-- VelocityParallel; the engine sparkle is round, so it faces the camera.
local function makeEmbers(fire: Fire): ParticleEmitter
	local root = math.sqrt(fire.scale)
	local textures = opts.textures
	local streak = textures and textures.ember
	return emitter(fire.holder, {
		Name = "ForgeGUI_FireEmbers", Texture = streak or TEX_SPARK, EmissionDirection = Enum.NormalId.Top,
		Orientation = if streak then Enum.ParticleOrientation.VelocityParallel else Enum.ParticleOrientation.FacingCamera,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 236, 170)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 150, 60)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(210, 60, 20)),
		}),
		Size = NumberSequence.new({ kp(0, 0.32 * root), kp(0.7, 0.22 * root), kp(1, 0) }),
		Transparency = NumberSequence.new({ kp(0, 0), kp(0.75, 0.15), kp(1, 1) }),
		Lifetime = NumberRange.new(1.5, 2.8), Speed = NumberRange.new(4, 8), SpreadAngle = Vector2.new(22, 22),
		Acceleration = Vector3.new(0, 2.5, 0), Drag = 0.9, WindAffectsDrag = true,
		LightEmission = 1, LightInfluence = 0, Brightness = 2.2,
	})
end

-- Registration ----------------------------------------------------------------------------

local function sourcePart(source: Instance): BasePart?
	if source:IsA("BasePart") then
		return source
	end
	local parent = source.Parent
	return if parent and parent:IsA("BasePart") then parent else nil
end

local function holderFor(source: Instance): Attachment?
	if source:IsA("Attachment") then
		return source -- borrowed: only our own children are added to it
	end
	local part = sourcePart(source)
	if not part then
		return nil
	end
	local holder = Instance.new("Attachment")
	own(holder)
	holder.Name = "ForgeGUI_FireLight"
	holder.Position = Vector3.new(0, part.Size.Y / 2, 0)
	holder.Parent = part
	return holder
end

local function lightFor(source: Instance, holder: Attachment): (PointLight?, boolean)
	local found = source:FindFirstChildOfClass("PointLight")
	local part = sourcePart(source)
	if not found and part then
		found = part:FindFirstChildOfClass("PointLight")
	end
	if found or opts.createLight == false then
		return found, found ~= nil
	end
	local light = Instance.new("PointLight")
	own(light)
	light.Color = opts.lightColor or Color3.fromRGB(255, 170, 90)
	light.Brightness = opts.lightBrightness or 2
	light.Range = opts.lightRange or 18
	light.Shadows = false
	light.Parent = holder
	return light, false
end

local function register(source: Instance)
	if fires[source] or not (source:IsA("BasePart") or source:IsA("Attachment")) then
		return
	end
	local holder = holderFor(source)
	if not holder then
		return
	end
	local light, borrowed = lightFor(source, holder)
	local scale = source:GetAttribute("FireScale")
	local at = holder.WorldPosition
	fires[source] = {
		source = source, holder = holder, light = light, borrowedLight = borrowed,
		brightness = if light then light.Brightness else 0, range = if light then light.Range else 0,
		scale = math.clamp(if type(scale) == "number" then scale else 1, 0.5, 3),
		seed = (at.X * 0.37 + at.Z * 0.13) % 97,
		smoke = nil, embers = nil, active = false,
	}
end

-- The ParticleRecipes `embers` smoke on this fire: off while our plume runs.
local function recipeSmoke(fire: Fire): { ParticleEmitter }
	local list: { ParticleEmitter } = {}
	local root: Instance = sourcePart(fire.source) or fire.source
	for _, d in root:GetDescendants() do
		if d:IsA("ParticleEmitter") and d:GetAttribute("ForgeGUIRecipe") == "embers" and string.find(string.lower(d.Name), "smoke") then
			table.insert(list, d)
		end
	end
	return list
end

local function activate(fire: Fire)
	fire.active = true
	fire.smoke = fire.smoke or makeSmoke(fire)
	fire.embers = fire.embers or makeEmbers(fire)
	for _, smoke in recipeSmoke(fire) do
		remember(smoke, "Enabled")
		smoke.Enabled = false
	end
	local light = fire.light
	if light and fire.borrowedLight then
		for _, property in LIGHT_PROPS do
			remember(light, property)
		end
	end
end

local function deactivate(fire: Fire)
	fire.active = false
	local smoke, embers = fire.smoke, fire.embers
	if smoke then
		smoke.Rate = 0
	end
	if embers then
		embers.Rate = 0
	end
	for _, recipe in recipeSmoke(fire) do
		restore(recipe, "Enabled")
	end
	local light = fire.light
	if not light then
		return
	end
	if fire.borrowedLight then
		for _, property in LIGHT_PROPS do
			restore(light, property)
		end
	else
		light.Brightness, light.Range, light.Shadows = fire.brightness, fire.range, false
	end
end

-- Everything FireLight made for this fire goes; borrowed things are put back.
local function forget(fire: Fire)
	deactivate(fire)
	for _, child in fire.holder:GetChildren() do
		if child:GetAttribute(OWNED_ATTR) == true then
			child:Destroy()
		end
	end
	if fire.holder:GetAttribute(OWNED_ATTR) == true then
		fire.holder:Destroy()
	end
	fires[fire.source] = nil
	local at = table.find(activeList, fire)
	if at then
		table.remove(activeList, at)
	end
end

-- Choosing the active set ---------------------------------------------------------------

local function shadowBudget(): number
	if shadowLevel <= 0.01 then
		return 0
	end
	return if shadowLevel < 0.75 then SHADOW_BUDGET.low else SHADOW_BUDGET.high
end

local function pick(eye: Vector3)
	local range = opts.range or 140
	local candidates: { Candidate } = {}
	for _, fire in fires do
		local distance = (fire.holder.WorldPosition - eye).Magnitude
		if fire.source:IsDescendantOf(Workspace) and distance <= range + (if fire.active then LEAVE_MARGIN else 0) then
			table.insert(candidates, { fire = fire, distance = distance })
		end
	end
	table.sort(candidates, function(a: Candidate, b: Candidate)
		return a.distance < b.distance
	end)
	local chosen: { Fire } = {}
	local chosenSet: { [Fire]: boolean } = {}
	for i = 1, math.min(#candidates, opts.maxActive or 10) do
		local fire = candidates[i].fire
		chosen[i], chosenSet[fire] = fire, true
		if not fire.active then
			activate(fire)
		end
	end
	for _, fire in activeList do
		if not chosenSet[fire] and fire.active then
			deactivate(fire)
		end
	end
	local budget = shadowBudget()
	for i, fire in chosen do
		local light = fire.light
		if light then
			light.Shadows = i <= budget
		end
	end
	activeList = chosen
end

-- Frame ---------------------------------------------------------------------------------

-- Layered noise with occasional gutters: 0.55 .. 1.25 around 1.
local function flicker(t: number, seed: number): number
	local slow = math.noise(t * 1.7, seed, 0.3)
	local fast = math.noise(t * 7.3, seed, 4.1)
	local gutter = math.max(0, math.noise(t * 0.9, seed, 9.7) - 0.25) * 1.6
	return math.clamp(1 + 0.22 * slow + 0.12 * fast - gutter, 0.55, 1.25)
end

local function draught(): number
	local getGust, getWind = opts.getGust, opts.getWind
	local gust = if getGust then math.clamp(getGust(), 0, 1) else 0
	local wind = if getWind then getWind() else Workspace.GlobalWind
	return 1 + 0.35 * gust + 0.15 * math.min(wind.Magnitude / WIND_REFERENCE, 1.5)
end

local function animate()
	if #activeList == 0 then
		return
	end
	local now = os.clock()
	local d = draught()
	local isPaused = opts.isPaused
	local paused = isPaused ~= nil and isPaused()
	for _, fire in activeList do
		local k = flicker(now, fire.seed)
		local light = fire.light
		if light then
			light.Brightness = fire.brightness * k * (0.9 + 0.1 * d)
			light.Range = fire.range * (0.93 + 0.07 * k)
		end
		local smoke, embers = fire.smoke, fire.embers
		if smoke then
			smoke.Rate = if paused then 0 else math.min(SMOKE_RATE * fire.scale, 10)
		end
		if embers then
			embers.Rate = if paused then 0 else math.min(EMBER_RATE * fire.scale * d * k, 22)
		end
	end
end

-- Lifecycle -------------------------------------------------------------------------------

function FireLight.step(dt: number)
	if not running then
		return
	end
	sincePick += dt
	local getter = opts.getFocus
	local camera = Workspace.CurrentCamera
	local eye = if getter then getter() elseif camera then camera.CFrame.Position else nil
	if sincePick >= PICK_STEP and eye then
		sincePick = 0
		pick(eye)
	end
	animate()
end

function FireLight.setShadowLevel(value: number)
	shadowLevel = math.clamp(if value == value then value else 0.5, 0, 1)
	sincePick = PICK_STEP -- re-pick on the next step so the budget applies at once
end

-- Idempotent: a second start while running does nothing (stop first to change options).
function FireLight.start(options: Options?): boolean
	if running then
		return false
	end
	running = true
	opts = options or {}
	FireLight.setShadowLevel(opts.shadowLevel or shadowLevel)
	local tag = opts.tag or DEFAULT_TAG
	for _, source in CollectionService:GetTagged(tag) do
		register(source)
	end
	table.insert(connections, CollectionService:GetInstanceAddedSignal(tag):Connect(register))
	table.insert(connections, CollectionService:GetInstanceRemovedSignal(tag):Connect(function(source: Instance)
		local fire = fires[source]
		if fire then
			forget(fire)
		end
	end))
	if not opts.manual then
		table.insert(connections, RunService.Heartbeat:Connect(FireLight.step))
	end
	return true
end

function FireLight.stop(): boolean
	if not running then
		return false
	end
	running = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, fire in fires do
		forget(fire)
	end
	table.clear(fires)
	table.clear(activeList)
	return true
end

function FireLight.stats(): { [string]: number }
	local known, shadowed = 0, 0
	for _ in fires do
		known += 1
	end
	for _, fire in activeList do
		if fire.light and fire.light.Shadows then
			shadowed += 1
		end
	end
	return { fires = known, active = #activeList, shadowed = shadowed }
end

return FireLight
