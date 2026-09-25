--!strict
-- MaterialKit: gives a place its own surfaces from a table of MaterialVariants,
-- and hands the place back with `clear()`.
--
--   MaterialKit.apply({
--       { name = "Kit_Sand", base = Enum.Material.Sand, colorMap = "rbxassetid://1",
--         normalMap = "rbxassetid://2", roughnessMap = "rbxassetid://3", studsPerTile = 18,
--         terrainColor = Color3.fromRGB(250, 238, 222) },
--       { name = "Kit_Masonry", base = Enum.Material.Sandstone, colorMap = "rbxassetid://4",
--         studsPerTile = 12, override = false }, -- only parts that name it use it
--   })
--
-- What each field does, and the Roblox behaviour behind it:
--   * override (default true) calls MaterialService:SetBaseMaterialOverride, so
--     EVERY part and terrain voxel of `base` wears the variant, including terrain
--     written later. That is what makes nothing show Roblox's stock materials.
--     With override = false the variant is used only where a part sets
--     `MaterialVariant = name`: a second look on the same base material (dressed
--     masonry walls beside cliff-strata rock, both Sandstone).
--   * terrainColor calls Terrain:SetMaterialColor. Terrain colour MULTIPLIES the
--     colour map, so near-white (about 225-255 per channel) keeps the painted
--     colours and only warms or cools them; a mid colour muddies them. Part-only
--     materials (Plaster, Wood, Fabric...) have no terrain colour; it is skipped.
--   * colorMap should be the cavity bake from tools/pbr_maps.py (--cavity), and
--     normalMap / roughnessMap its normal and roughness maps. Terrain cannot
--     displace (measured: close-up ground reads flat whatever the normal map), so
--     the relief has to live in the colour bake and the normal map.
--   * studsPerTile: ground 12-18, rock faces 26-40, walls about 12, wood and
--     cloth about 6 (the values the source build shipped with).
--   * pattern = Enum.MaterialPattern.Organic lets Roblox vary the tiling on organic
--     ground; keep Regular (the default) for bricks and planks.
--
-- Ownership: every variant this module creates carries ForgeGUIMaterialKit = true,
-- and only those are ever reconfigured or destroyed. A variant of the same name it
-- did not create is left alone and reported as skipped. Borrowed settings are
-- recorded once, at the first change, so `clear()` restores them:
--   MaterialService: ForgeGUIMaterialKitPriorOverride_<Material> (the prior
--     override name, "" for none);
--   Terrain: ForgeGUIMaterialKitPriorColor_<Material> (the prior Color3).
-- These are NOT spelled ForgeGUIPrior_<Property>: they are method-backed settings,
-- not properties, and a generic restorer that assigns every ForgeGUIPrior_*
-- attribute back as a property would fail on them and then delete the record.
--
-- `apply` is idempotent (a second apply reconfigures its own variants) and
-- additive: to replace a kit, `clear()` then `apply()`. `clear()` returns false when
-- nothing was applied. Run it in Edit (from the command bar or execute_luau) or on
-- the server; MaterialService replicates.

local MaterialService = game:GetService("MaterialService")
local Workspace = game:GetService("Workspace")

local MaterialKit = {}

export type Spec = {
	name: string,
	base: Enum.Material,
	colorMap: string?,
	normalMap: string?,
	roughnessMap: string?,
	metalnessMap: string?,
	studsPerTile: number?,
	pattern: Enum.MaterialPattern?,
	override: boolean?,
	terrainColor: Color3?,
}
export type Report = { created: { string }, updated: { string }, skipped: { string }, failed: { string } }

local OWNED_ATTR = "ForgeGUIMaterialKit"
local OVERRIDE_PRIOR = "ForgeGUIMaterialKitPriorOverride_"
local COLOR_PRIOR = "ForgeGUIMaterialKitPriorColor_"
local DEFAULT_STUDS = 12

local function isOwned(instance: Instance): boolean
	return instance:GetAttribute(OWNED_ATTR) == true
end

local function validate(spec: Spec): string?
	if type(spec.name) ~= "string" or spec.name == "" then
		return "a spec has no name"
	end
	if typeof(spec.base) ~= "EnumItem" or (spec.base :: EnumItem).EnumType ~= Enum.Material then
		return spec.name .. ": base must be an Enum.Material"
	end
	if spec.studsPerTile ~= nil and (type(spec.studsPerTile) ~= "number" or spec.studsPerTile <= 0) then
		return spec.name .. ": studsPerTile must be a positive number"
	end
	return nil
end

-- The owned variant of this name, a new one, or nil when a stranger holds the name.
local function variantFor(name: string): (MaterialVariant?, boolean)
	for _, child in ipairs(MaterialService:GetChildren()) do
		if child.Name == name and child:IsA("MaterialVariant") then
			return if isOwned(child) then child else nil, false
		end
	end
	local made = Instance.new("MaterialVariant")
	made.Name = name
	made:SetAttribute(OWNED_ATTR, true)
	return made, true
end

local function configure(variant: MaterialVariant, spec: Spec)
	variant.BaseMaterial = spec.base
	variant.ColorMap = spec.colorMap or ""
	variant.NormalMap = spec.normalMap or ""
	variant.RoughnessMap = spec.roughnessMap or ""
	variant.MetalnessMap = spec.metalnessMap or ""
	variant.StudsPerTile = spec.studsPerTile or DEFAULT_STUDS
	variant.MaterialPattern = spec.pattern or Enum.MaterialPattern.Regular
	variant.Parent = MaterialService
end

local function setOverride(spec: Spec)
	local key = OVERRIDE_PRIOR .. spec.base.Name
	if MaterialService:GetAttribute(key) == nil then
		MaterialService:SetAttribute(key, MaterialService:GetBaseMaterialOverride(spec.base))
	end
	MaterialService:SetBaseMaterialOverride(spec.base, spec.name)
end

local function setTerrainColor(spec: Spec, color: Color3): boolean
	local terrain = Workspace.Terrain
	local key = COLOR_PRIOR .. spec.base.Name
	local ok, prior = pcall(function()
		return terrain:GetMaterialColor(spec.base)
	end)
	if not ok then
		return false -- not a terrain material
	end
	local written = pcall(function()
		terrain:SetMaterialColor(spec.base, color)
	end)
	if written and terrain:GetAttribute(key) == nil then
		terrain:SetAttribute(key, prior)
	end
	return written
end

local function applyOne(spec: Spec, report: Report)
	local problem = validate(spec)
	if problem then
		table.insert(report.failed, problem)
		return
	end
	local variant, created = variantFor(spec.name)
	if not variant then
		table.insert(report.skipped, spec.name .. ": the name belongs to a variant this module did not create")
		return
	end
	local ok, err = pcall(function()
		configure(variant, spec)
	end)
	if not ok then
		if created then
			variant:Destroy()
		end
		table.insert(report.failed, ("%s: %s"):format(spec.name, tostring(err)))
		return
	end
	if spec.override ~= false then
		setOverride(spec)
	end
	if spec.terrainColor and not setTerrainColor(spec, spec.terrainColor) then
		table.insert(report.skipped, spec.name .. ": " .. spec.base.Name .. " is not a terrain material, terrainColor ignored")
	end
	table.insert(if created then report.created else report.updated, spec.name)
end

function MaterialKit.apply(specs: { Spec }): Report
	local report: Report = { created = {}, updated = {}, skipped = {}, failed = {} }
	-- Marked before the first change, so clear() can still undo the specs applied
	-- before one that raises (a spec that is not a table, say).
	MaterialService:SetAttribute(OWNED_ATTR, true)
	for _, spec in ipairs(specs) do
		applyOne(spec, report)
	end
	return report
end

local function restorePriors(instance: Instance, prefix: string, restore: (material: Enum.Material, value: any) -> ())
	for key, value in instance:GetAttributes() do
		if string.sub(key, 1, #prefix) == prefix then
			local material = (Enum.Material :: any)[string.sub(key, #prefix + 1)]
			if material then
				pcall(restore, material, value)
			end
			instance:SetAttribute(key, nil)
		end
	end
end

-- Destroys only the variants this module created and puts back every override and
-- terrain colour it changed. Returns false when nothing was applied.
function MaterialKit.clear(): boolean
	if MaterialService:GetAttribute(OWNED_ATTR) == nil then
		return false
	end
	restorePriors(MaterialService, OVERRIDE_PRIOR, function(material, value)
		MaterialService:SetBaseMaterialOverride(material, if type(value) == "string" then value else "")
	end)
	restorePriors(Workspace.Terrain, COLOR_PRIOR, function(material, value)
		Workspace.Terrain:SetMaterialColor(material, value)
	end)
	for _, child in ipairs(MaterialService:GetChildren()) do
		if child:IsA("MaterialVariant") and isOwned(child) then
			child:Destroy()
		end
	end
	MaterialService:SetAttribute(OWNED_ATTR, nil)
	return true
end

-- The variants this module owns, by name.
function MaterialKit.owned(): { [string]: MaterialVariant }
	local list = {}
	for _, child in ipairs(MaterialService:GetChildren()) do
		if child:IsA("MaterialVariant") and isOwned(child) then
			list[child.Name] = child
		end
	end
	return list
end

return MaterialKit
