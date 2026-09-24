--!strict
-- KeepOut: a placement guard so scattered clutter never stands inside a building,
-- a wall or across a walkway.
--
-- A scatter pass that places crates, jars, rocks and trees by noise or by a list
-- of points will put some of them inside a house or in the middle of a gate
-- passage. Nobody sees it in an overview capture; a player walks into it. The fix
-- is a rule at placement time, not a clean-up afterwards: register the footprint
-- of everything that must stay clear, and have every placer ask `blocked` before
-- it parents a prop.
--
--   local zone = KeepOut.new()
--   for _, building in ipairs(workspace.World.Buildings:GetChildren()) do
--       zone.registerModel(building)
--   end
--   zone.registerPassage(gatehouse, "X", 14, 5) -- the walkway through a gate, 14 studs out each side
--   if not zone.blockedModel(crate) then crate.Parent = workspace.World.Props end
--
-- Rules, and why:
--   * A prop's box is shrunk to `shrink` (default 0.7) before the test. Props may
--     touch a wall or lean on it; only passing into it counts. 0.7 is the value the
--     source build shipped with; it was set by eye, not calibrated.
--   * Trees are tested by their trunk, not their crown: X and Z shrink to the trunk
--     share (about 0.12 of the width for a palm or acacia, 0.15 for a bare tree), so
--     a crown may overhang a roof while the trunk may not stand in the house. Give
--     a share per name in `trunkShare`, or a KeepOutTrunk attribute on the model.
--   * Boxes are oriented (separating-axis test on all 15 axes), so rotated walls
--     and gates are exact, not their axis-aligned bounds.
--   * The list is linear: fine for a few hundred footprints and a few thousand
--     queries in an Edit-time build. Rebuild with `reset` + `collect` when one
--     section of a world is rebuilt on its own, so it still sees the buildings the
--     other sections made.
--
-- It creates no instances and changes nothing in the place, so there is nothing
-- to own or restore. WorldCheck's `clutter` check reports the same rule after the
-- fact (same 0.7 shrink, same KeepOutTrunk attribute).

local KeepOut = {}

export type Box = { cframe: CFrame, half: Vector3 }
export type Options = {
	-- Fraction of a prop's box that must stay clear. Default 0.7.
	shrink: number?,
	-- Trunk share (0..1 of X and Z) by model name, for trees.
	trunkShare: { [string]: number }?,
}
export type Zone = {
	register: (cframe: CFrame, size: Vector3) -> (),
	registerModel: (model: Model) -> (),
	registerPassage: (model: Model, axis: string, approach: number, halfWidth: number) -> (),
	collect: (root: Instance, include: (model: Model) -> boolean) -> number,
	blocked: (cframe: CFrame, size: Vector3, trunk: number?) -> boolean,
	blockedModel: (model: Model) -> boolean,
	reset: () -> (),
	count: () -> number,
}

local DEFAULT_SHRINK = 0.7
local EPSILON = 1e-6

local function radius(box: Box, axis: Vector3): number
	local cf, half = box.cframe, box.half
	return math.abs(cf.XVector:Dot(axis)) * half.X + math.abs(cf.YVector:Dot(axis)) * half.Y + math.abs(cf.ZVector:Dot(axis)) * half.Z
end

-- Oriented boxes overlap unless some axis separates them: the six face normals,
-- then the nine edge cross products (needed only when both boxes are tilted).
function KeepOut.boxesOverlap(a: Box, b: Box): boolean
	local d = b.cframe.Position - a.cframe.Position
	local faceA = { a.cframe.XVector, a.cframe.YVector, a.cframe.ZVector }
	local faceB = { b.cframe.XVector, b.cframe.YVector, b.cframe.ZVector }
	local axes = { faceA[1], faceA[2], faceA[3], faceB[1], faceB[2], faceB[3] }
	for _, u in ipairs(faceA) do
		for _, v in ipairs(faceB) do
			local cross = u:Cross(v)
			if cross.Magnitude > EPSILON then
				table.insert(axes, cross.Unit)
			end
		end
	end
	for _, axis in ipairs(axes) do
		if math.abs(d:Dot(axis)) > radius(a, axis) + radius(b, axis) then
			return false
		end
	end
	return true
end

-- The half-size of a prop's probe box: shrunk, and narrowed to the trunk for trees.
local function probeHalf(size: Vector3, shrink: number, trunk: number?): Vector3
	local across = trunk or shrink
	return Vector3.new(size.X / 2 * across, size.Y / 2 * shrink, size.Z / 2 * across)
end

function KeepOut.new(options: Options?): Zone
	local settings: Options = options or {}
	local shrink = settings.shrink or DEFAULT_SHRINK
	local trunkShare = settings.trunkShare or {}
	local boxes: { Box } = {}

	local function register(cframe: CFrame, size: Vector3)
		table.insert(boxes, { cframe = cframe, half = size / 2 })
	end

	local function registerModel(model: Model)
		local cframe, size = model:GetBoundingBox()
		register(cframe, size)
	end

	-- A walkway through a gate or arch: the model's box run out `approach` studs
	-- each side along its local `axis` ("X" or "Z"), `halfWidth` studs either side
	-- of its centre line.
	local function registerPassage(model: Model, axis: string, approach: number, halfWidth: number)
		assert(axis == "X" or axis == "Z", "KeepOut.registerPassage: axis must be \"X\" or \"Z\"")
		local cframe, size = model:GetBoundingBox()
		local half = if axis == "X"
			then Vector3.new(size.X / 2 + approach, size.Y / 2, halfWidth)
			else Vector3.new(halfWidth, size.Y / 2, size.Z / 2 + approach)
		table.insert(boxes, { cframe = cframe, half = half })
	end

	-- Registers every model under `root` that `include` accepts; returns how many.
	local function collect(root: Instance, include: (model: Model) -> boolean): number
		local added = 0
		for _, item in ipairs(root:GetDescendants()) do
			if item:IsA("Model") and include(item) then
				registerModel(item)
				added += 1
			end
		end
		return added
	end

	local function blocked(cframe: CFrame, size: Vector3, trunk: number?): boolean
		local probe: Box = { cframe = cframe, half = probeHalf(size, shrink, trunk) }
		for _, other in ipairs(boxes) do
			if KeepOut.boxesOverlap(probe, other) then
				return true
			end
		end
		return false
	end

	-- Tests a model where it stands now: pivot it into place first.
	local function blockedModel(model: Model): boolean
		local cframe, size = model:GetBoundingBox()
		local attribute = model:GetAttribute("KeepOutTrunk")
		local trunk = if type(attribute) == "number" then attribute else trunkShare[model.Name]
		return blocked(cframe, size, trunk)
	end

	return {
		register = register,
		registerModel = registerModel,
		registerPassage = registerPassage,
		collect = collect,
		blocked = blocked,
		blockedModel = blockedModel,
		reset = function()
			table.clear(boxes)
		end,
		count = function(): number
			return #boxes
		end,
	}
end

return KeepOut
