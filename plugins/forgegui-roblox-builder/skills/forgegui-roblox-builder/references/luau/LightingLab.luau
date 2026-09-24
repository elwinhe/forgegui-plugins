--!strict
-- LightingLab: a lighting and VFX test lab on a flat plate far outside the world.
-- Run on the server (a Script, or execute_luau in Edit):
--
--   local LightingLab = require(ServerStorage.LightingLab)
--   local lab, report = LightingLab.build({
--       origin = Vector3.new(6000, 0, 0),
--       place = function(kind, name, cframe, parent)       -- optional: your game's kit
--           local source = ServerStorage.Kit:FindFirstChild(name)
--           if not source then return nil end
--           local copy = source:Clone(); copy:PivotTo(cframe); copy.Parent = parent
--           return copy
--       end,
--   })
--   print(report.built, report.skipped, report.spawn)
--   LightingLab.clear()   -- removes the lab and puts the terrain back
--
-- Why a lab: a look change judged in the live world is judged against whatever
-- happened to be in shot. The lab puts the same references side by side in the
-- same light, so a before/after capture differs only by the change. Stations,
-- each signed:
--   materials  balls (plastic white/grey/black/red/blue, metal, glass, neon) and a
--              swatch per MaterialVariant in MaterialService
--   terrain    one strip per terrain material (tiling and colour at a glance)
--   bounce     a white and a red wall in a sunlit corner under a roof (GI colour bleed)
--   passage    a covered walk-through (interior darkness, contact shadow); or your kit's
--   pond       terrain water with red/white/blue pillars on the bank (reflections)
--   fire       braziers (Fire + shadowed PointLight) against a wall (fire shadows)
--   wind       primitive trees, a shrub and a banner tagged ForgeGUISway (FoliageSway,
--              WindVfx); plus any kit items named in `windItems`
--   props      crates, barrels, rocks (contact shadows); plus kit items named in `props`
--   tiling     A/B/C: the same kit building as placed, with a fine detail texture, and
--              with a tiled texture blended over it (needs `place`; skipped otherwise)
-- Stations that need game assets are optional: without `place` they use
-- primitives or are skipped, and the report says which.
--
-- Ownership: every instance it creates (and every model `place` returns) carries
-- ForgeGUILightingLab = true under one root Folder that also carries
-- ForgeGUILightingLabRoot = true. Terrain is borrowed: before filling anything the
-- lab copies the whole region it will touch into an owned TerrainRegion, and
-- clear() pastes it back, so a lab built over existing terrain leaves it as found.
-- build() clears an earlier lab first, so it is idempotent. Nothing is ever
-- destroyed by name, and a stranger's instance inside the root survives clear().

local CollectionService = game:GetService("CollectionService")
local MaterialService = game:GetService("MaterialService")
local Workspace = game:GetService("Workspace")

export type PlaceFn = (kind: string, name: string, cframe: CFrame, parent: Instance) -> Instance?
export type Options = {
	origin: Vector3?, -- lab centre, default (6000, 0, 0); keep it clear of the world
	half: number?, -- half size of the plate in studs, default 240 (min 200)
	groundMaterial: Enum.Material?, -- default Ground
	stations: { string }?, -- default all of LightingLab.STATIONS
	place: PlaceFn?, -- game kit placement, called with (station, item name, cframe, parent)
	parent: Instance?, -- default Workspace
	terrainMaterials: { Enum.Material }?,
	materialVariants: { string }?, -- default every MaterialVariant in MaterialService (max 16)
	windItems: { string }?, -- kit names placed at the wind station
	props: { string }?, -- kit names placed at the props station
	detailTexture: string?, -- tiling station B overlay (rbxassetid)
	tilingTexture: string?, -- tiling station C overlay (rbxassetid)
	swayTag: string?, -- default "ForgeGUISway"
}
export type Report = {
	origin: Vector3,
	spawn: CFrame,
	built: { string },
	skipped: { string }, -- "station: reason"
	terrain: string, -- "snapshot" | "part plate (reason)"
	instances: number,
}
type Ctx = { origin: Vector3, options: Options, root: Folder, report: Report, terrain: boolean }

local OWNED_ATTR = "ForgeGUILightingLab"
local ROOT_ATTR = "ForgeGUILightingLabRoot"
local CORNER_ATTR = "ForgeGUILabTerrainCorner"
local VOXEL = 4
local WHITE, RED, BLUE = Color3.fromRGB(235, 232, 226), Color3.fromRGB(190, 40, 30), Color3.fromRGB(40, 90, 200)
local WOOD = Color3.fromRGB(96, 72, 52)

local STATIONS = { "materials", "terrain", "bounce", "passage", "pond", "fire", "wind", "props", "tiling" }
local DEFAULT_TERRAIN: { Enum.Material } = {
	Enum.Material.Grass, Enum.Material.LeafyGrass, Enum.Material.Ground, Enum.Material.Mud, Enum.Material.Sand,
	Enum.Material.Sandstone, Enum.Material.Rock, Enum.Material.Slate, Enum.Material.Basalt, Enum.Material.Limestone,
	Enum.Material.Snow, Enum.Material.Glacier, Enum.Material.Salt, Enum.Material.Pavement, Enum.Material.Concrete,
	Enum.Material.Asphalt, Enum.Material.Cobblestone, Enum.Material.Brick, Enum.Material.WoodPlanks,
}

local LightingLab = {}
LightingLab.STATIONS = STATIONS

-- Helpers --------------------------------------------------------------------------------

local function own<T>(instance: T): T
	(instance :: any):SetAttribute(OWNED_ATTR, true)
	return instance
end

local function at(ctx: Ctx, x: number, z: number, y: number?): Vector3
	return ctx.origin + Vector3.new(x, y or 0, z)
end

local function swayTag(ctx: Ctx): string
	return ctx.options.swayTag or "ForgeGUISway"
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, material: Enum.Material, colour: Color3): Part
	local p = own(Instance.new("Part"))
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Material = material
	p.Color = colour
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function station(ctx: Ctx, name: string): Model
	local model = own(Instance.new("Model"))
	model.Name = "Station_" .. name
	model.Parent = ctx.root
	return model
end

-- A two-sided signboard with its text on both faces.
local function sign(parent: Instance, position: Vector3, size: Vector2, text: string)
	local dark = Color3.fromRGB(28, 28, 30)
	local board = part(parent, "Sign", Vector3.new(size.X, size.Y, 0.4), CFrame.new(position), Enum.Material.SmoothPlastic, dark)
	board.CanCollide, board.CastShadow = false, false
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = own(Instance.new("SurfaceGui"))
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		local label = own(Instance.new("TextLabel"))
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.Text = text
		label.Parent = gui
		gui.Parent = board
	end
end

-- A kit item from the injected `place`, marked as the lab's own. nil when there is
-- no `place`, it returned nothing, or it errored (the error goes in the report).
local function placed(ctx: Ctx, kind: string, name: string, cf: CFrame, parent: Instance): Instance?
	local placeFn = ctx.options.place
	if not placeFn then
		return nil
	end
	local ok, result = pcall(placeFn, kind, name, cf, parent)
	if not ok then
		table.insert(ctx.report.skipped, ("%s/%s: place() errored: %s"):format(kind, name, tostring(result)))
		return nil
	end
	if typeof(result) ~= "Instance" then
		return nil
	end
	own(result)
	if not result:IsDescendantOf(parent) then
		result.Parent = parent
	end
	return result
end

-- Terrain ------------------------------------------------------------------------------------

local function voxel(v: Vector3): Vector3int16
	return Vector3int16.new(math.floor(v.X / VOXEL), math.floor(v.Y / VOXEL), math.floor(v.Z / VOXEL))
end

-- Copies the region the lab will fill into an owned TerrainRegion under the root.
local function snapshot(ctx: Ctx, half: number): (boolean, string?)
	local lo = ctx.origin + Vector3.new(-half - 8, -16, -half - 8)
	local hi = ctx.origin + Vector3.new(half + 8, 24, half + 8)
	local region = Region3int16.new(voxel(lo), voxel(hi))
	local ok, copy = pcall(function()
		return Workspace.Terrain:CopyRegion(region)
	end)
	if not ok or not copy then
		return false, tostring(copy)
	end
	own(copy)
	copy.Name = "TerrainSnapshot"
	copy.Parent = ctx.root
	local min = region.Min
	ctx.root:SetAttribute(CORNER_ATTR, Vector3.new(min.X, min.Y, min.Z))
	return true, nil
end

local function plate(ctx: Ctx, half: number)
	local material = ctx.options.groundMaterial or Enum.Material.Ground
	if ctx.terrain then
		Workspace.Terrain:FillBlock(CFrame.new(at(ctx, 0, 0, -4)), Vector3.new(half * 2, 8, half * 2), material)
		return
	end
	local grey = Color3.fromRGB(150, 146, 140)
	part(ctx.root, "Plate", Vector3.new(half * 2, 2, half * 2), CFrame.new(at(ctx, 0, 0, -1)), Enum.Material.Concrete, grey)
end

-- Stations -----------------------------------------------------------------------------------

local function variantNames(ctx: Ctx): { string }
	local names = ctx.options.materialVariants
	if names then
		return names
	end
	local found: { string } = {}
	for _, d in MaterialService:GetDescendants() do
		if d:IsA("MaterialVariant") then
			table.insert(found, d.Name)
		end
	end
	table.sort(found)
	return found
end

local function materials(ctx: Ctx)
	local model = station(ctx, "materials")
	local plastic = Enum.Material.SmoothPlastic
	local balls: { { material: Enum.Material, colour: Color3 } } = {
		{ material = plastic, colour = Color3.fromRGB(240, 240, 240) },
		{ material = plastic, colour = Color3.fromRGB(128, 128, 128) },
		{ material = plastic, colour = Color3.fromRGB(24, 24, 24) },
		{ material = plastic, colour = RED },
		{ material = plastic, colour = BLUE },
		{ material = Enum.Material.Metal, colour = Color3.fromRGB(200, 200, 205) },
		{ material = Enum.Material.Glass, colour = Color3.fromRGB(180, 220, 230) },
		{ material = Enum.Material.Neon, colour = Color3.fromRGB(255, 170, 60) },
	}
	for i, spec in balls do
		local cf = CFrame.new(at(ctx, -150 + i * 8, -110, 2.5))
		local ball = part(model, "Ball", Vector3.new(5, 5, 5), cf, spec.material, spec.colour)
		ball.Shape = Enum.PartType.Ball
	end
	for i, name in variantNames(ctx) do
		if i > 16 then
			break
		end
		local cf = CFrame.new(at(ctx, -150 + i * 9, -126, 3.5))
		local swatch = part(model, "Swatch_" .. name, Vector3.new(7, 7, 1), cf, plastic, Color3.new(1, 1, 1))
		local variant = MaterialService:FindFirstChild(name, true)
		if variant and variant:IsA("MaterialVariant") then
			swatch.Material = variant.BaseMaterial
			swatch.MaterialVariant = name
		end
	end
	sign(model, at(ctx, -110, -100, 3), Vector2.new(16, 3), "MATERIALS: balls and variant swatches")
end

local function terrainStrip(ctx: Ctx)
	local model = station(ctx, "terrain")
	local list: { Enum.Material } = ctx.options.terrainMaterials or DEFAULT_TERRAIN
	local step = 22
	local start = -((#list - 1) * step) / 2
	for i, material in list do
		local centre = at(ctx, start + (i - 1) * step, -170, -4)
		local ok = pcall(function()
			Workspace.Terrain:FillBlock(CFrame.new(centre), Vector3.new(20, 8, 40), material)
		end)
		if ok then
			sign(model, centre + Vector3.new(0, 6, 22), Vector2.new(12, 2), string.upper(material.Name))
		end
	end
	sign(model, at(ctx, 0, -145, 4), Vector2.new(16, 3), "TERRAIN: one strip per material")
end

local function bounce(ctx: Ctx)
	local model = station(ctx, "bounce")
	local plastic = Enum.Material.SmoothPlastic
	part(model, "WhiteWall", Vector3.new(24, 14, 1), CFrame.new(at(ctx, -80, 40, 7)), plastic, WHITE)
	part(model, "RedWall", Vector3.new(1, 14, 24), CFrame.new(at(ctx, -92, 52, 7)), plastic, RED)
	part(model, "Roof", Vector3.new(24, 1, 12), CFrame.new(at(ctx, -80, 46, 14.5)), plastic, WHITE)
	sign(model, at(ctx, -80, 30, 3), Vector2.new(14, 3), "BOUNCE: red bleeds onto white")
end

local function passage(ctx: Ctx)
	local model = station(ctx, "passage")
	if not placed(ctx, "passage", "passage", CFrame.new(at(ctx, 0, 40)), model) then
		local wall, plaster = Color3.fromRGB(200, 190, 175), Enum.Material.Plaster
		part(model, "WallL", Vector3.new(2, 12, 28), CFrame.new(at(ctx, -6, 40, 6)), plaster, wall)
		part(model, "WallR", Vector3.new(2, 12, 28), CFrame.new(at(ctx, 6, 40, 6)), plaster, wall)
		part(model, "Roof", Vector3.new(14, 1.5, 28), CFrame.new(at(ctx, 0, 40, 12.75)), plaster, wall)
	end
	sign(model, at(ctx, 0, 18, 3), Vector2.new(14, 3), "PASSAGE: walk through")
end

local function pond(ctx: Ctx)
	if not ctx.terrain then
		table.insert(ctx.report.skipped, "pond: needs terrain water (terrain snapshot failed)")
		return
	end
	local model = station(ctx, "pond")
	local centre, radius = at(ctx, 60, 80), 16
	local terrain = Workspace.Terrain
	terrain:FillCylinder(CFrame.new(centre + Vector3.new(0, -3, 0)), 6, radius + 2, Enum.Material.Air)
	terrain:FillCylinder(CFrame.new(centre + Vector3.new(0, -3.2, 0)), 5.6, radius, Enum.Material.Water)
	terrain:FillCylinder(CFrame.new(centre + Vector3.new(0, -7, 0)), 2, radius + 2, ctx.options.groundMaterial or Enum.Material.Ground)
	for i, colour in { RED, WHITE, BLUE } do
		local cf = CFrame.new(centre + Vector3.new(-12 + i * 6, 8, -radius - 4))
		part(model, "Pillar", Vector3.new(3, 16, 3), cf, Enum.Material.SmoothPlastic, colour)
	end
	sign(model, centre + Vector3.new(0, 4, radius + 6), Vector2.new(14, 3), "REFLECTIONS: stand low on the bank")
end

local function brazier(parent: Instance, base: Vector3)
	local metal = Color3.fromRGB(40, 36, 34)
	part(parent, "BrazierPost", Vector3.new(0.8, 3, 0.8), CFrame.new(base + Vector3.new(0, 1.5, 0)), Enum.Material.Metal, metal)
	local bowlCf = CFrame.new(base + Vector3.new(0, 3.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local bowl = part(parent, "BrazierBowl", Vector3.new(1, 3, 3), bowlCf, Enum.Material.Metal, metal)
	bowl.Shape = Enum.PartType.Cylinder
	local fire = own(Instance.new("Fire"))
	fire.Size, fire.Heat = 4, 8
	fire.Parent = bowl
	local light = own(Instance.new("PointLight"))
	light.Color, light.Brightness, light.Range, light.Shadows = Color3.fromRGB(255, 170, 90), 2, 18, true
	light.Parent = bowl
end

local function fireStation(ctx: Ctx)
	local model = station(ctx, "fire")
	local wallCf = CFrame.new(at(ctx, 80, -40, 6))
	part(model, "FireWall", Vector3.new(30, 12, 1), wallCf, Enum.Material.Plaster, Color3.fromRGB(226, 210, 186))
	brazier(model, at(ctx, 72, -34))
	brazier(model, at(ctx, 88, -34))
	placed(ctx, "fire", "campfire", CFrame.new(at(ctx, 80, -26)), model)
	sign(model, at(ctx, 80, -14, 3), Vector2.new(14, 3), "FIRE: shadows read best at night")
end

-- A primitive tree tagged for FoliageSway: trunk plus canopy, pivoting at its foot.
local function tree(ctx: Ctx, parent: Instance, base: Vector3, height: number, profile: string)
	local model = own(Instance.new("Model"))
	model.Name = "Tree_" .. profile
	local trunkCf = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local trunk = part(model, "Trunk", Vector3.new(height, 1.2, 1.2), trunkCf, Enum.Material.Wood, WOOD)
	trunk.Shape = Enum.PartType.Cylinder
	local canopyCf = CFrame.new(base + Vector3.new(0, height, 0))
	local canopy = part(model, "Canopy", Vector3.one * (height * 0.55), canopyCf, Enum.Material.LeafyGrass, Color3.fromRGB(70, 110, 55))
	canopy.Shape = Enum.PartType.Ball
	canopy.CanCollide = false
	model:SetAttribute("SwayProfile", profile)
	model.Parent = parent
	CollectionService:AddTag(model, swayTag(ctx))
end

local function banner(ctx: Ctx, parent: Instance)
	local model = own(Instance.new("Model"))
	model.Name = "Banner"
	part(model, "Pole", Vector3.new(0.6, 14, 0.6), CFrame.new(at(ctx, 200, 30, 7)), Enum.Material.Wood, WOOD)
	part(model, "Cloth", Vector3.new(0.2, 6, 4), CFrame.new(at(ctx, 200, 32.3, 10)), Enum.Material.Fabric, RED)
	model:SetAttribute("SwayProfile", "banner")
	model.Parent = parent
	CollectionService:AddTag(model, swayTag(ctx))
end

local function wind(ctx: Ctx)
	local model = station(ctx, "wind")
	local trees: { { profile: string, height: number } } = {
		{ profile = "tree", height = 18 }, { profile = "palm", height = 26 },
		{ profile = "tree", height = 14 }, { profile = "shrub", height = 4 },
	}
	for i, spec in trees do
		tree(ctx, model, at(ctx, 140 + (i - 1) * 16, 10 + (i % 2) * 12), spec.height, spec.profile)
	end
	banner(ctx, model)
	local items: { string } = ctx.options.windItems or {}
	for i, name in items do
		local cf = CFrame.new(at(ctx, 140 + i * 14, 55)) * CFrame.Angles(0, i, 0)
		local item = placed(ctx, "wind", name, cf, model)
		if item and not CollectionService:HasTag(item, swayTag(ctx)) then
			CollectionService:AddTag(item, swayTag(ctx))
		end
	end
	sign(model, at(ctx, 170, -6, 3), Vector2.new(16, 3), "WIND: sway, ribbons, dust")
end

local function primitiveProps(ctx: Ctx, model: Model)
	local wood, planks = Color3.fromRGB(150, 110, 70), Enum.Material.WoodPlanks
	part(model, "Crate", Vector3.new(4, 4, 4), CFrame.new(at(ctx, -160, 110, 2)), planks, wood)
	part(model, "Crate", Vector3.new(4, 4, 4), CFrame.new(at(ctx, -156, 111, 2)) * CFrame.Angles(0, 0.4, 0), planks, wood)
	part(model, "Crate", Vector3.new(3, 3, 3), CFrame.new(at(ctx, -158, 110.5, 5.5)) * CFrame.Angles(0, 0.8, 0), planks, wood)
	for i = 0, 2 do
		local cf = CFrame.new(at(ctx, -140 + i * 3.4, 110, 2)) * CFrame.Angles(0, 0, math.rad(90))
		local barrel = part(model, "Barrel", Vector3.new(4, 3, 3), cf, Enum.Material.Wood, wood)
		barrel.Shape = Enum.PartType.Cylinder
	end
	local rockCf = CFrame.new(at(ctx, -120, 110, 1.5)) * CFrame.Angles(0.2, 0.5, 0.1)
	local rock = part(model, "Rock", Vector3.new(7, 4, 5), rockCf, Enum.Material.Rock, Color3.fromRGB(120, 116, 110))
	rock.Shape = Enum.PartType.Ball
	part(model, "LowWall", Vector3.new(16, 3, 1.5), CFrame.new(at(ctx, -100, 110, 1.5)), Enum.Material.Brick, Color3.fromRGB(160, 90, 70))
end

local function props(ctx: Ctx)
	local model = station(ctx, "props")
	local names: { string } = ctx.options.props or {}
	for i, name in names do
		local cf = CFrame.new(at(ctx, -160 + (i - 1) * 20, 130)) * CFrame.Angles(0, i * 0.7, 0)
		placed(ctx, "props", name, cf, model)
	end
	primitiveProps(ctx, model)
	sign(model, at(ctx, -130, 95, 3), Vector2.new(16, 3), "PROPS: contact shadows")
end

-- Overlays a tiled texture on the side faces and top of each part in `model`.
local function overlay(model: Instance, id: string, studs: number, transparency: number)
	local faces = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Top }
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			for _, face in faces do
				local texture = own(Instance.new("Texture"))
				texture.Texture, texture.Face = id, face
				texture.StudsPerTileU, texture.StudsPerTileV = studs, studs
				texture.Transparency = transparency
				texture.Parent = d
			end
		end
	end
end

local function tiling(ctx: Ctx)
	if not ctx.options.place then
		table.insert(ctx.report.skipped, "tiling: needs `place` to supply a building")
		return
	end
	local model = station(ctx, "tiling")
	local labels = { "A: AS PLACED", "B: + FINE DETAIL TEXTURE", "C: + TILED TEXTURE BLEND" }
	local studs, alpha = { 0, 4, 10 }, { 0, 0.7, 0.55 }
	for i, label in labels do
		local x = -40 + (i - 1) * 40
		local building = placed(ctx, "tiling", "building", CFrame.new(at(ctx, x, 170)), model)
		local texture: string? = if i == 2 then ctx.options.detailTexture elseif i == 3 then ctx.options.tilingTexture else nil
		local text = label
		if not building then
			text ..= " (place returned nil)"
		elseif texture then
			overlay(building, texture, studs[i], alpha[i])
		elseif i > 1 then
			text ..= " (no texture given)"
		end
		sign(model, at(ctx, x, 150, 3), Vector2.new(18, 3), text)
	end
end

local BUILDERS: { [string]: (Ctx) -> () } = {
	materials = materials, terrain = terrainStrip, bounce = bounce, passage = passage, pond = pond,
	fire = fireStation, wind = wind, props = props, tiling = tiling,
}

-- Public ---------------------------------------------------------------------------------------

local function roots(parent: Instance): { Folder }
	local list: { Folder } = {}
	for _, child in parent:GetChildren() do
		if child:IsA("Folder") and child:GetAttribute(ROOT_ATTR) == true and child:GetAttribute(OWNED_ATTR) == true then
			table.insert(list, child)
		end
	end
	return list
end

-- The lab root under `parent` (default Workspace), found by ownership, or nil.
function LightingLab.find(parent: Instance?): Folder?
	return roots(parent or Workspace)[1]
end

-- Where to put a visitor: in front of the welcome sign, looking at it.
function LightingLab.spawnCFrame(origin: Vector3): CFrame
	return CFrame.lookAt(origin + Vector3.new(0, 4, 8), origin + Vector3.new(0, 4, -12))
end

local function restoreTerrain(root: Folder)
	local snap = root:FindFirstChildOfClass("TerrainRegion")
	local corner = root:GetAttribute(CORNER_ATTR)
	if not (snap and snap:GetAttribute(OWNED_ATTR) == true and typeof(corner) == "Vector3") then
		return
	end
	local ok, err = pcall(function()
		Workspace.Terrain:PasteRegion(snap, Vector3int16.new(corner.X, corner.Y, corner.Z), true)
	end)
	if not ok then
		warn(("LightingLab: terrain restore failed: %s"):format(tostring(err)))
	end
end

-- Removes every lab under `parent`: pastes the terrain snapshot back, destroys owned
-- children, and the root once it is empty. Returns true when a lab was found.
function LightingLab.clear(parent: Instance?): boolean
	local list = roots(parent or Workspace)
	for _, root in list do
		restoreTerrain(root)
		for _, child in root:GetChildren() do
			if child:GetAttribute(OWNED_ATTR) == true then
				child:Destroy()
			end
		end
		if #root:GetChildren() == 0 then
			root:Destroy()
		else -- a stranger's instance lives here: keep it, stop claiming the folder
			root:SetAttribute(ROOT_ATTR, nil)
			root:SetAttribute(OWNED_ATTR, nil)
		end
	end
	return #list > 0
end

local function buildStations(ctx: Ctx, names: { string })
	local report = ctx.report
	for _, name in names do
		local builder = BUILDERS[name]
		if not builder then
			table.insert(report.skipped, name .. ": unknown station")
		elseif name == "terrain" and not ctx.terrain then
			table.insert(report.skipped, "terrain: terrain snapshot failed")
		else
			local ok, err: any = pcall(builder, ctx)
			if ok then
				table.insert(report.built, name)
			else
				table.insert(report.skipped, ("%s: %s"):format(name, tostring(err)))
			end
		end
	end
end

-- Builds the lab (clearing an earlier one first) and returns its root and a report.
function LightingLab.build(opts: Options?): (Folder, Report)
	local options: Options = opts or {}
	local parent = options.parent or Workspace
	LightingLab.clear(parent)
	local origin = options.origin or Vector3.new(6000, 0, 0)
	local half = math.max(options.half or 240, 200)
	local root = own(Instance.new("Folder"))
	root.Name = "ForgeGUI_LightingLab"
	root:SetAttribute(ROOT_ATTR, true)
	root:SetAttribute("ForgeGUILabOrigin", origin)
	root.Parent = parent
	local report: Report = {
		origin = origin, spawn = LightingLab.spawnCFrame(origin), built = {}, skipped = {}, terrain = "snapshot", instances = 0,
	}
	local ctx: Ctx = { origin = origin, options = options, root = root, report = report, terrain = true }
	local ok, why = snapshot(ctx, half)
	if not ok then
		ctx.terrain = false
		report.terrain = ("part plate (terrain snapshot failed: %s)"):format(tostring(why))
	end
	plate(ctx, half)
	sign(root, at(ctx, 0, -12, 4), Vector2.new(22, 4), "LIGHTING & VFX LAB")
	buildStations(ctx, options.stations or STATIONS)
	report.instances = #root:GetDescendants()
	return root, report
end

return LightingLab
