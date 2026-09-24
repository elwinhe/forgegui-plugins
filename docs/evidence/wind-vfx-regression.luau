-- Appended to the reviewed WindVfx source in place of its final `return WindVfx`:
--   python plugins/forgegui-roblox-builder/skills/forgegui-roblox-builder/references/tools/paste_module.py \
--     plugins/forgegui-roblox-builder/skills/forgegui-roblox-builder/references/luau/WindVfx.luau \
--     docs/evidence/wind-vfx-regression.luau > paste.luau
-- Run the result through Studio MCP execute_luau (Edit mode is fine) in an owned test place.
--
-- Covers ownership and cleanup: every instance start() makes is marked; a second
-- start() builds nothing new; a same-named stranger folder is never touched; a
-- stranger's instance inside the owned folder survives stop(), which then stops
-- claiming the folder; stop() is idempotent; a clean restart leaves nothing behind.
-- Also: the palette and texture options reach the emitters, and a paused game
-- spawns nothing. Everything happens under a scratch folder that is removed at the
-- end. The script never yields, so the Heartbeat loop cannot interleave with it.
local HttpService = game:GetService("HttpService")
local checks = {}
local scratch = Instance.new("Folder")
scratch.Name = "ForgeGUIWindVfxRegression_" .. HttpService:GenerateGUID(false)
scratch.Parent = Workspace

local function check(condition: boolean, label: string)
	assert(condition, label)
	table.insert(checks, label)
end

local function ownedRoots(): { Instance }
	local list = {}
	for _, child in scratch:GetChildren() do
		if child:GetAttribute("ForgeGUIWindVfx") == true then
			table.insert(list, child)
		end
	end
	return list
end

local function countClass(root: Instance, className: string): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d.ClassName == className then
			n += 1
		end
	end
	return n
end

-- A stand-in wind: a steady, strong breeze toward -X.
local stubWind = {
	sample = function(): (Vector3, number, number)
		return Vector3.new(-1, 0, 0), 0.9, 0.5
	end,
	speed = function(strength: number): number
		return 3 + 22 * strength
	end,
	storm = function(): number
		return 0
	end,
}
local pausedNow = false

local ok, failure = xpcall(function()
	local impostor = Instance.new("Folder")
	impostor.Name = "ForgeGUI_WindVfx"
	impostor.Parent = scratch

	local leaf = "rbxasset://textures/particles/smoke_main.dds"
	local options: Options = {
		parent = scratch :: Instance, wind = stubWind, palette = "snow", ribbons = 5, crests = 2,
		textures = { leaf = leaf }, isPaused = function(): boolean
			return pausedNow
		end,
	}
	WindVfx.start(options)
	WindVfx.start(options)
	local roots = ownedRoots()
	check(#roots == 1, "start twice builds exactly one owned folder")
	local root = roots[1]
	check(countClass(root, "Trail") == 5, "the ribbon pool has the requested size")
	check(#root:GetChildren() == 5 + 2 + 3, "5 ribbons, 2 crest emitters and 3 dust volumes")
	for _, d in root:GetDescendants() do
		check(d:GetAttribute("ForgeGUIWindVfx") == true, "created instance is marked: " .. d:GetFullName())
	end
	local wisps = root:FindFirstChild("GroundWisps", true)
	assert(wisps and wisps:IsA("ParticleEmitter"), "the wisp emitter exists")
	check(wisps.Color.Keypoints[1].Value == WindVfx.PALETTES.snow.dustLight, "the palette reaches the wisps")
	local leaves = root:FindFirstChild("Leaves", true)
	check(leaves ~= nil and leaves:IsA("ParticleEmitter") and leaves.Texture == leaf, "a leaf texture enables the leaf emitter")

	-- Drive a few frames by hand; a paused game spawns nothing.
	pausedNow = true
	for _ = 1, 10 do
		WindVfx.step(0.1)
	end
	check(wisps.Rate == 0, "paused: the wisps stop")
	for _, trail in root:GetDescendants() do
		if trail:IsA("Trail") then
			check(trail.Enabled == false, "paused: no ribbon spawned")
		end
	end
	pausedNow = false
	for _ = 1, 10 do
		WindVfx.step(0.1)
	end

	-- A stranger's instance inside our folder survives stop().
	local stranger = Instance.new("Folder")
	stranger.Name = "CallerOwned"
	stranger.Parent = root
	check(WindVfx.stop() == true, "stop reports it had something to do")
	check(stranger.Parent == root and root.Parent == scratch, "a stranger's instance keeps its folder")
	check(root:GetAttribute("ForgeGUIWindVfx") == nil, "the kept folder is no longer claimed")
	check(#root:GetChildren() == 1, "only the stranger's instance is left in it")
	check(impostor.Parent == scratch, "a same-named stranger folder is untouched")
	check(WindVfx.stop() == false, "a second stop reports nothing to do")
	check(not WindVfx.isRunning(), "the loop is stopped")

	-- A clean cycle leaves nothing of ours behind.
	WindVfx.start({ parent = scratch :: Instance, wind = stubWind })
	check(#ownedRoots() == 1, "restart builds one owned folder")
	WindVfx.stop()
	check(#ownedRoots() == 0, "stop leaves no owned folder behind")
end, debug.traceback)

WindVfx.stop()
scratch:Destroy()

if not ok then
	error(`wind vfx regression failed after {#checks} checks:\n{failure}`)
end
print(`wind vfx regression: {#checks} checks passed`)
