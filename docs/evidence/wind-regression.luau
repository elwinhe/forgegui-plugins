-- Appended to the reviewed Wind source in place of its final `return Wind`:
--   python plugins/forgegui-roblox-builder/skills/forgegui-roblox-builder/references/tools/paste_module.py \
--     plugins/forgegui-roblox-builder/skills/forgegui-roblox-builder/references/luau/Wind.luau \
--     docs/evidence/wind-regression.luau > paste.luau
-- Run the result through Studio MCP execute_luau (Edit mode is fine) in an owned test place.
--
-- Covers: the field is a pure, bounded function of time; the storm dial clamps and
-- eases; get() is a velocity along the wind; start() records GlobalWind once and
-- is idempotent; stop() restores it, removes its attributes and is idempotent; a
-- prior left by an interrupted run is the one restored.
-- The place is left as it was found, whether the checks pass or fail.
local checks = {}
local placeWind = Workspace.GlobalWind
local placePrior = Workspace:GetAttribute("ForgeGUIPrior_GlobalWind")

local function check(condition: boolean, label: string)
	assert(condition, label)
	table.insert(checks, label)
end

local function near(a: number, b: number, label: string)
	check(math.abs(a - b) < 1e-4, `{label} (expected {b}, got {a})`)
end

check(Workspace:GetAttribute("ForgeGUIWind") == nil, "no wind is running in the test place yet")

local ok, failure = xpcall(function()
	Wind.configure({ clock = function(): number
		return 5000
	end })

	-- 1. A pure, bounded field.
	local d1, s1, g1 = Wind.at(12345.678)
	local d2, s2, g2 = Wind.at(12345.678)
	check(d1 == d2 and s1 == s2 and g1 == g2, "the field is a pure function of time")
	near(d1.Magnitude, 1, "the direction is a unit vector")
	near(d1.Y, 0, "the direction is horizontal")
	local low, high = 1, 0
	for t = 0, 1800, 0.5 do
		local _, _, gust = Wind.at(t)
		low, high = math.min(low, gust), math.max(high, gust)
	end
	check(low >= 0 and high <= 1, "gusts stay within 0..1 over half an hour")
	check(high > 0.4, "strong gusts do happen within half an hour")
	local _, calm = Wind.at(777, 0)
	local _, stormy = Wind.at(777, 1)
	check(stormy > calm and stormy >= Wind.DEFAULTS.stormStrength, "a full storm is stronger than calm air")

	-- 2. The storm dial.
	Wind.setStorm(5, true)
	near(Wind.storm(), 1, "setStorm clamps above 1")
	Wind.setStorm(-2, true)
	near(Wind.storm(), 0, "setStorm clamps below 0")
	Wind.setStorm(0 / 0, true)
	near(Wind.storm(), 0, "setStorm treats NaN as 0")
	Wind.setStorm(1)
	Wind.step(Wind.DEFAULTS.stormSeconds)
	near(Wind.storm(), 1 - math.exp(-1), "the storm eases in with its time constant")
	Wind.setStorm(0, true)

	-- 3. get() is a velocity along the wind.
	local direction, strength = Wind.sample()
	local velocity = Wind.get(Vector3.new(50, 0, 0))
	check(velocity.Magnitude >= Wind.speed(0), "get returns at least the base wind speed")
	near(velocity.Unit:Dot(direction), 1, "get points along the sampled direction")
	near(Wind.speed(strength), Wind.DEFAULTS.speedBase + Wind.DEFAULTS.speedGain * strength, "speed maps strength to studs/s")

	-- 4. start/stop borrow GlobalWind and hand it back.
	Workspace:SetAttribute("ForgeGUIPrior_GlobalWind", nil)
	Workspace.GlobalWind = Vector3.new(1, 2, 3)
	Wind.start()
	Wind.start()
	check(Wind.isRunning(), "start runs the loop")
	check(Workspace:GetAttribute("ForgeGUIWind") == true, "Workspace is marked while the wind runs")
	check(Workspace:GetAttribute("ForgeGUIPrior_GlobalWind") == Vector3.new(1, 2, 3), "the prior GlobalWind is recorded")
	check(Workspace.GlobalWind ~= Vector3.new(1, 2, 3), "start writes GlobalWind")
	check(Wind.stop() == true, "stop reports it had something to do")
	check(Workspace.GlobalWind == Vector3.new(1, 2, 3), "stop restores GlobalWind")
	check(Workspace:GetAttribute("ForgeGUIWind") == nil, "stop removes the running mark")
	check(Workspace:GetAttribute("ForgeGUIPrior_GlobalWind") == nil, "stop removes the prior")
	check(Wind.stop() == false, "a second stop reports nothing to do")

	-- 5. A prior left by an interrupted run is the value that comes back.
	Workspace:SetAttribute("ForgeGUIPrior_GlobalWind", Vector3.new(4, 0, 0))
	Workspace.GlobalWind = Vector3.new(9, 9, 9)
	Wind.start()
	Wind.stop()
	check(Workspace.GlobalWind == Vector3.new(4, 0, 0), "an earlier prior wins over the current value")
end, debug.traceback)

Wind.stop()
Wind.configure({ clock = Wind.DEFAULTS.clock })
Workspace.GlobalWind = placeWind
Workspace:SetAttribute("ForgeGUIPrior_GlobalWind", placePrior)
Workspace:SetAttribute("ForgeGUIWind", nil)

if not ok then
	error(`wind regression failed after {#checks} checks:\n{failure}`)
end
print(`wind regression: {#checks} checks passed`)
for _, label in checks do
	print("  ok", label)
end
