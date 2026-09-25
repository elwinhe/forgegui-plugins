-- GroundScatter footprint harness: executes the shipped GroundScatter.luau against a
-- fake terrain whose material is a function of world X/Z, and reports whether any
-- laid patch's real (rotated, sized) footprint crosses a material boundary.
-- Usage: lune run ground-scatter-footprint.luau <path-to-GroundScatter.luau>
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Color3, Vector3, Vector2, CFrame = roblox.Color3, roblox.Vector3, roblox.Vector2, roblox.CFrame
local Enum = roblox.Enum
-- Lune hands out a fresh EnumItem userdata per access; Roblox EnumItems are singletons.
-- Pin one object per material so table keys behave as they do in the engine.
local GROUND, SAND = Enum.Material.Ground, Enum.Material.Sand
local path = process.args[1] or "plugins/forgegui-roblox-builder/skills/forgegui-roblox-builder/references/luau/GroundScatter.luau"

-- Minimal fake instances: enough of Model/Part/Folder for GroundScatter.
local function instance(class)
	local props = { ClassName = class, Name = class }
	local attrs, children = {}, {}
	local methods = {}
	local obj
	function methods:GetAttribute(k) return attrs[k] end
	function methods:SetAttribute(k, v) attrs[k] = v end
	function methods:GetChildren() return table.clone(children) end
	function methods:GetDescendants()
		local out = {}
		for _, c in children do
			table.insert(out, c)
			for _, d in c:GetDescendants() do table.insert(out, d) end
		end
		return out
	end
	function methods:IsA(name)
		if name == "BasePart" then return class == "Part" or class == "MeshPart" end
		return class == name
	end
	function methods:FindFirstChildOfClass(name)
		for _, c in children do if c.ClassName == name then return c end end
		return nil
	end
	function methods:FindFirstChildWhichIsA(name)
		for _, c in children do if c:IsA(name) then return c end end
		return nil
	end
	function methods:Destroy()
		for _, c in self:GetChildren() do c:Destroy() end
		self.Parent = nil
		props.destroyed = true
	end
	function methods:Clone()
		local copy = instance(class)
		for k, v in props do
			if k ~= "_children" and k ~= "Parent" and k ~= "destroyed" then copy[k] = v end
		end
		for k, v in attrs do copy:SetAttribute(k, v) end
		for _, c in children do
			local cc = c:Clone()
			cc.Parent = copy
			if props.PrimaryPart == c then copy.PrimaryPart = cc end
		end
		return copy
	end
	-- Model pivot/box: pivot = PrimaryPart.CFrame (or WorldPivot); box = AABB of parts in pivot frame.
	function methods:GetPivot()
		if class == "Model" then
			return props.PrimaryPart and props.PrimaryPart.CFrame or props.WorldPivot or CFrame.identity
		end
		return props.CFrame
	end
	function methods:PivotTo(target)
		local from = self:GetPivot()
		local delta = target * from:Inverse()
		for _, d in self:GetDescendants() do
			if d:IsA("BasePart") then d.CFrame = delta * d.CFrame end
		end
		if class == "Model" and not props.PrimaryPart then props.WorldPivot = target end
	end
	function methods:GetBoundingBox()
		local pivot = self:GetPivot()
		local lo, hi
		for _, d in self:GetDescendants() do
			if d:IsA("BasePart") then
				local rel = pivot:ToObjectSpace(d.CFrame)
				local h = d.Size / 2
				for _, sx in { -1, 1 } do for _, sy in { -1, 1 } do for _, sz in { -1, 1 } do
					local c = rel:PointToWorldSpace(Vector3.new(sx * h.X, sy * h.Y, sz * h.Z))
					lo = lo and Vector3.new(math.min(lo.X, c.X), math.min(lo.Y, c.Y), math.min(lo.Z, c.Z)) or c
					hi = hi and Vector3.new(math.max(hi.X, c.X), math.max(hi.Y, c.Y), math.max(hi.Z, c.Z)) or c
				end end end
			end
		end
		local centre = (lo + hi) / 2
		return pivot * CFrame.new(centre), hi - lo
	end
	obj = setmetatable({}, {
		__fake_instance = true,
		__index = function(_, k) return methods[k] or props[k] end,
		__newindex = function(_, k, v)
			if k == "Parent" then
				local old = props.Parent
				if old then
					local i = table.find(old._children, obj)
					if i then table.remove(old._children, i) end
				end
				if v then table.insert(v._children, obj) end
			end
			props[k] = v
		end,
	})
	props._children = children
	if class == "Part" or class == "MeshPart" then
		props.CFrame, props.Size, props.Color = CFrame.identity, Vector3.new(4, 1, 2), Color3.new(0.5, 0.5, 0.5)
	end
	return obj
end

-- Fake terrain: flat at Y=0, material by world X/Z. Layout copies the Studio
-- regression: Sand everywhere, Ground square X in [-72,-8], Ground road X in [20,28].
local ROAD = { 20, 28 }
local SQUARE = { -72, -8 }
local function materialAt(x, z)
	if math.abs(z) > 32 then return SAND end
	if x >= SQUARE[1] and x <= SQUARE[2] then return GROUND end
	if x >= ROAD[1] and x <= ROAD[2] then return GROUND end
	return SAND
end
local rays = 0
local Workspace = instance("Workspace")
Workspace.Terrain = instance("Terrain")
Workspace.Raycast = function(_, origin, direction)
	rays += 1
	if origin.Y + direction.Y > 0 then return nil end
	return { Position = Vector3.new(origin.X, 0, origin.Z), Normal = Vector3.yAxis, Material = materialAt(origin.X, origin.Z), Instance = Workspace.Terrain }
end
local services = { Workspace = Workspace, RunService = { Heartbeat = { Connect = function() return { Disconnect = function() end } end } } }
local env = {
	game = { GetService = function(_, n) return assert(services[n], n) end },
	workspace = Workspace, Color3 = Color3, Vector3 = Vector3, Vector2 = Vector2, CFrame = CFrame, Enum = Enum,
	Instance = { new = instance }, RaycastParams = { new = function() return {} end }, warn = print,
	typeof = function(v)
		local mt = type(v) == "table" and getmetatable(v)
		return if mt and mt.__fake_instance then "Instance" else typeof(v)
	end,
}
local GroundScatter = luau.load(fs.readFile(path), { debugName = "GroundScatter", environment = env })()

local function template(sx, sz)
	local m = instance("Model")
	local slab = instance("Part")
	slab.Size = Vector3.new(sx, 0.6, sz)
	slab.Parent = m
	m.PrimaryPart = slab
	return m
end

-- Real footprint of a laid patch: its bounding box corners projected to XZ.
local function footprintCorners(model)
	local box, size = model:GetBoundingBox()
	local out = {}
	for _, sx in { -1, 1 } do for _, sz in { -1, 1 } do
		table.insert(out, box:PointToWorldSpace(Vector3.new(sx * size.X / 2, 0, sz * size.Z / 2)))
	end end
	return out, box, size
end

local function run(label, tpl)
	local scratch = instance("Folder")
	GroundScatter.start({ kinds = { [GROUND] = { template = tpl } }, manual = true, parent = scratch, radius = 90 })
	for _ = 1, 400 do
		GroundScatter.step(Vector3.zero)
		if GroundScatter.stats().queued == 0 then break end
	end
	local patches = scratch:GetChildren()[1]:GetChildren()
	assert(#patches > 0, label .. ": must place patches")
	for _, patch in patches do
		for _, point in footprintCorners(patch) do
			assert(materialAt(point.X, point.Z) == GROUND, label .. ": actual corner crosses material boundary")
		end
	end
	GroundScatter.stop()
	scratch:Destroy()
	print(label, #patches, "patches: full corners pass")
end

local fixedMath = table.clone(math)
fixedMath.sin = function() return 0.5 / 43758.5453 end
local fixedEnv = table.clone(env)
fixedEnv.math = fixedMath
local fixed = luau.load(fs.readFile(path), { environment = fixedEnv })()
local roadCentre = 5.25 - 1.4
local originalRaycast = Workspace.Raycast
Workspace.Raycast = function(_, origin)
	return {
		Position = Vector3.new(origin.X, 0, origin.Z), Normal = Vector3.yAxis,
		Material = if math.abs(origin.X - roadCentre) <= 7 then GROUND else SAND,
		Instance = Workspace.Terrain,
	}
end
local function boundaryCase(centre, expected, footprint)
	roadCentre = centre
	local scratch = instance("Folder")
	fixed.start({ kinds = { [GROUND] = { template = template(12, 12) } }, manual = true,
		parent = scratch, radius = 1, jitter = 0, footprint = footprint })
	fixed.step(Vector3.new(5.25, 0, 5.25))
	local count = #scratch:GetChildren()[1]:GetChildren()
	fixed.stop()
	scratch:Destroy()
	assert(count == expected, "14-stud road: expected " .. expected .. " patches, got " .. count)
end
boundaryCase(5.25 - 1.4, 0)
boundaryCase(5.25, 1)
boundaryCase(5.25 - 1.4, 1, 5.52)
print("PASS: overhang rejected; fitting patch accepted; explicit inset remains opt-in")

Workspace.Raycast = originalRaycast
run("12x12", template(12, 12))
run("12x6", template(12, 6))
run("6x12", template(6, 12))
run("16x4", template(16, 4))
local offset = template(12, 6)
offset.PrimaryPart.CFrame = CFrame.new(3, 0, 2)
offset.PrimaryPart = nil
run("offset pivot 12x6", offset)

