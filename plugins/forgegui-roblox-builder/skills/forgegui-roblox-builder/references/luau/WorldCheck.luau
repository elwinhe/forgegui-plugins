--!strict
-- Placement checks to run after anything reshapes a world.
--
-- A fidelity pass swapped island geometry for terrain, and a SpawnLocation the
-- Baseplate template had left at the origin ended up twenty studs inside rock.
-- Roblox picks among enabled spawns at random, so a player sometimes spawned
-- in the ground. Nothing in a screenshot shows that; these checks do.
--
-- Run in Studio Edit mode (or on the server during play):
--
--   local report = WorldCheck.run({ floors = { ... }, interactives = { ... } })
--   print(WorldCheck.format(report))
--
-- The logic takes an adapter, so it runs headless against stubs;
-- WorldCheck.robloxAdapter() is the real one.
--
-- execute_luau cannot require place modules; paste this file ahead of a runner
-- with references/tools/paste_module.py (see references/world-and-ui-checks.md).

local WorldCheck = {}

export type Hit = { position: Vector3, name: string }
export type Adapter = {
	spawns: () -> { any },
	-- World-space centre and vertical half-height of a part or model, rotation included.
	extents: (object: any) -> (Vector3, number),
	-- Horizontal footprint (width, depth) of a spawn's top surface, in studs.
	footprint: (spawn: any) -> (number, number),
	-- First solid thing (terrain or a collidable part) along a ray, ignoring `ignore`.
	raycast: (origin: Vector3, direction: Vector3, ignore: { any }?) -> Hit?,
	-- Names of solid things overlapping an axis-aligned box, ignoring `ignore`.
	solidInBox: (cframe: CFrame, size: Vector3, ignore: { any }?) -> { string },
	-- Oriented bounding box of a part or model. Optional: without it `clutter` is not checked.
	box: ((object: any) -> (CFrame, Vector3))?,
}
export type Finding = { check: string, severity: string, subject: string, detail: string }
export type Report = { findings: { Finding }, errors: number, warnings: number, checked: { [string]: number } }
export type Options = {
	adapter: Adapter?,
	-- Walkable parts that terrain or props must not cover (an invisible floor, say).
	floors: { any }?,
	-- Parts or models players must be able to see and reach: pads, pickups, prompts.
	interactives: { any }?,
	-- Space a character needs above a spawn, in studs.
	clearance: Vector3?,
	-- How far above a spawn or floor a surface may sit before it counts as covering it.
	tolerance: number?,
	-- How high above a spawn or part to look for cover. An island floating far
	-- overhead is sky, not a roof.
	coverHeight: number?,
	-- Placed props (crates, rocks, trees) that must not stand inside a building,
	-- wall or walkway. Each is tested by its bounding box shrunk to `clutterShrink`
	-- (a prop may touch a wall, not pass into it); terrain never counts, since
	-- props are sunk into the ground on purpose. A KeepOutTrunk attribute (0..1)
	-- narrows X and Z to the trunk, so a tree crown may overhang a roof.
	clutter: { any }?,
	clutterShrink: number?,
}

local DEFAULT_CLEARANCE = Vector3.new(4, 6, 4)
local DEFAULT_TOLERANCE = 0.5
local DEFAULT_COVER_HEIGHT = 60
-- Matches KeepOut.luau's default, so the check reports what the placement guard would have refused.
local DEFAULT_CLUTTER_SHRINK = 0.7
-- Roblox places a character at a random point at least a stud in from a spawn's
-- edge; a pad under about 3.2 studs on either side falls back to its centre.
local MIN_SPAWN_SIDE = 4

local function add(report: Report, check: string, severity: string, subject: string, detail: string)
	table.insert(report.findings, { check = check, severity = severity, subject = subject, detail = detail })
	if severity == "error" then
		report.errors += 1
	else
		report.warnings += 1
	end
end

local function nameOf(object: any): string
	local ok, full = pcall(function()
		return object:GetFullName()
	end)
	return if ok then full else tostring(object.Name)
end

-- The first solid surface met looking straight down onto a point from `height`
-- above it, ignoring the object being tested.
local function surfaceAbove(adapter: Adapter, point: Vector3, height: number, ignore: { any }): Hit?
	return adapter.raycast(Vector3.new(point.X, point.Y + height, point.Z), Vector3.new(0, -height, 0), ignore)
end

local function checkSpawnPool(report: Report, enabled: { any })
	-- Neutral spawns share one pool; each team colour has its own.
	local groups: { [string]: { any } } = {}
	local order = {}
	for _, spawn in ipairs(enabled) do
		local key = if spawn.Neutral then "neutral" else "team " .. tostring(spawn.TeamColor)
		if not groups[key] then
			groups[key] = {}
			table.insert(order, key)
		end
		table.insert(groups[key], spawn)
	end
	for _, key in ipairs(order) do
		local members = groups[key]
		local intended = false
		local names = {}
		for _, spawn in ipairs(members) do
			intended = intended or spawn:GetAttribute("MultipleSpawnsIntended") == true
			table.insert(names, nameOf(spawn))
		end
		if #members > 1 and not intended then
			add(report, "multiple_spawns", "warning", key, ("%d enabled spawns (%s). Roblox picks one at random, so every one must be valid; disable leftovers, or set MultipleSpawnsIntended."):format(#members, table.concat(names, ", ")))
		end
	end
end

type Limits = { clearance: Vector3, tolerance: number, coverHeight: number }

local function checkSpawns(adapter: Adapter, report: Report, limits: Limits)
	local enabled = {}
	for _, spawn in ipairs(adapter.spawns()) do
		if spawn.Enabled then
			table.insert(enabled, spawn)
		end
	end
	report.checked.spawns = #enabled
	checkSpawnPool(report, enabled)

	for _, spawn in ipairs(enabled) do
		local name = nameOf(spawn)
		local center, halfHeight = adapter.extents(spawn)
		local top = center.Y + halfHeight
		local ignore = { spawn }
		local clearance = limits.clearance

		local width, depth = adapter.footprint(spawn)
		if width < MIN_SPAWN_SIDE or depth < MIN_SPAWN_SIDE then
			add(report, "spawn_small", "warning", name, ("the top is %gx%g studs; under %g on a side, players stack on its centre."):format(width, depth, MIN_SPAWN_SIDE))
		end

		local cover = surfaceAbove(adapter, center, halfHeight + limits.coverHeight, ignore)
		if cover and cover.position.Y > top + limits.tolerance and spawn:GetAttribute("AllowCovered") ~= true then
			add(report, "spawn_buried", "error", name, ("%s surface is %.1f studs above the spawn top (%.1f): a player spawning here starts inside or under it."):format(cover.name, cover.position.Y - top, top))
		end

		local box = CFrame.new(center.X, top + 0.1 + clearance.Y / 2, center.Z)
		local blocking = adapter.solidInBox(box, clearance, ignore)
		if #blocking > 0 then
			add(report, "spawn_clearance", "error", name, ("the %gx%gx%g space above the spawn overlaps %s."):format(clearance.X, clearance.Y, clearance.Z, table.concat(blocking, ", ")))
		end
	end
end

local function checkCovered(adapter: Adapter, report: Report, objects: { any }, check: string, limits: Limits)
	report.checked[check] = #objects
	for _, object in ipairs(objects) do
		local center, halfHeight = adapter.extents(object)
		local top = center.Y + halfHeight
		local cover = surfaceAbove(adapter, center, halfHeight + limits.coverHeight, { object })
		if cover and cover.position.Y > top + limits.tolerance then
			add(report, check, "error", nameOf(object), ("%s covers it: surface at %.1f, top at %.1f."):format(cover.name, cover.position.Y, top))
		end
	end
end

local function checkClutter(adapter: Adapter, report: Report, objects: { any }, shrink: number)
	report.checked.clutter = #objects
	local box = adapter.box
	if not box then
		return
	end
	for _, object in ipairs(objects) do
		if object:GetAttribute("AllowOverlap") == true then
			continue
		end
		local cframe, size = box(object)
		local trunk = object:GetAttribute("KeepOutTrunk")
		local share = if type(trunk) == "number" then trunk else shrink
		local probe = Vector3.new(size.X * share, size.Y * shrink, size.Z * share)
		local hits = {}
		for _, name in ipairs(adapter.solidInBox(cframe, probe, { object })) do
			if string.sub(name, 1, 7) ~= "Terrain" then
				table.insert(hits, name)
			end
		end
		if #hits > 0 then
			add(report, "clutter_overlap", "error", nameOf(object), ("its box shrunk to %g overlaps %s: it stands inside something solid."):format(shrink, table.concat(hits, ", ")))
		end
	end
end

function WorldCheck.run(options: Options?): Report
	local settings: Options = options or {}
	local adapter = settings.adapter or WorldCheck.robloxAdapter()
	local limits: Limits = {
		clearance = settings.clearance or DEFAULT_CLEARANCE,
		tolerance = settings.tolerance or DEFAULT_TOLERANCE,
		coverHeight = settings.coverHeight or DEFAULT_COVER_HEIGHT,
	}
	local report: Report = { findings = {}, errors = 0, warnings = 0, checked = {} }
	checkSpawns(adapter, report, limits)
	checkCovered(adapter, report, settings.floors or {}, "floor_covered", limits)
	checkCovered(adapter, report, settings.interactives or {}, "interactive_covered", limits)
	checkClutter(adapter, report, settings.clutter or {}, settings.clutterShrink or DEFAULT_CLUTTER_SHRINK)
	return report
end

function WorldCheck.format(report: Report): string
	local lines = { ("WorldCheck: %d error(s), %d warning(s)"):format(report.errors, report.warnings) }
	local checked = {}
	for key, count in pairs(report.checked) do
		table.insert(checked, ("%s=%d"):format(key, count))
	end
	table.sort(checked)
	table.insert(lines, "checked " .. table.concat(checked, " "))
	for _, finding in ipairs(report.findings) do
		table.insert(lines, ("[%s] %s %s: %s"):format(finding.severity, finding.check, finding.subject, finding.detail))
	end
	return table.concat(lines, "\n")
end

-- Terrain voxels whose centre lies inside an axis-aligned box. Cells that only
-- touch the box are skipped, so ground a spawn stands on is not counted as
-- something in the character's way.
local function solidVoxelsInBox(low: Vector3, high: Vector3): number
	local region = Region3.new(low, high):ExpandToGrid(4)
	local materials, occupancies = workspace.Terrain:ReadVoxels(region, 4)
	local origin = region.CFrame.Position - region.Size / 2
	local solid = 0
	for x = 1, materials.Size.X do
		for y = 1, materials.Size.Y do
			for z = 1, materials.Size.Z do
				local center = origin + Vector3.new(x - 0.5, y - 0.5, z - 0.5) * 4
				local inside = center.X >= low.X and center.X <= high.X and center.Y >= low.Y and center.Y <= high.Y and center.Z >= low.Z and center.Z <= high.Z
				if inside and occupancies[x][y][z] > 0.5 and materials[x][y][z] ~= Enum.Material.Water then
					solid += 1
				end
			end
		end
	end
	return solid
end

-- The real adapter: terrain and collidable parts count as solid; characters
-- never do, so a check during play is not blocked by the player standing there.
function WorldCheck.robloxAdapter(): Adapter
	local Players = game:GetService("Players")
	local function exclusions(ignore: { any }?): { Instance }
		local list: { Instance } = {}
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character then
				table.insert(list, player.Character)
			end
		end
		for _, item in ipairs(ignore or {}) do
			table.insert(list, item)
		end
		return list
	end
	return {
		spawns = function()
			local list = {}
			for _, item in ipairs(workspace:GetDescendants()) do
				if item:IsA("SpawnLocation") then
					table.insert(list, item)
				end
			end
			return list
		end,
		extents = function(object)
			local cframe, size
			if object:IsA("Model") then
				cframe, size = object:GetBoundingBox()
			else
				cframe, size = object.CFrame, object.Size
			end
			-- A cylinder lying on its side is tall in X; project every axis onto world Y.
			local _, _, _, _, _, _, r10, r11, r12 = cframe:GetComponents()
			return cframe.Position, (math.abs(r10) * size.X + math.abs(r11) * size.Y + math.abs(r12) * size.Z) / 2
		end,
		footprint = function(spawn)
			-- World-space X and Z extents of the pad, rotation included.
			local _, _, _, r00, r01, r02, _, _, _, r20, r21, r22 = spawn.CFrame:GetComponents()
			local size = spawn.Size
			return math.abs(r00) * size.X + math.abs(r01) * size.Y + math.abs(r02) * size.Z, math.abs(r20) * size.X + math.abs(r21) * size.Y + math.abs(r22) * size.Z
		end,
		raycast = function(origin, direction, ignore)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = exclusions(ignore)
			params.RespectCanCollide = true
			local result = workspace:Raycast(origin, direction, params)
			if not result then
				return nil
			end
			local name = if result.Instance == workspace.Terrain then "Terrain (" .. result.Material.Name .. ")" else result.Instance:GetFullName()
			return { position = result.Position, name = name }
		end,
		box = function(object)
			if object:IsA("Model") then
				return object:GetBoundingBox()
			end
			return object.CFrame, object.Size
		end,
		solidInBox = function(cframe, size, ignore)
			local names = {}
			local params = OverlapParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = exclusions(ignore)
			params.RespectCanCollide = true
			for _, part in ipairs(workspace:GetPartBoundsInBox(cframe, size, params)) do
				table.insert(names, part:GetFullName())
			end
			-- Part queries do not report terrain; read its voxels directly.
			local solid = solidVoxelsInBox(cframe.Position - size / 2, cframe.Position + size / 2)
			if solid > 0 then
				table.insert(names, ("Terrain (%d solid voxels)"):format(solid))
			end
			return names
		end,
	}
end

return WorldCheck
