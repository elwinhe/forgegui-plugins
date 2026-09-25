--!strict
-- FoliageSway: trees, palms, shrubs and banners lean and sway with the wind.
-- Client only. Tag what should move, then start it from a LocalScript:
--
--   -- in Studio or at build time (tags replicate):
--   CollectionService:AddTag(treeModel, "ForgeGUISway")
--   treeModel:SetAttribute("SwayProfile", "palm")   -- optional; default "tree"
--
--   local FoliageSway = require(ReplicatedStorage.FoliageSway)
--   FoliageSway.start({ wind = Wind, onLeafSource = WindVfx.setLeafSource })
--
-- A tagged Model (or a single tagged BasePart) is rotated about its base,
-- client-side only: a steady lean downwind that grows with strength, a sway whose
-- speed and size follow the gusts, and a small cross-wind wobble. Each plant's
-- phase comes from its position, so a stand never moves in lockstep, and big
-- specimens move less than small ones (gain = 1/sqrt(height / profile height)).
--
-- Attributes on the tagged instance (all optional):
--   SwayProfile  string   palm | tree | conifer | dead | shrub | banner  (default tree)
--   SwayScale    number   multiplies lean and sway (0 freezes it)
--   SwayBase     Vector3  world-space pivot; default: bottom centre of the bounding box
--   SwayLeaves   boolean  report this plant's crown as a leaf source (default: palms)
--
-- Why it is built this way:
-- - Only anchored parts are moved, and only on this client, so physics and the
--   server copy are untouched; a plant that streams back in starts from the
--   server's CFrame, which is its rest pose.
-- - At most `maxActive` plants (nearest first) within `range` studs move,
--   re-chosen twice a second, all in ONE Workspace:BulkMoveTo per frame. Writing
--   CFrame part by part costs a property-changed event per part per frame.
--   Plants farther than `near` move every other frame; plants wholly behind the
--   camera are skipped. With nothing in range the frame loop does no work.
-- - Set ModelStreamingMode = Atomic on tagged models so a tree arrives whole.
--
-- Ownership: it creates no instances. It borrows each moving part's CFrame:
-- when a plant starts moving, every part gets ForgeGUIPrior_CFrame (its rest
-- pose) and ForgeGUIFoliageSway = true; when it stops moving the rest pose is
-- written back and both attributes removed. stop() restores everything, and
-- restoreAll() repairs parts left moved by a crashed or reloaded copy.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

export type WindSource = { sample: () -> (Vector3, number, number) }
export type Profile = { lean: number, sway: number, speed: number, height: number, leaves: boolean }
export type Options = {
	wind: WindSource?, -- default: read Workspace.GlobalWind
	tag: string?, -- default "ForgeGUISway"
	range: number?, -- studs, default 220
	maxActive: number?, -- default 60
	near: number?, -- studs; farther plants update every other frame, default 110
	leafRange: number?, -- studs for onLeafSource, default 80
	onLeafSource: ((position: Vector3?) -> ())?,
}
type Plant = {
	root: Instance, parts: { BasePart }, rests: { CFrame }, base: Vector3, height: number,
	profile: Profile, gain: number, phase: number, active: boolean, far: boolean,
}
type Candidate = { plant: Plant, distance: number }

local OWNED_ATTR = "ForgeGUIFoliageSway"
local PRIOR_ATTR = "ForgeGUIPrior_CFrame"
local TAU = math.pi * 2
local PICK_STEP = 0.5

-- Degrees of lean per unit strength, sway amplitude (degrees), sway speed (Hz)
-- and the nominal height (studs) the numbers were tuned for.
local PROFILES: { [string]: Profile } = {
	palm = { lean = 2.2, sway = 1.6, speed = 0.33, height = 30, leaves = true },
	tree = { lean = 1.0, sway = 0.8, speed = 0.45, height = 20, leaves = false },
	conifer = { lean = 0.6, sway = 0.5, speed = 0.4, height = 28, leaves = false },
	dead = { lean = 0.35, sway = 0.3, speed = 0.6, height = 16, leaves = false },
	shrub = { lean = 3.0, sway = 2.6, speed = 0.9, height = 4, leaves = false },
	banner = { lean = 1.2, sway = 1.8, speed = 0.7, height = 16, leaves = false },
}

local FoliageSway = {}
FoliageSway.PROFILES = PROFILES

local options: Options = {}
local plants: { [Instance]: Plant } = {}
local activeList: { Plant } = {}
local connections: { RBXScriptConnection } = {}
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}
local clock, frame, sincePick = 0, 0, PICK_STEP
local running = false

local function windNow(): (Vector3, number, number)
	local source = options.wind
	if source then
		return source.sample()
	end
	local v = Workspace.GlobalWind
	local flat = Vector3.new(v.X, 0, v.Z)
	local dir = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(-1, 0, 0)
	return dir, math.max(0, (v.Magnitude - 3) / 22), 0
end

-- Registration ---------------------------------------------------------------------------

local function collectParts(root: Instance): { BasePart }
	local parts: { BasePart } = {}
	if root:IsA("BasePart") and root.Anchored then
		table.insert(parts, root)
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Anchored then
			table.insert(parts, d)
		end
	end
	return parts
end

-- Bottom centre of the plant (or its SwayBase) and its height.
local function footprint(root: Instance, parts: { BasePart }): (Vector3, number)
	local cf, size = parts[1].CFrame, parts[1].Size
	if root:IsA("Model") then
		cf, size = root:GetBoundingBox()
	end
	local base = root:GetAttribute("SwayBase")
	local bottom = Vector3.new(cf.X, cf.Y - size.Y / 2, cf.Z)
	return if typeof(base) == "Vector3" then base else bottom, math.max(size.Y, 1)
end

local function profileOf(root: Instance): Profile
	local name = root:GetAttribute("SwayProfile")
	local base = PROFILES[if type(name) == "string" then name else "tree"] or PROFILES.tree
	local scale = root:GetAttribute("SwayScale")
	local leaves = root:GetAttribute("SwayLeaves")
	if type(scale) ~= "number" and type(leaves) ~= "boolean" then
		return base
	end
	local s = if type(scale) == "number" then math.max(scale, 0) else 1
	return {
		lean = base.lean * s, sway = base.sway * s, speed = base.speed, height = base.height,
		leaves = if type(leaves) == "boolean" then leaves else base.leaves,
	}
end

local function register(root: Instance)
	if plants[root] then
		return
	end
	local parts = collectParts(root)
	if #parts == 0 then
		return
	end
	local base, height = footprint(root, parts)
	local profile = profileOf(root)
	plants[root] = {
		root = root, parts = parts, rests = {}, base = base, height = height, profile = profile,
		gain = 1 / math.sqrt(math.max(height / profile.height, 0.5)),
		phase = (base.X * 0.137 + base.Z * 0.071) % TAU, active = false, far = false,
	}
end

-- Borrow / hand back -------------------------------------------------------------------------

local function borrow(plant: Plant)
	for i, part in plant.parts do
		local prior = part:GetAttribute(PRIOR_ATTR)
		local rest = if typeof(prior) == "CFrame" then prior else part.CFrame
		plant.rests[i] = rest
		part:SetAttribute(PRIOR_ATTR, rest)
		part:SetAttribute(OWNED_ATTR, true)
	end
	plant.active = true
end

local function handBack(plant: Plant)
	for i, part in plant.parts do
		local rest = plant.rests[i]
		if part.Parent and rest then
			part.CFrame = rest
		end
		part:SetAttribute(PRIOR_ATTR, nil)
		part:SetAttribute(OWNED_ATTR, nil)
	end
	plant.active = false
end

local function unregister(root: Instance, restore: boolean)
	local plant = plants[root]
	if not plant then
		return
	end
	plants[root] = nil
	if plant.active and restore then
		handBack(plant)
	end
	plant.active = false
	local index = table.find(activeList, plant)
	if index then
		table.remove(activeList, index)
	end
end

-- Choosing the active set ------------------------------------------------------------------

local function reportLeaves(candidates: { Candidate })
	local report = options.onLeafSource
	if not report then
		return
	end
	local leafRange = options.leafRange or 80
	for _, candidate in candidates do
		if candidate.distance > leafRange then
			break
		end
		local plant = candidate.plant
		if plant.profile.leaves then
			report(plant.base + Vector3.new(0, plant.height * 0.85, 0))
			return
		end
	end
	report(nil)
end

-- The nearest maxActive plants in range; the ones that drop out are handed back.
local function pick(eye: Vector3)
	local range, near = options.range or 220, options.near or 110
	local candidates: { Candidate } = {}
	for _, plant in plants do
		local distance = (plant.base - eye).Magnitude
		if distance <= range then
			table.insert(candidates, { plant = plant, distance = distance })
		end
	end
	table.sort(candidates, function(a: Candidate, b: Candidate): boolean
		return a.distance < b.distance
	end)
	reportLeaves(candidates)
	local chosen: { Plant } = {}
	local chosenSet: { [Plant]: boolean } = {}
	for i = 1, math.min(#candidates, options.maxActive or 60) do
		local plant = candidates[i].plant
		if not plant.active then
			borrow(plant)
		end
		plant.far = candidates[i].distance > near
		chosen[i] = plant
		chosenSet[plant] = true
	end
	for _, plant in activeList do
		if not chosenSet[plant] and plant.active then
			handBack(plant)
		end
	end
	activeList = chosen
end

-- Motion -------------------------------------------------------------------------------------

-- The rotation about the plant's base this frame (applied on top of each rest pose).
local function bendOf(plant: Plant, dir: Vector3, strength: number, gust: number): CFrame
	local p = plant.profile
	local t = clock * p.speed * TAU + plant.phase
	local swing = math.sin(t) * 0.7 + math.sin(t * 2.3 + plant.phase * 1.7) * 0.3
	local size = p.sway * (0.4 + 0.8 * gust + 0.3 * strength)
	local lean = math.rad((p.lean * strength + size * swing) * plant.gain)
	local wobble = math.rad(size * 0.3 * plant.gain * math.sin(t * 1.3 + 2.1))
	local bend = CFrame.fromAxisAngle(Vector3.yAxis:Cross(dir), lean) * CFrame.fromAxisAngle(dir, wobble)
	return CFrame.new(plant.base) * bend * CFrame.new(-plant.base)
end

-- One frame against a view. Public so tests and custom loops can drive it.
function FoliageSway.step(dt: number, view: CFrame)
	sincePick += dt
	if sincePick >= PICK_STEP then
		sincePick = 0
		pick(view.Position)
	end
	if #activeList == 0 then
		return
	end
	local dir, strength, gust = windNow()
	clock += dt * (1 + 0.6 * gust)
	frame += 1
	table.clear(moveParts)
	table.clear(moveFrames)
	local eye, lookDir = view.Position, view.LookVector
	for i, plant in activeList do
		local behind = (plant.base - eye):Dot(lookDir) < -plant.height
		if plant.active and not behind and not (plant.far and (frame + i) % 2 == 0) then
			local bend = bendOf(plant, dir, strength, gust)
			for k, part in plant.parts do
				if part.Parent then
					table.insert(moveParts, part)
					table.insert(moveFrames, bend * plant.rests[k])
				end
			end
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Public -------------------------------------------------------------------------------------

-- Registers every tagged plant and starts the Heartbeat loop. Idempotent.
function FoliageSway.start(opts: Options?)
	if running then
		return
	end
	running = true
	options = opts or {}
	local tag = options.tag or "ForgeGUISway"
	for _, instance in CollectionService:GetTagged(tag) do
		register(instance)
	end
	table.insert(connections, CollectionService:GetInstanceAddedSignal(tag):Connect(register))
	table.insert(connections, CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
		-- Streamed out or untagged: the server copy is the rest pose, so restore only if still here.
		unregister(instance, instance:IsDescendantOf(game))
	end))
	sincePick = PICK_STEP
	table.insert(connections, RunService.Heartbeat:Connect(function(dt: number)
		local camera = Workspace.CurrentCamera
		if camera then
			FoliageSway.step(dt, camera.CFrame)
		end
	end))
end

-- Stops and puts every moved part back. Safe to call twice.
function FoliageSway.stop(): boolean
	local wasRunning = running
	running = false
	for _, conn in connections do
		conn:Disconnect()
	end
	table.clear(connections)
	for root in plants do
		unregister(root, true)
	end
	activeList = {}
	local report = options.onLeafSource
	if report and wasRunning then
		report(nil)
	end
	return wasRunning
end

-- Puts back any part under `root` (default Workspace) that still carries this
-- module's ownership mark, e.g. after a copy of the module was reloaded mid-sway.
function FoliageSway.restoreAll(root: Instance?): number
	local fixed = 0
	for _, d in (root or Workspace):GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute(OWNED_ATTR) == true then
			local prior = d:GetAttribute(PRIOR_ATTR)
			if typeof(prior) == "CFrame" then
				d.CFrame = prior
				fixed += 1
			end
			d:SetAttribute(PRIOR_ATTR, nil)
			d:SetAttribute(OWNED_ATTR, nil)
		end
	end
	return fixed
end

function FoliageSway.isRunning(): boolean
	return running
end

return FoliageSway
