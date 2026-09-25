--!strict
-- GroundScatter: real 3D ground patches laid near the camera on chosen terrain
-- materials, so close-up ground stops reading as flat paint.
--
-- Measured: Roblox terrain cannot displace a texture. However good the normal
-- map, cracked earth, paving or gravel reads as a flat print once the camera is
-- a few studs off the ground. What fixed it was the modern-engine answer: small
-- generated 3D patches (a ~12-stud slab of cracked mud plates, a gravel scatter,
-- a flagstone cluster) laid on the matching terrain around the camera, sunk so
-- only their top few tenths of a stud stand proud.
--
--   GroundScatter.start({
--       kinds = { [Enum.Material.Ground] = { template = assets.MudPlates, tint = Color3.fromRGB(214, 196, 178) } },
--   })
--
-- Run it from a LocalScript: it is visual only (no collision, no queries, no
-- touch) and each client lays its own patches.
--
-- How it decides, and why:
--   * The world is cut into `cell`-stud cells snapped to world coordinates, and
--     each cell's jitter and yaw come from a hash of its coordinates, so a patch
--     never swims as the camera moves and returns to the same spot. `cell` sits a
--     little under the patch width so neighbours overlap and hide their edges.
--   * One ray down per cell finds the ground; steep ground (normal.Y < minUp:
--     cliffs, bank faces), water and other materials get nothing.
--   * FOOTPRINT rule: a patch is laid only where its whole footprint (centre and
--     the four corners of its own box, as it will stand: its X and Z extents,
--     turned by the cell's yaw, pulled in to 0.92 of each half-side) is the same
--     material. Without it, roads about 14 studs wide under 12-stud patches
--     mostly got patches that straddled the road edge and read as loose tiles
--     strewn over the next material. Narrow strips therefore get none, which is
--     the right answer. The corners are probed where the patch will actually
--     lie: a world-aligned square from the shorter side let a 12 x 6 patch lie
--     across an 8-stud road, and let a turned square reach past its test.
--   * The patch follows the slope and is sunk so only its top `protrude` studs
--     stand proud, so it reads as part of the ground rather than an object on it.
--   * Generated colour maps come out warmer and brighter than graded terrain;
--     `tint` sets SurfaceAppearance.Color (or the part colour) to pull a patch
--     onto the ground's tone. Match it in a capture, not by numbers.
--   * Cells are checked `cellsPerFrame` at a time, nearest first (five rays each),
--     patches come from a pool, and cells beyond `leaveRadius` are returned.
--
-- Cost, measured on High with the full effects stack: about 60 patches in view
-- in an open area at a 6 ms median frame. The rays are the per-frame cost
-- (12 cells x 5 rays at the default); the patches cost what their meshes cost.
--
-- Ownership: the folder it lays patches in and every patch carry
-- ForgeGUIGroundScatter = true. `stop()` destroys only those (the templates are
-- the caller's and are never touched); `start()` also removes owned folders a
-- previous run left behind, so starting twice lays one set. `manual = true`
-- skips the Heartbeat connection: call `step(focus)` yourself (tests, Edit).

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GroundScatter = {}

export type Kind = { template: Model, tint: Color3? }
export type Config = {
	kinds: { [Enum.Material]: Kind },
	cell: number?,
	radius: number?,
	leaveRadius: number?,
	protrude: number?,
	minUp: number?,
	footprint: number?,
	cellsPerFrame: number?,
	jitter: number?,
	castTop: number?,
	castDepth: number?,
	parent: Instance?,
	focus: (() -> Vector3?)?,
	manual: boolean?,
}
export type Stats = { patches: number, empty: number, pooled: number, queued: number }

type Prepared = { template: Model, tint: Color3?, lift: number, box: CFrame, reach: Vector2 }
type Patch = { model: Model, material: Enum.Material }
type State = {
	cell: number,
	radius: number,
	leaveRadius: number,
	minUp: number,
	cellsPerFrame: number,
	jitter: number,
	castTop: number,
	castDepth: number,
	focus: () -> Vector3?,
	kinds: { [Enum.Material]: Prepared },
	folder: Folder,
	placed: { [Vector3]: Patch | false },
	pools: { [Enum.Material]: { Model } },
	queue: { Vector3 },
	lastCell: Vector3?,
	ray: RaycastParams,
	connection: RBXScriptConnection?,
}

local OWNED_ATTR = "ForgeGUIGroundScatter"
local CORNERS = { Vector2.new(1, 1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(-1, -1) }
-- Cells are keyed by Vector3 (X, 0, Z): a native vector is compared by value as a
-- table key. A Vector2 is userdata and is keyed by identity, so a cell looked up
-- with a new Vector2 is never found and would be laid again after every re-plan.

local state: State? = nil

local function hash(x: number, z: number, salt: number): number
	local n = math.sin(x * 12.9898 + z * 78.233 + salt * 37.719) * 43758.5453
	return n - math.floor(n)
end

local function cameraFocus(): Vector3?
	local camera = Workspace.CurrentCamera
	return if camera then camera.Focus.Position else nil
end

-- Offsets that put the template's box top `protrude` studs above the ground point
-- under its pivot, the box's frame in pivot space, and the half-extents of its
-- footprint test: 0.46 of each of the box's own X and Z sides (a `footprint`
-- number sets both), so the corners probed are the patch's real corners pulled
-- in a little, wherever and however the patch is turned.
local function prepare(material: Enum.Material, kind: Kind, protrude: number, footprint: number?): Prepared
	assert(type(kind) == "table" and typeof(kind.template) == "Instance" and kind.template:IsA("Model"), "GroundScatter: kinds[" .. material.Name .. "].template must be a Model")
	local box, size = kind.template:GetBoundingBox()
	local rel = kind.template:GetPivot():ToObjectSpace(box)
	return {
		template = kind.template,
		tint = kind.tint,
		lift = protrude - rel.Y - size.Y / 2,
		box = rel,
		reach = if footprint then Vector2.new(footprint, footprint) else Vector2.new(size.X * 0.46, size.Z * 0.46),
	}
end

local function clone(s: State, material: Enum.Material): Model
	local pool = s.pools[material]
	local reused = pool and table.remove(pool)
	if reused then
		return reused
	end
	local kind = s.kinds[material]
	local model = kind.template:Clone()
	model:SetAttribute(OWNED_ATTR, true)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
			local look = part:FindFirstChildOfClass("SurfaceAppearance")
			if kind.tint and look then
				look.Color = kind.tint
			elseif kind.tint then
				part.Color = kind.tint
			end
		end
	end
	return model
end

local function release(s: State, patch: Patch)
	patch.model.Parent = nil
	s.pools[patch.material] = s.pools[patch.material] or {}
	table.insert(s.pools[patch.material], patch.model)
end

local function groundAt(s: State, x: number, z: number): RaycastResult?
	return Workspace:Raycast(Vector3.new(x, s.castTop, z), Vector3.new(0, -s.castDepth, 0), s.ray)
end

-- Whether the ground under all four corners of `box` (the patch's bounding box
-- where it will stand, so the probe follows its size, yaw and slope) is `material`.
local function covered(s: State, box: CFrame, material: Enum.Material, reach: Vector2): boolean
	for _, corner in ipairs(CORNERS) do
		local point = box:PointToWorldSpace(Vector3.new(corner.X * reach.X, 0, corner.Y * reach.Y))
		local hit = groundAt(s, point.X, point.Z)
		if not hit or hit.Material ~= material then
			return false
		end
	end
	return true
end

-- The patch for one cell, or false when the cell gets none.
local function lay(s: State, cell: Vector3): Patch | false
	local jx = (hash(cell.X, cell.Z, 1) - 0.5) * s.cell * s.jitter
	local jz = (hash(cell.X, cell.Z, 2) - 0.5) * s.cell * s.jitter
	local x, z = (cell.X + 0.5) * s.cell + jx, (cell.Z + 0.5) * s.cell + jz
	local hit = groundAt(s, x, z)
	if not hit or hit.Normal.Y < s.minUp then
		return false
	end
	local kind = s.kinds[hit.Material]
	if not kind then
		return false
	end
	local up = hit.Normal
	local yaw = math.floor(hash(cell.X, cell.Z, 3) * 4) * math.pi / 2 + (hash(cell.X, cell.Z, 4) - 0.5) * 0.5
	local level = CFrame.fromMatrix(hit.Position, up:Cross(Vector3.zAxis).Unit, up) * CFrame.Angles(0, yaw, 0)
	local pivot = level * CFrame.new(0, kind.lift, 0)
	if not covered(s, pivot * kind.box, hit.Material, kind.reach) then
		return false
	end
	local model = clone(s, hit.Material)
	model:PivotTo(pivot)
	model.Parent = s.folder
	return { model = model, material = hit.Material }
end

local function cellOf(s: State, position: Vector3): Vector3
	return Vector3.new(math.floor(position.X / s.cell), 0, math.floor(position.Z / s.cell))
end

local function cellDistance(s: State, cell: Vector3, focus: Vector3): number
	return Vector2.new((cell.X + 0.5) * s.cell - focus.X, (cell.Z + 0.5) * s.cell - focus.Z).Magnitude
end

-- Queues the empty cells in reach (nearest popped first) and returns far ones to the pool.
local function plan(s: State, focus: Vector3)
	table.clear(s.queue)
	local centre = cellOf(s, focus)
	local reach = math.ceil(s.radius / s.cell)
	for dx = -reach, reach do
		for dz = -reach, reach do
			local cell = Vector3.new(centre.X + dx, 0, centre.Z + dz)
			if s.placed[cell] == nil and cellDistance(s, cell, focus) <= s.radius then
				table.insert(s.queue, cell)
			end
		end
	end
	table.sort(s.queue, function(a, b)
		return cellDistance(s, a, focus) > cellDistance(s, b, focus)
	end)
	for cell, patch in pairs(s.placed) do
		if cellDistance(s, cell, focus) > s.leaveRadius then
			if patch then
				release(s, patch :: Patch)
			end
			s.placed[cell] = nil
		end
	end
end

-- One frame of work around `focus` (default: the configured focus, the camera's).
function GroundScatter.step(focus: Vector3?)
	local s = state
	if not s then
		return
	end
	local at = focus or s.focus()
	if not at then
		return
	end
	local cell = cellOf(s, at)
	if cell ~= s.lastCell then
		s.lastCell = cell
		plan(s, at)
	end
	for _ = 1, math.min(s.cellsPerFrame, #s.queue) do
		local nextCell = table.remove(s.queue) :: Vector3
		if s.placed[nextCell] == nil then
			s.placed[nextCell] = lay(s, nextCell)
		end
	end
end

local function removeOwned(parent: Instance)
	for _, child in ipairs(parent:GetChildren()) do
		if child:GetAttribute(OWNED_ATTR) == true then
			child:Destroy()
		end
	end
end

local function build(config: Config): State
	assert(type(config) == "table" and type(config.kinds) == "table" and next(config.kinds) ~= nil, "GroundScatter.start: config.kinds must map at least one Enum.Material to a template")
	local protrude = config.protrude or 0.45
	local kinds: { [Enum.Material]: Prepared } = {}
	for material, kind in pairs(config.kinds) do
		kinds[material] = prepare(material, kind, protrude, config.footprint)
	end
	local radius = config.radius or 64
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Include
	ray.FilterDescendantsInstances = { Workspace.Terrain }
	ray.IgnoreWater = false -- a water surface stops the ray, so nothing is laid under water
	local folder = Instance.new("Folder")
	folder.Name = "ForgeGUIGroundScatter"
	folder:SetAttribute(OWNED_ATTR, true)
	return {
		cell = config.cell or 10.5,
		radius = radius,
		leaveRadius = config.leaveRadius or radius + 8,
		minUp = config.minUp or 0.86,
		cellsPerFrame = config.cellsPerFrame or 12,
		jitter = config.jitter or 0.3,
		castTop = config.castTop or 400,
		castDepth = config.castDepth or 800,
		focus = config.focus or cameraFocus,
		kinds = kinds,
		folder = folder,
		placed = {},
		pools = {},
		queue = {},
		lastCell = nil,
		ray = ray,
		connection = nil,
	}
end

-- Starts laying patches. Starting while running restarts with the new config.
function GroundScatter.start(config: Config)
	GroundScatter.stop()
	local parent = config.parent or Workspace
	removeOwned(parent)
	local s = build(config)
	s.folder.Parent = parent
	state = s
	if not config.manual then
		s.connection = RunService.Heartbeat:Connect(function()
			GroundScatter.step(nil)
		end)
	end
end

-- Stops, and destroys every patch and pooled clone it made. Returns false when not running.
function GroundScatter.stop(): boolean
	local s = state
	if not s then
		return false
	end
	state = nil
	if s.connection then
		s.connection:Disconnect()
	end
	for _, pool in pairs(s.pools) do
		for _, model in ipairs(pool) do
			model:Destroy()
		end
	end
	s.folder:Destroy()
	return true
end

function GroundScatter.stats(): Stats
	local s = state
	local result: Stats = { patches = 0, empty = 0, pooled = 0, queued = 0 }
	if not s then
		return result
	end
	for _, patch in pairs(s.placed) do
		if patch then
			result.patches += 1
		else
			result.empty += 1
		end
	end
	for _, pool in pairs(s.pools) do
		result.pooled += #pool
	end
	result.queued = #s.queue
	return result
end

return GroundScatter
