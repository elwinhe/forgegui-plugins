-- Appended to the reviewed FoliageSway source in place of its final `return FoliageSway`:
--   python plugins/forgegui-roblox-builder/skills/forgegui-roblox-builder/references/tools/paste_module.py \
--     plugins/forgegui-roblox-builder/skills/forgegui-roblox-builder/references/luau/FoliageSway.luau \
--     docs/evidence/foliage-sway-regression.luau > paste.luau
-- Run the result through Studio MCP execute_luau (Edit mode is fine) in an owned test place.
--
-- Covers the borrowed CFrame: a tagged plant moves only while active, records its
-- rest pose as ForgeGUIPrior_CFrame, and is put back exactly by stop(); restoreAll()
-- repairs parts left moved; unanchored parts and untagged models are never moved;
-- stop() is idempotent. Uses a unique tag and a scratch folder, and never yields.
local HttpService = game:GetService("HttpService")
local checks = {}
local tag = "ForgeGUISwayRegression_" .. HttpService:GenerateGUID(false)
local scratch = Instance.new("Folder")
scratch.Name = tag
scratch.Parent = Workspace

local function check(condition: boolean, label: string)
	assert(condition, label)
	table.insert(checks, label)
end

local function block(parent: Instance, name: string, cf: CFrame, anchored: boolean): Part
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Anchored = name, Vector3.new(1, 10, 1), cf, anchored
	p.Parent = parent
	return p
end

local stubWind = {
	sample = function(): (Vector3, number, number)
		return Vector3.new(-1, 0, 0), 1.2, 1
	end,
}

local ok, failure = xpcall(function()
	local origin = Vector3.new(0, 5000, 0)
	local plant = Instance.new("Model")
	plant.Name = "Plant"
	local trunk = block(plant, "Trunk", CFrame.new(origin + Vector3.new(0, 5, 0)), true)
	local crown = block(plant, "Crown", CFrame.new(origin + Vector3.new(0, 11, 0)) * CFrame.Angles(0, 0.3, 0), true)
	local loose = block(plant, "Loose", CFrame.new(origin + Vector3.new(3, 5, 0)), false)
	plant:SetAttribute("SwayProfile", "shrub")
	plant:SetAttribute("SwayBase", origin)
	plant.Parent = scratch
	local bystander = Instance.new("Model")
	local still = block(bystander, "Still", CFrame.new(origin + Vector3.new(8, 5, 0)), true)
	bystander.Parent = scratch
	local rests = { trunk.CFrame, crown.CFrame }
	local stillRest = still.CFrame
	game:GetService("CollectionService"):AddTag(plant, tag)

	local view = CFrame.lookAt(origin + Vector3.new(0, 8, 30), origin + Vector3.new(0, 5, 0))
	FoliageSway.start({ tag = tag, wind = stubWind })
	FoliageSway.start({ tag = tag, wind = stubWind })
	FoliageSway.step(0.6, view)
	FoliageSway.step(0.1, view)
	check(trunk.CFrame ~= rests[1] and crown.CFrame ~= rests[2], "an active plant moves")
	check(trunk:GetAttribute("ForgeGUIPrior_CFrame") == rests[1], "the rest pose is recorded on the part")
	check(crown:GetAttribute("ForgeGUIFoliageSway") == true, "moved parts are marked")
	check(loose:GetAttribute("ForgeGUIFoliageSway") == nil, "unanchored parts are not borrowed")
	check(still.CFrame == stillRest and still:GetAttribute("ForgeGUIFoliageSway") == nil, "untagged models are not moved")
	local reach = (trunk.Position - origin).Magnitude
	check(math.abs(reach - 5) < 0.01, "parts rotate about the plant's base")

	check(FoliageSway.stop() == true, "stop reports it had something to do")
	check(trunk.CFrame == rests[1] and crown.CFrame == rests[2], "stop puts every part back exactly")
	check(trunk:GetAttribute("ForgeGUIPrior_CFrame") == nil and crown:GetAttribute("ForgeGUIFoliageSway") == nil, "stop removes its attributes")
	check(FoliageSway.stop() == false, "a second stop reports nothing to do")

	-- A part left moved (a reloaded copy of the module) is repaired by restoreAll.
	trunk:SetAttribute("ForgeGUIPrior_CFrame", rests[1])
	trunk:SetAttribute("ForgeGUIFoliageSway", true)
	trunk.CFrame = rests[1] * CFrame.Angles(0.2, 0, 0)
	still:SetAttribute("ForgeGUIPrior_CFrame", CFrame.new()) -- not marked as ours: must be ignored
	check(FoliageSway.restoreAll(scratch) == 1, "restoreAll repairs exactly the marked part")
	check(trunk.CFrame == rests[1], "the repaired part is back at rest")
	check(still.CFrame == stillRest, "a part without the ownership mark is left alone")
end, debug.traceback)

FoliageSway.stop()
scratch:Destroy()

if not ok then
	error(`foliage sway regression failed after {#checks} checks:\n{failure}`)
end
print(`foliage sway regression: {#checks} checks passed`)
