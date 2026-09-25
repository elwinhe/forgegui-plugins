-- Appended to the reviewed LightingLab source in place of its final `return LightingLab`:
--   python plugins/forgegui-roblox-builder/skills/forgegui-roblox-builder/references/tools/paste_module.py \
--     plugins/forgegui-roblox-builder/skills/forgegui-roblox-builder/references/luau/LightingLab.luau \
--     docs/evidence/lighting-lab-regression.luau > paste.luau
-- Run the result through Studio MCP execute_luau in Edit mode in an owned test place.
--
-- Covers: every station builds (with an injected `place`); everything the lab makes,
-- and every model `place` returns, is marked; a second build replaces the first;
-- clear() puts the terrain back exactly as found (terrain that was there before
-- stays, air stays air) and removes its sway tags; a same-named stranger folder is
-- never touched; a stranger's instance inside the lab survives clear(); clear() is
-- idempotent. Built far away (origin 20000, 400, -20000) under a scratch folder.
local HttpService = game:GetService("HttpService")
local checks = {}
local scratch = Instance.new("Folder")
scratch.Name = "ForgeGUILightingLabRegression_" .. HttpService:GenerateGUID(false)
scratch.Parent = Workspace
local ORIGIN = Vector3.new(20000, 400, -20000)
local SEED = ORIGIN + Vector3.new(100, -4, 100) -- pre-existing terrain inside the lab's plate
local terrain = Workspace.Terrain

local function check(condition: boolean, label: string)
	assert(condition, label)
	table.insert(checks, label)
end

local function materialAt(position: Vector3): Enum.Material
	local region = Region3.new(position - Vector3.new(2, 2, 2), position + Vector3.new(2, 2, 2)):ExpandToGrid(4)
	local materials = terrain:ReadVoxels(region, 4)
	return materials[1][1][1]
end

local calls = 0
local function place(kind: string, name: string, cframe: CFrame, parent: Instance): Instance?
	calls += 1
	local model = Instance.new("Model")
	model.Name = kind .. "_" .. name
	local block = Instance.new("Part")
	block.Anchored, block.Size = true, Vector3.new(10, 8, 10)
	block.CFrame = cframe + Vector3.new(0, 4, 0)
	block.Parent = model
	model.Parent = parent
	return model
end

local ok, failure = xpcall(function()
	check(materialAt(ORIGIN + Vector3.new(0, -2, 0)) == Enum.Material.Air, "the test region starts empty")
	terrain:FillBlock(CFrame.new(SEED), Vector3.new(8, 8, 8), Enum.Material.Rock)
	local impostor = Instance.new("Folder")
	impostor.Name = "ForgeGUI_LightingLab"
	impostor.Parent = scratch

	local texture = "rbxasset://textures/particles/smoke_main.dds"
	local options: Options = {
		origin = ORIGIN, parent = scratch :: Instance, place = place, props = { "crate" }, windItems = { "tree" },
		detailTexture = texture, tilingTexture = texture,
	}
	local root, report = LightingLab.build(options)
	check(report.terrain == "snapshot", "the terrain region was snapshotted: " .. report.terrain)
	check(#report.built == #LightingLab.STATIONS, ("every station built (skipped: %s)"):format(table.concat(report.skipped, "; ")))
	check(calls == 7, "place was asked for passage, campfire, the wind item, the prop and three buildings")
	check(LightingLab.find(scratch) == root, "find locates the lab by ownership")
	check(materialAt(ORIGIN + Vector3.new(0, -2, 0)) ~= Enum.Material.Air, "the plate is terrain")
	check(root:GetAttribute("ForgeGUILightingLabRoot") == true, "the root is marked")
	for _, child in root:GetChildren() do
		check(child:GetAttribute("ForgeGUILightingLab") == true, "top-level lab instance is marked: " .. child.Name)
		for _, grandchild in child:GetChildren() do
			check(grandchild:GetAttribute("ForgeGUILightingLab") == true, "station member is marked: " .. grandchild:GetFullName())
		end
	end
	local tagged = 0
	for _, instance in game:GetService("CollectionService"):GetTagged("ForgeGUISway") do
		tagged += if instance:IsDescendantOf(root) then 1 else 0
	end
	check(tagged == 6, "the wind station tags four trees, the banner and the kit item for FoliageSway")

	-- A second build replaces the first.
	local again = LightingLab.build(options)
	local labs = 0
	for _, child in scratch:GetChildren() do
		labs += if child:GetAttribute("ForgeGUILightingLabRoot") == true then 1 else 0
	end
	check(labs == 1 and root.Parent == nil, "build twice leaves exactly one lab")

	-- clear() hands everything back.
	check(LightingLab.clear(scratch) == true, "clear reports it found a lab")
	check(again.Parent == nil, "the lab root is gone")
	check(materialAt(ORIGIN + Vector3.new(0, -2, 0)) == Enum.Material.Air, "terrain that was air is air again")
	check(materialAt(SEED) == Enum.Material.Rock, "terrain that was there before the lab is back")
	check(impostor.Parent == scratch, "a same-named stranger folder is untouched")
	check(LightingLab.clear(scratch) == false, "a second clear reports nothing to do")

	-- A stranger's instance inside the lab survives, and the folder stops being claimed.
	local third = LightingLab.build({ origin = ORIGIN, parent = scratch :: Instance, stations = { "bounce" } })
	local stranger = Instance.new("Folder")
	stranger.Name = "CallerOwned"
	stranger.Parent = third
	LightingLab.clear(scratch)
	check(stranger.Parent == third and third.Parent == scratch, "a stranger's instance keeps the lab folder")
	check(third:GetAttribute("ForgeGUILightingLabRoot") == nil, "the kept folder is no longer claimed")
	check(#third:GetChildren() == 1, "only the stranger's instance is left")
	check(materialAt(SEED) == Enum.Material.Rock, "terrain is restored on this path too")
end, debug.traceback)

LightingLab.clear(scratch)
terrain:FillBlock(CFrame.new(SEED), Vector3.new(8, 8, 8), Enum.Material.Air)
scratch:Destroy()

if not ok then
	error(`lighting lab regression failed after {#checks} checks:\n{failure}`)
end
print(`lighting lab regression: {#checks} checks passed`)
