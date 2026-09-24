-- Surface realism regression: MaterialKit, DetailGrain, KeepOut and GroundScatter.
-- Build the standalone script with the four modules ahead of this runner, then run it
-- through Studio MCP execute_luau in Edit, in an owned test place. From the repo root:
--
--   S=plugins/forgegui-roblox-builder/skills/forgegui-roblox-builder/references
--   python $S/tools/paste_module.py $S/luau/MaterialKit.luau $S/luau/DetailGrain.luau \
--       $S/luau/KeepOut.luau $S/luau/GroundScatter.luau docs/evidence/surface-realism-regression.luau > paste.luau
--
-- It asserts ownership (only tagged instances are ever destroyed, same-named strangers
-- survive), restore (overrides and terrain colours come back, clear/stop leave nothing
-- behind), idempotence (a second apply/start does not stack), and the placement rules
-- (footprint, protrude, keep-out, trunk share).
--
-- The place is left as it was found: terrain in the test region is read first and
-- written back at the end, and every module is cleared, whether it passed or failed.
local HttpService = game:GetService("HttpService")
local MaterialService = game:GetService("MaterialService")
local Terrain = workspace.Terrain
local checks = {}

local function check(condition: boolean, label: string)
	assert(condition, label)
	table.insert(checks, label)
end

local function near(actual: number, expected: number, tolerance: number, label: string)
	check(math.abs(actual - expected) <= tolerance, `{label} (expected {expected}, got {actual})`)
end

local scratch = Instance.new("Folder")
scratch.Name = "ForgeGUISurfaceRegression_" .. HttpService:GenerateGUID(false)
scratch.Parent = workspace

-- A far corner of the map for the terrain tests; multiples of 4 so fills align to voxels.
local ORIGIN = Vector3.new(12000, 100, -12000)
local region = Region3.new(ORIGIN - Vector3.new(96, 12, 96), ORIGIN + Vector3.new(96, 12, 96)):ExpandToGrid(4)
local savedMaterials, savedOccupancy = Terrain:ReadVoxels(region, 4)
local priorOverride = MaterialService:GetBaseMaterialOverride(Enum.Material.Sand)
local priorSandColor = Terrain:GetMaterialColor(Enum.Material.Sand)
check(MaterialService:GetAttribute("ForgeGUIMaterialKit") == nil, "the test place has no MaterialKit applied yet")

local function materialKitChecks()
	local stranger = Instance.new("MaterialVariant")
	stranger.Name = "ForgeGUIRegression_Stranger"
	stranger.BaseMaterial = Enum.Material.Rock
	stranger.StudsPerTile = 7
	stranger.Parent = MaterialService
	local specs: { any } = {
		{ name = "ForgeGUIRegression_Sand", base = Enum.Material.Sand, studsPerTile = 18, terrainColor = Color3.fromRGB(250, 238, 222) },
		{ name = "ForgeGUIRegression_Stranger", base = Enum.Material.Rock, studsPerTile = 30 },
		{ name = "ForgeGUIRegression_Cloth", base = Enum.Material.Fabric, override = false, terrainColor = Color3.new(1, 1, 1) },
		{ name = "ForgeGUIRegression_Bad", base = "Sand" },
	}
	local report = MaterialKit.apply(specs)
	check(table.find(report.created, "ForgeGUIRegression_Sand") ~= nil and table.find(report.created, "ForgeGUIRegression_Cloth") ~= nil, "valid specs create owned variants")
	check(#report.failed == 1, "a spec with a non-Material base is reported as failed")
	local strangerSkipped = false
	for _, note in ipairs(report.skipped) do
		strangerSkipped = strangerSkipped or string.find(note, "ForgeGUIRegression_Stranger", 1, true) == 1
	end
	check(strangerSkipped, "a name held by a variant it did not create is reported as skipped")
	check(stranger.StudsPerTile == 7 and stranger:GetAttribute("ForgeGUIMaterialKit") == nil, "a same-named stranger variant is not touched")
	check(MaterialService:GetBaseMaterialOverride(Enum.Material.Sand) == "ForgeGUIRegression_Sand", "override = true sets the base material override")
	check(MaterialService:GetBaseMaterialOverride(Enum.Material.Fabric) ~= "ForgeGUIRegression_Cloth", "override = false leaves the base material alone")
	check(Terrain:GetMaterialColor(Enum.Material.Sand) == Color3.fromRGB(250, 238, 222), "terrainColor is applied")
	check(MaterialService:GetAttribute("ForgeGUIMaterialKitPriorOverride_Sand") == priorOverride, "the prior override is recorded")
	check(Terrain:GetAttribute("ForgeGUIMaterialKitPriorColor_Sand") == priorSandColor, "the prior terrain colour is recorded")

	specs[1].studsPerTile = 20
	specs[1].terrainColor = Color3.fromRGB(200, 200, 200)
	local again = MaterialKit.apply(specs)
	check(table.find(again.updated, "ForgeGUIRegression_Sand") ~= nil and #again.created == 0, "a second apply reconfigures, it does not create")
	local sand: MaterialVariant? = MaterialKit.owned().ForgeGUIRegression_Sand
	check(sand ~= nil and sand.StudsPerTile == 20, "the reconfigured variant carries the new values")
	check(Terrain:GetAttribute("ForgeGUIMaterialKitPriorColor_Sand") == priorSandColor, "the first prior survives a second apply")

	check(MaterialKit.clear() == true, "clear reports it had something to do")
	check(MaterialService:GetBaseMaterialOverride(Enum.Material.Sand) == priorOverride, "the override is restored")
	check(Terrain:GetMaterialColor(Enum.Material.Sand) == priorSandColor, "the terrain colour is restored")
	check(next(MaterialKit.owned()) == nil, "every owned variant is destroyed")
	check(stranger.Parent == MaterialService, "the stranger survives clear")
	check(MaterialService:GetAttribute("ForgeGUIMaterialKitPriorOverride_Sand") == nil and Terrain:GetAttribute("ForgeGUIMaterialKitPriorColor_Sand") == nil, "restored priors are cleaned up")
	check(MaterialKit.clear() == false, "clear on a clean place reports nothing to do")
	stranger:Destroy()
end

local function ownedTextures(root: Instance): { Texture }
	local list = {}
	for _, item in ipairs(root:GetDescendants()) do
		if item:IsA("Texture") and item:GetAttribute("ForgeGUIDetailGrain") == true then
			table.insert(list, item)
		end
	end
	return list
end

local function detailGrainChecks()
	local house = Instance.new("Model")
	house.Name = "House"
	for i = 1, 2 do
		local mesh = Instance.new("MeshPart")
		mesh.Anchored = true
		mesh.Size = Vector3.new(10, 8, 10)
		mesh.Position = Vector3.new(i * 12, 4, 0)
		mesh.Parent = house
	end
	local plain = Instance.new("Part")
	plain.Anchored = true
	plain.Parent = house
	local strangerTexture = Instance.new("Texture")
	strangerTexture.Name = "DetailGrain"
	strangerTexture.Parent = plain
	house.Parent = scratch

	local layers = DetailGrain.grain("rbxassetid://1", "rbxassetid://2")
	check(DetailGrain.apply(house, { layers = layers }) == 20, "grain puts 2 layers on 5 faces of each MeshPart")
	local made = ownedTextures(house)
	local seen: { [number]: boolean } = {}
	local bottom = false
	for _, texture in ipairs(made) do
		seen[math.floor(texture.Transparency * 100 + 0.5)] = true
		bottom = bottom or texture.Face == Enum.NormalId.Bottom
		check(texture.StudsPerTileU == 3 and texture.StudsPerTileV == 3, "grain tiles at 3 studs")
	end
	check(#made == 20 and not bottom, "no layer goes on the bottom face")
	check(seen[15] == true and seen[30] == true, "dark at 0.15 and light at 0.3 transparency")
	check(#plain:GetChildren() == 1, "primitive Parts are skipped by default")
	check(DetailGrain.apply(house, { layers = layers }) == 20 and #ownedTextures(house) == 20, "a second apply replaces rather than stacks")
	check(DetailGrain.apply(house, { layers = DetailGrain.blend("rbxassetid://3") }) == 10, "the tiled material blend is one layer")
	check(DetailGrain.apply(house, { layers = layers, classes = { "BasePart" } }) == 30, "classes widens the target set")
	check(not pcall(DetailGrain.apply, house, { layers = {} }), "empty layers are refused")
	check(DetailGrain.clear(house) == 30 and #ownedTextures(house) == 0, "clear removes every owned texture")
	check(strangerTexture.Parent == plain, "a same-named texture it did not make survives")
end

local function testModel(name: string, position: Vector3, size: Vector3): Model
	local holder = Instance.new("Model")
	holder.Name = name
	local part = Instance.new("Part")
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Parent = holder
	holder.Parent = scratch
	return holder
end

local function keepOutChecks()
	local zone = KeepOut.new({ trunkShare = { palm = 0.12 } })
	zone.register(CFrame.new(0, 5, 0), Vector3.new(20, 10, 20))
	check(zone.blocked(CFrame.new(5, 1, 5), Vector3.new(2, 2, 2)), "a crate inside a house is blocked")
	check(not zone.blocked(CFrame.new(11.2, 1, 0), Vector3.new(2, 2, 2)), "a crate leaning on the wall is allowed")

	zone.register(CFrame.new(50, 5, 0) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(40, 10, 2))
	check(zone.blocked(CFrame.new(57.07, 1, -7.07), Vector3.new(2, 2, 2)), "a crate on a rotated wall is blocked")
	check(not zone.blocked(CFrame.new(57, 1, 7), Vector3.new(2, 2, 2)), "a crate inside the rotated wall's axis-aligned box but off the wall is allowed")

	local gate = testModel("gate", Vector3.new(100, 5, 0), Vector3.new(8, 10, 20))
	zone.registerPassage(gate, "X", 14, 5)
	check(zone.blocked(CFrame.new(114, 1, 0), Vector3.new(2, 2, 2)), "the walkway in front of a gate is kept clear")
	check(not zone.blocked(CFrame.new(124, 1, 0), Vector3.new(2, 2, 2)), "beyond the approach length is free")

	local palm = testModel("palm", Vector3.new(14, 8, 0), Vector3.new(16, 16, 16))
	check(not zone.blockedModel(palm), "a palm is tested by its trunk, so its crown may overhang the roof")
	check(KeepOut.new().collect(scratch, function(m)
		return m.Name == "gate"
	end) == 1, "collect registers the models the filter accepts")
	local plainZone = KeepOut.new()
	plainZone.register(CFrame.new(0, 5, 0), Vector3.new(20, 10, 20))
	check(plainZone.blockedModel(palm), "without a trunk share the same crown is blocked")
	palm:SetAttribute("KeepOutTrunk", 0.12)
	check(not plainZone.blockedModel(palm), "a KeepOutTrunk attribute works without a name table")
	plainZone.reset()
	check(plainZone.count() == 0 and not plainZone.blocked(CFrame.new(5, 1, 5), Vector3.new(2, 2, 2)), "reset empties the zone")
end

local function fillTestGround()
	Terrain:FillBlock(CFrame.new(ORIGIN - Vector3.new(0, 4, 0)), Vector3.new(176, 8, 176), Enum.Material.Sand)
	-- A 64-stud Ground square west of the origin, and an 8-stud Ground road east of it.
	Terrain:FillBlock(CFrame.new(ORIGIN + Vector3.new(-40, -4, 0)), Vector3.new(64, 8, 64), Enum.Material.Ground)
	Terrain:FillBlock(CFrame.new(ORIGIN + Vector3.new(24, -4, 0)), Vector3.new(8, 8, 64), Enum.Material.Ground)
	-- Measured in Studio: freshly filled terrain is not raycastable until the next
	-- physics step, so a scatter started in the same frame finds no ground at all.
	local probe = RaycastParams.new()
	probe.FilterType = Enum.RaycastFilterType.Include
	probe.FilterDescendantsInstances = { Terrain }
	for _ = 1, 120 do
		local hit = workspace:Raycast(ORIGIN + Vector3.new(-40, 60, 0), Vector3.new(0, -120, 0), probe)
		if hit and hit.Material == Enum.Material.Ground then
			return
		end
		task.wait()
	end
	error("the test ground never became raycastable")
end

local function patchPositions(folder: Instance): { string }
	local list = {}
	for _, patch in ipairs(folder:GetChildren()) do
		local p = (patch :: Model):GetPivot().Position
		table.insert(list, ("%.2f,%.2f"):format(p.X, p.Z))
	end
	table.sort(list)
	return list
end

local function ownedFolders(): { Instance }
	local list = {}
	for _, child in ipairs(scratch:GetChildren()) do
		if child:GetAttribute("ForgeGUIGroundScatter") == true then
			table.insert(list, child)
		end
	end
	return list
end

local function runScatter(template: Model): Instance?
	GroundScatter.start({
		kinds = { [Enum.Material.Ground] = { template = template, tint = Color3.fromRGB(200, 100, 50) } },
		manual = true,
		parent = scratch,
		radius = 90,
		castTop = ORIGIN.Y + 60,
		castDepth = 120,
	})
	for _ = 1, 400 do
		GroundScatter.step(ORIGIN)
		if GroundScatter.stats().queued == 0 then
			break
		end
	end
	return ownedFolders()[1]
end

local function checkPatch(model: Model, ray: RaycastParams)
	local box, size = model:GetBoundingBox()
	local hit = workspace:Raycast(Vector3.new(box.Position.X, ORIGIN.Y + 60, box.Position.Z), Vector3.new(0, -120, 0), ray)
	check(hit ~= nil and hit.Material == Enum.Material.Ground, "every patch stands on Ground")
	check(box.Position.X < ORIGIN.X, "no patch is laid on the narrow Ground road (footprint rule)")
	near(box.Position.Y + size.Y / 2 - (hit :: RaycastResult).Position.Y, 0.45, 0.15, "a patch protrudes 0.45 studs")
	local part = model:FindFirstChildWhichIsA("BasePart") :: BasePart
	check(not part.CanCollide and not part.CanQuery and not part.CanTouch, "patches are visual only")
	check(part.Color == Color3.fromRGB(200, 100, 50), "the tint reaches a patch without a SurfaceAppearance")
	check(model:GetAttribute("ForgeGUIGroundScatter") == true, "every patch is owned")
end

local function groundScatterChecks()
	fillTestGround()
	local template = Instance.new("Model")
	template.Name = "MudPatch"
	local slab = Instance.new("Part")
	slab.Size = Vector3.new(12, 0.6, 12)
	slab.Parent = template
	template.PrimaryPart = slab

	local made = runScatter(template)
	check(made ~= nil and #ownedFolders() == 1, "start makes one owned folder")
	local folder = made :: Instance
	local first = patchPositions(folder)
	check(#first > 0 and GroundScatter.stats().patches == #first, "patches are laid on the Ground square")
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Include
	ray.FilterDescendantsInstances = { Terrain }
	for _, patch in ipairs(folder:GetChildren()) do
		checkPatch(patch :: Model, ray)
	end

	local again = runScatter(template)
	check(again ~= nil and #ownedFolders() == 1, "starting again does not stack a second set")
	check(table.concat(patchPositions(again :: Instance), ";") == table.concat(first, ";"), "cells are world-snapped: the same patches land in the same places")

	-- Crossing into the next cell re-plans; cells already laid must not be laid again.
	for _ = 1, 400 do
		GroundScatter.step(ORIGIN + Vector3.new(11, 0, 0))
		if GroundScatter.stats().queued == 0 then
			break
		end
	end
	check(#(again :: Instance):GetChildren() == #first, "a re-plan never lays a cell twice")

	GroundScatter.step(ORIGIN + Vector3.new(400, 0, 0))
	local stats = GroundScatter.stats()
	check(stats.patches == 0 and stats.pooled == #first, "moving away returns every patch to the pool")
	check(GroundScatter.stop() == true and #ownedFolders() == 0, "stop removes everything it made")
	check(template.Parent == nil and template:GetAttribute("ForgeGUIGroundScatter") == nil and slab.Color ~= Color3.fromRGB(200, 100, 50), "the caller's template is never touched")
	check(GroundScatter.stop() == false, "stop when stopped reports nothing to do")
end

local ok, failure = xpcall(function()
	materialKitChecks()
	detailGrainChecks()
	keepOutChecks()
	groundScatterChecks()
end, debug.traceback)

-- Hand the place back whatever happened.
pcall(MaterialKit.clear)
pcall(GroundScatter.stop)
pcall(function()
	Terrain:WriteVoxels(region, 4, savedMaterials, savedOccupancy)
end)
scratch:Destroy()

if not ok then
	error(`FAIL surface realism regression after {#checks} checks:\n{failure}`)
end
print(`PASS surface realism regression: {#checks} checks passed`)
