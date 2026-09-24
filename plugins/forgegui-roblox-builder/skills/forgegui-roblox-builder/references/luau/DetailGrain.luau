--!strict
-- DetailGrain: fine tiled detail over generated buildings, so one stretched
-- texture stops reading as blocky up close.
--
-- A generated building wears one 1024 px texture over its whole mesh. Spread
-- over every face of a house, that leaves at most a few tens of pixels per stud,
-- which goes soft and blocky when a player stands beside it. Two tiled overlays of neutral grain (dark crevices,
-- light crests, no colour, no shapes) at about 3 studs per tile add detail at
-- every distance while the building keeps its own colours.
--
--   local layers = DetailGrain.grain("rbxassetid://<dark>", "rbxassetid://<light>")
--   DetailGrain.apply(workspace.World.Buildings, { layers = layers })
--   DetailGrain.clear(workspace.World.Buildings)
--
-- The grain pair comes from tools/make_grain.py (RGBA, pattern in alpha, tiles
-- exactly). Upload both as Image assets and pass the ids; nothing is hardcoded.
--
-- Compared side by side on the same generated house under the same lighting:
--   A bare (the one baked texture)                                   blocky up close
--   B fine grain: dark at Transparency 0.15, light at 0.3, 3 studs   chosen, shipped on every building
--   C tiled material blend: a mudbrick colour map at 10 studs, 0.55  washed out the baked detail
-- B beat A and C. C is kept as `DetailGrain.blend` because on plain, low-detail
-- meshes a tiled material can still be the better fix; judge it the same way,
-- A/B/C side by side in one capture.
--
-- Textures go on the five faces a player sees (not Bottom). A Texture projects
-- per face of the part's box, so on a MeshPart it lands on each face's direction;
-- on odd shapes check the capture for stretching on slanted faces.
--
-- Ownership: every Texture this module creates carries ForgeGUIDetailGrain = true;
-- `clear` destroys only those, never by name. `apply` clears its own textures
-- under the root first, so a second apply replaces rather than stacks.
-- Cost: 2 Textures x 5 faces = 10 instances per MeshPart. With grain on every
-- building, a dense town ran at about 11 ms median frame time on High with the
-- full effects stack (grain was not measured on its own).

local DetailGrain = {}

export type Layer = { texture: string, transparency: number, studs: number, color: Color3? }
export type Options = {
	layers: { Layer },
	-- Faces to cover. Default: every face but Bottom.
	faces: { Enum.NormalId }?,
	-- Classes that receive layers. Default { "MeshPart" }: primitive Parts tile
	-- their own material and rarely need it.
	classes: { string }?,
}

local OWNED_ATTR = "ForgeGUIDetailGrain"
local DEFAULT_FACES = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Top }
local DEFAULT_CLASSES = { "MeshPart" }

-- The shipped look: dark crevices at 0.15, light crests at 0.3, both at 3 studs.
function DetailGrain.grain(darkId: string, lightId: string, studs: number?): { Layer }
	local tile = studs or 3
	return {
		{ texture = darkId, transparency = 0.15, studs = tile },
		{ texture = lightId, transparency = 0.3, studs = tile },
	}
end

-- A tiled material blended over the baked texture (C in the comparison above).
function DetailGrain.blend(textureId: string, studs: number?, transparency: number?): { Layer }
	return { { texture = textureId, transparency = transparency or 0.55, studs = studs or 10 } }
end

local function validate(options: Options)
	assert(type(options) == "table" and type(options.layers) == "table" and #options.layers > 0, "DetailGrain.apply: options.layers must be a non-empty list")
	for i, layer in ipairs(options.layers) do
		assert(type(layer.texture) == "string" and layer.texture ~= "", ("DetailGrain: layer %d has no texture id"):format(i))
		assert(type(layer.studs) == "number" and layer.studs > 0, ("DetailGrain: layer %d studs must be > 0"):format(i))
		assert(type(layer.transparency) == "number" and layer.transparency >= 0 and layer.transparency <= 1, ("DetailGrain: layer %d transparency must be 0..1"):format(i))
	end
end

local function targets(root: Instance, classes: { string }): { BasePart }
	local list: { BasePart } = {}
	local function consider(item: Instance)
		if not item:IsA("BasePart") then
			return
		end
		for _, className in ipairs(classes) do
			if item:IsA(className) then
				table.insert(list, item)
				return
			end
		end
	end
	consider(root)
	for _, item in ipairs(root:GetDescendants()) do
		consider(item)
	end
	return list
end

local function dress(part: BasePart, layers: { Layer }, faces: { Enum.NormalId }): number
	-- Offsets seeded by position, so neighbouring parts never repeat in step.
	local p = part.Position
	local rng = Random.new(math.floor(p.X * 7 + p.Z * 13 + p.Y * 3))
	local made = 0
	for _, face in ipairs(faces) do
		for _, layer in ipairs(layers) do
			local texture = Instance.new("Texture")
			texture.Name = "DetailGrain"
			texture.Texture = layer.texture
			texture.Transparency = layer.transparency
			texture.Color3 = layer.color or Color3.new(1, 1, 1)
			texture.Face = face
			texture.StudsPerTileU = layer.studs
			texture.StudsPerTileV = layer.studs
			texture.OffsetStudsU = rng:NextNumber(0, layer.studs)
			texture.OffsetStudsV = rng:NextNumber(0, layer.studs)
			texture:SetAttribute(OWNED_ATTR, true)
			texture.Parent = part
			made += 1
		end
	end
	return made
end

-- Removes every Texture this module made under `root`. Returns the count.
function DetailGrain.clear(root: Instance): number
	local removed = 0
	for _, item in ipairs(root:GetDescendants()) do
		if item:IsA("Texture") and item:GetAttribute(OWNED_ATTR) == true then
			item:Destroy()
			removed += 1
		end
	end
	return removed
end

-- Lays the layers on every matching part under `root` (root included). Returns
-- the number of Textures created.
function DetailGrain.apply(root: Instance, options: Options): number
	validate(options)
	DetailGrain.clear(root)
	local faces = options.faces or DEFAULT_FACES
	local made = 0
	for _, part in ipairs(targets(root, options.classes or DEFAULT_CLASSES)) do
		made += dress(part, options.layers, faces)
	end
	return made
end

return DetailGrain
