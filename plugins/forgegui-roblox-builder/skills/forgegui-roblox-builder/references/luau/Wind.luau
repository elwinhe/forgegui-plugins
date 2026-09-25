--!strict
-- Wind: one shared wind field for everything that moves in the air.
-- Ship as a ModuleScript (ReplicatedStorage.Wind) and start it once per client:
--
--   local Wind = require(ReplicatedStorage.Wind)
--   Wind.start({ prevailing = Vector3.new(-1, 0, 0) })   -- blows toward -X
--   local direction, strength, gust = Wind.sample()       -- the wind right now
--   local velocity = Wind.get(somePosition)               -- studs/s at a point
--   Wind.setStorm(1)                                       -- ease into a storm
--
-- WindVfx (ribbons, dust), FoliageSway (trees, shrubs) and any game code read the
-- same numbers, so a gust bends the trees, thickens the dust and speeds the ribbons
-- at the same moment. It also drives Workspace.GlobalWind, which moves terrain
-- grass and every ParticleEmitter with WindAffectsDrag = true.
--
-- Why it is built this way:
-- - The field is a pure function of time. The default clock is
--   Workspace:GetServerTimeNow(), so every client sees the same gust at the same
--   moment without replicating anything. Gusts sit one per `gustSlot` seconds at a
--   hashed time inside the slot, with hashed strengths and attack/decay times, so
--   they arrive irregularly (5-16 s apart at the default slot) yet repeatably.
-- - `get(position)` delays the gust by the distance along the wind divided by
--   `gustTravel`, so a gust visibly rolls across a field instead of switching on
--   everywhere at once. Three hash evaluations: cheap enough per plant or ribbon.
-- - The storm is a 0..1 target eased with a time constant (`stormSeconds`); a
--   storm that switches on in one frame reads as a bug.
-- - Strength is unitless: ~0.25 still air, ~0.7 a strong gust, 1.1-1.4 in a full
--   storm. `speed(strength)` maps it to studs/s (3 + 22 * strength by default),
--   the scale GlobalWind uses.
--
-- Ownership: the module creates no instances. It borrows one property,
-- Workspace.GlobalWind, recording the value it found as the attribute
-- ForgeGUIPrior_GlobalWind on Workspace (first start wins) and marking Workspace
-- with ForgeGUIWind = true while running. stop() restores the prior value and
-- removes both attributes. start() and stop() are idempotent.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

export type Config = {
	prevailing: Vector3, -- horizontal direction the wind blows TOWARD
	veerDegrees: number, -- slow swing of the direction either side of prevailing
	gustSlot: number, -- seconds; one gust per slot at a hashed time
	calm: number, -- base strength between gusts
	gustGain: number, -- strength a full gust adds
	stormStrength: number, -- strength at storm 1
	stormSeconds: number, -- time constant of storm easing
	speedBase: number, -- studs/s at strength 0
	speedGain: number, -- extra studs/s per unit strength
	gustTravel: number, -- studs/s a gust front rolls downwind in get(position)
	setGlobalWind: boolean, -- drive Workspace.GlobalWind
	globalWindStep: number, -- seconds between GlobalWind writes
	seed: number, -- change to decorrelate two fields; equal seeds agree everywhere
	clock: () -> number, -- seconds; must agree across clients for a shared wind
}

local TAU = math.pi * 2
local OWNED_ATTR = "ForgeGUIWind"
local PRIOR_ATTR = "ForgeGUIPrior_GlobalWind"

local DEFAULTS: Config = {
	prevailing = Vector3.new(-1, 0, 0),
	veerDegrees = 25,
	gustSlot = 10.5,
	calm = 0.3,
	gustGain = 0.42,
	stormStrength = 1.1,
	stormSeconds = 6,
	speedBase = 3,
	speedGain = 22,
	gustTravel = 40,
	setGlobalWind = true,
	globalWindStep = 0.1,
	seed = 0,
	clock = function(): number
		return Workspace:GetServerTimeNow()
	end,
}

local Wind = {}
Wind.DEFAULTS = DEFAULTS

local config: Config = table.clone(DEFAULTS)
local current = { direction = DEFAULTS.prevailing, strength = DEFAULTS.calm, gust = 0 }
local stormLevel = 0 -- eased 0..1
local stormTarget = 0
local connection: RBXScriptConnection? = nil
local sinceGlobal = 0

-- A repeatable number in [0, 1) for a seed: every client gets the same one.
local function hash(n: number): number
	local x = math.sin(n * 127.1 + 311.7) * 43758.5453
	return x - math.floor(x)
end

local function flatUnit(v: Vector3): Vector3
	local flat = Vector3.new(v.X, 0, v.Z)
	return if flat.Magnitude > 1e-4 then flat.Unit else Vector3.new(-1, 0, 0)
end

-- The gust envelope (0..1) at time t: slot k holds one gust at a hashed time.
local function gustAt(t: number): number
	local slotLength = config.gustSlot
	local slot = math.floor(t / slotLength)
	local seed = config.seed * 1000.37
	local best = 0
	for k = slot - 1, slot + 1 do
		local h = k + seed
		local peak = (k + 0.25 + 0.5 * hash(h)) * slotLength
		local rise, fall = 1.2 + 1.2 * hash(h + 0.37), 2 + 2 * hash(h + 0.71)
		local x = t - peak
		local shape = if x < 0 then math.exp(-(x / rise) ^ 2) else math.exp(-(x / fall) ^ 2)
		best = math.max(best, shape * (0.45 + 0.55 * hash(h + 0.13)))
	end
	return best
end

local function directionAt(t: number, gust: number): Vector3
	local veer = math.rad(config.veerDegrees) * (0.6 * math.sin(TAU * t / 311) + 0.4 * math.sin(TAU * t / 173 + 1.7))
	veer += 0.1 * gust * math.sin(TAU * t / 5.3) -- a gust swings the direction a little
	return CFrame.Angles(0, veer, 0):VectorToWorldSpace(flatUnit(config.prevailing))
end

local function strengthAt(t: number, gust: number, storm: number): number
	local calm = config.calm + 0.06 * math.sin(TAU * t / 97 + 0.4) + config.gustGain * gust
	calm += 0.05 * gust * math.sin(TAU * t * 1.3)
	local stormy = config.stormStrength + 0.3 * gust
	return calm + (stormy - calm) * storm
end

-- The field at time t for a storm level: (direction, strength, gust). Pure.
function Wind.at(t: number, storm: number?): (Vector3, number, number)
	local gust = gustAt(t)
	return directionAt(t, gust), strengthAt(t, gust, math.clamp(storm or 0, 0, 1)), gust
end

-- Merges `partial` over the current settings (defaults on the first call).
-- Unknown fields and values of the wrong type are ignored with a warning.
function Wind.configure(partial: { [string]: any }?): Config
	if partial then
		local merged = table.clone(config) :: any
		for key, value in partial do
			local default = (DEFAULTS :: any)[key]
			if default == nil or typeof(value) ~= typeof(default) then
				warn(("Wind: config field '%s' ignored (unknown or wrong type)"):format(tostring(key)))
			else
				merged[key] = value
			end
		end
		config = merged :: Config
	end
	return config
end

-- Wind speed in studs/s for a strength (what GlobalWind is set to).
function Wind.speed(strength: number): number
	return config.speedBase + config.speedGain * strength
end

-- The shared wind now: (direction it blows toward, strength, gust 0..1).
-- Before start() it is computed on demand from the clock.
function Wind.sample(): (Vector3, number, number)
	if connection == nil then
		return Wind.at(config.clock(), stormLevel)
	end
	return current.direction, current.strength, current.gust
end

-- Wind velocity (studs/s) at a world position: the gust arrives later downwind.
function Wind.get(position: Vector3): Vector3
	local t = config.clock()
	local direction = if connection then current.direction else directionAt(t, gustAt(t))
	local shifted = t - position:Dot(direction) / math.max(config.gustTravel, 1)
	return direction * Wind.speed(strengthAt(t, gustAt(shifted), stormLevel))
end

-- Storm target 0..1, eased over `stormSeconds`; `instant` jumps straight there.
function Wind.setStorm(level: number, instant: boolean?)
	stormTarget = if level == level then math.clamp(level, 0, 1) else 0
	if instant then
		stormLevel = stormTarget
	end
end

-- 0..1 how far the storm has eased in.
function Wind.storm(): number
	return stormLevel
end

function Wind.isRunning(): boolean
	return connection ~= nil
end

-- One update: eases the storm, refreshes the sample and (every globalWindStep,
-- while started) writes GlobalWind. Public so tests and custom loops can drive it.
function Wind.step(dt: number)
	local seconds = math.max(config.stormSeconds, 1e-3)
	stormLevel += (stormTarget - stormLevel) * (1 - math.exp(-math.max(dt, 0) / seconds))
	local direction, strength, gust = Wind.at(config.clock(), stormLevel)
	current.direction, current.strength, current.gust = direction, strength, gust
	sinceGlobal += dt
	if config.setGlobalWind and connection ~= nil and sinceGlobal >= config.globalWindStep then
		sinceGlobal = 0
		Workspace.GlobalWind = direction * Wind.speed(strength)
	end
end

-- Starts the Heartbeat loop. A second call only applies `partial` config.
function Wind.start(partial: { [string]: any }?)
	Wind.configure(partial)
	if connection then
		return
	end
	if config.setGlobalWind and Workspace:GetAttribute(PRIOR_ATTR) == nil then
		Workspace:SetAttribute(PRIOR_ATTR, Workspace.GlobalWind)
	end
	Workspace:SetAttribute(OWNED_ATTR, true)
	sinceGlobal = config.globalWindStep
	connection = RunService.Heartbeat:Connect(Wind.step)
	Wind.step(0)
end

-- Stops the loop and hands GlobalWind back. Safe to call when not running;
-- returns true when there was something to stop or restore.
function Wind.stop(): boolean
	local conn = connection
	connection = nil
	if conn then
		conn:Disconnect()
	end
	local prior = Workspace:GetAttribute(PRIOR_ATTR)
	if typeof(prior) == "Vector3" then
		Workspace.GlobalWind = prior
	end
	local hadState = conn ~= nil or prior ~= nil or Workspace:GetAttribute(OWNED_ATTR) == true
	Workspace:SetAttribute(PRIOR_ATTR, nil)
	Workspace:SetAttribute(OWNED_ATTR, nil)
	return hadState
end

return Wind
