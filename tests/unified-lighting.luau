-- Executes the shipped sources, not a port of their algorithms.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Color3, Vector3, Vector2, CFrame = roblox.Color3, roblox.Vector3, roblox.Vector2, roblox.CFrame
local source = "plugins/forgegui-roblox-builder/skills/forgegui-roblox-builder/references/luau/"
local checks = 0
local function check(ok, message)
	assert(ok, message)
	checks += 1
end
local function signal()
	local listeners = {}
	return {
		Connect = function(_, fn)
			listeners[fn] = true
			return { Disconnect = function() listeners[fn] = nil end }
		end,
		Fire = function(_, ...)
			for fn in listeners do fn(...) end
		end,
	}
end
local function instance(class)
	local props = { ClassName = class, Name = class }
	local attrs, children, signals = {}, {}, {}
	if class == "DepthOfFieldEffect" then
		props.Enabled, props.FocusDistance, props.InFocusRadius = false, 33, 19
		props.NearIntensity, props.FarIntensity = 0.12, 0.24
	end
	local methods = {}
	function methods:GetAttribute(key) return attrs[key] end
	function methods:SetAttribute(key, value) attrs[key] = value end
	function methods:GetAttributes() return table.clone(attrs) end
	function methods:GetChildren() return table.clone(children) end
	function methods:IsA(name) return class == name end
	function methods:FindFirstChildOfClass(name)
		for _, c in children do if c.ClassName == name then return c end end
		return nil
	end
	function methods:GetPropertyChangedSignal(name)
		if not signals[name] then signals[name] = signal() end
		return signals[name]
	end
	function methods:Destroy()
		for _, child in self:GetChildren() do child:Destroy() end
		self.Parent = nil
		props.destroyed = true
	end
	local obj
	obj = setmetatable({}, {
		__index = function(_, key) return methods[key] or props[key] end,
		__newindex = function(_, key, value)
			if key == "Parent" then
				local old = props.Parent
				if old then
					local index = table.find(old._children, obj)
					if index then table.remove(old._children, index) end
				end
				if value then table.insert(value._children, obj) end
			end
			-- Deliberately quantize all Lighting colours to stress readback ownership.
			if class == "Lighting" and typeof(value) == "Color3" then
				value = Color3.fromRGB(math.round(value.R * 255), math.round(value.G * 255), math.round(value.B * 255))
			end
			props[key] = value
			if signals[key] then signals[key]:Fire() end
		end,
	})
	props._children = children
	return obj
end
local Lighting, Workspace = instance("Lighting"), instance("Workspace")
Workspace.Terrain = instance("Terrain")
Workspace.Terrain.Parent = Workspace
Workspace.Raycast = function() return nil end
Lighting.GetSunDirection = function() return Vector3.new(0, 1, 0) end
Lighting.ClockTime, Lighting.Brightness = 12, 2
local render = {}
local RunService = {
	Heartbeat = signal(),
	BindToRenderStep = function(_, name, _, fn) render[name] = fn end,
	UnbindFromRenderStep = function(_, name) render[name] = nil end,
}
local services = { Lighting = Lighting, Workspace = Workspace, RunService = RunService,
	Players = { GetPlayers = function() return {} end }, ServerStorage = instance("ServerStorage") }
local env = {
	game = { GetService = function(_, name) return assert(services[name], name) end },
	workspace = Workspace, Color3 = Color3, Vector3 = Vector3, Vector2 = Vector2, CFrame = CFrame,
	Enum = roblox.Enum, Instance = { new = instance }, RaycastParams = { new = function() return {} end },
	warn = function(...) print(...) end,
}
local modules = {}
local function load(name)
	if modules[name] then return modules[name] end
	local scope = table.clone(env)
	scope.script = { Parent = { LightingCompositor = "LightingCompositor" } }
	scope.require = function(module) return load(module) end
	modules[name] = luau.load(fs.readFile(source .. name .. ".luau"), { debugName = name, environment = scope })()
	return modules[name]
end
local properties = { "Ambient", "OutdoorAmbient", "ColorShift_Top", "ColorShift_Bottom" }
local function snapshot()
	local b = {}
	for _, p in properties do b[p] = Lighting[p] end
	return b
end
local function colours(actual, expected, label)
	for _, p in properties do
		local a, b = actual[p], expected[p]
		check(math.abs(a.R-b.R) < 1/255+1e-6 and math.abs(a.G-b.G) < 1/255+1e-6 and math.abs(a.B-b.B) < 1/255+1e-6, label .. ": " .. p)
	end
end
local function camera()
	local c = instance("Camera")
	c.CFrame, c.Focus = CFrame.new(0, 5, 12), CFrame.new(0, 5, 0)
	c.ViewportSize, c.FieldOfView, c.Parent = Vector2.new(1280, 720), 70, Workspace
	return c
end
Workspace.CurrentCamera = camera()
local initial = {
	Ambient = Color3.fromRGB(61, 70, 80), OutdoorAmbient = Color3.fromRGB(102, 111, 120),
	ColorShift_Top = Color3.fromRGB(180, 150, 120), ColorShift_Bottom = Color3.fromRGB(70, 60, 50),
}
local grade = { exposure = 0, contrast = 0.1, saturation = 0, brightness = 0, tint = Color3.new(1,1,1),
	shadowTint = Color3.new(0.5, 0.8, 1), highlightTint = Color3.new(1, 0.7, 0.5) }
local C, G, GI, Fx = load("LightingCompositor"), load("ColourGrade"), load("GlobalIllumination"), load("CameraFx")
local Presets, Sky = load("LightingPresets"), load("SkyboxPresets")
local function reset()
	G.stop(); GI.stop()
	for p, v in initial do Lighting[p] = v end
end
local function startGrade()
	G.start({ keyframes = { { clock = 0, grade = grade } } }); G.step()
end
local function startGI(getter)
	GI.start({ manual = true, level = 1, getBase = getter, getFocus = function() return Vector3.zero end }); GI.step(0.1)
end
local stable
for _, gradeFirst in { true, false } do
	for _, stopGradeFirst in { true, false } do
		reset()
		if gradeFirst then startGrade(); startGI() else startGI(); startGrade() end
		local expected = snapshot()
		if stable then colours(expected, stable, "start order") else stable = expected end
		for i = 1, 160 do
			if i % 2 == 0 then G.step(); GI.step(0.1) else GI.step(0.1); G.step() end
			colours(snapshot(), expected, "stable alternating " .. i)
		end
		if stopGradeFirst then
			G.stop()
			local giOnly = snapshot()
			GI.step(0.1); colours(snapshot(), giOnly, "GI remains after grade stop")
			GI.stop()
		else
			GI.stop()
			local gradeOnly = snapshot()
			G.step(); colours(snapshot(), gradeOnly, "grade remains after GI stop")
			G.stop()
		end
		colours(snapshot(), initial, "both stopped")
		G.stop(); GI.stop(); colours(snapshot(), initial, "repeated stop")
	end
end
-- Assert the composition equation, not just repeatability.
reset(); startGI()
local giOnly = snapshot()
check(giOnly.OutdoorAmbient ~= initial.OutdoorAmbient, "GI changes the scene")
startGrade()
local tone, topTone = G.nudge(grade.shadowTint), G.nudge(grade.highlightTint)
local function times(a, b)
	return Color3.new(math.min(a.R*b.R,1), math.min(a.G*b.G,1), math.min(a.B*b.B,1))
end
colours(snapshot(), {
	Ambient = times(giOnly.Ambient, tone), OutdoorAmbient = times(giOnly.OutdoorAmbient, tone),
	ColorShift_Top = times(initial.ColorShift_Top, topTone), ColorShift_Bottom = giOnly.ColorShift_Bottom,
}, "base then GI then grade equation")
reset(); startGrade(); startGI()
GI.setLevel(0); G.setStrength(0); G.step()
colours(snapshot(), initial, "both off")
GI.setLevel(1); G.setStrength(1); GI.step(0.1); G.step()
colours(snapshot(), stable, "on again")
local external = Color3.fromRGB(41, 51, 62)
Lighting.Ambient = external
G.step(); GI.step(0.1)
check(C.getBase().Ambient == external, "external tiny or large write becomes base")
Lighting.Ambient = Color3.fromRGB(42, 51, 62)
GI.stop(); G.stop()
check(Lighting.Ambient == Color3.fromRGB(42, 51, 62), "stop captures external edit without a step")
reset(); startGrade(); startGI()
C.setBase({ Ambient = Lighting.Ambient })
local explicit = C.getBase().Ambient
GI.stop(); G.stop()
check(Lighting.Ambient == explicit, "explicit same-output base input")
check(not pcall(function() C.setBase({ Brightness = 1 }) end), "reject unsupported base property")
reset(); startGrade()
local supplied = { ambient = external, outdoor = initial.OutdoorAmbient, bottom = initial.ColorShift_Bottom }
startGI(function() return supplied end)
check(C.getBase().Ambient == external, "GI getBase feeds shared base")
supplied.ambient = Color3.fromRGB(90, 80, 70)
GI.stop(); G.stop()
check(Lighting.Ambient == supplied.ambient, "stop captures latest getBase")
for _, presetFirst in { false, true } do
	reset()
	if presetFirst then Presets.apply("dungeon_torchlit") end
	startGrade(); startGI()
	if not presetFirst then Presets.apply("dungeon_torchlit") end
	G.step(); GI.step(0.1)
	check(Lighting:GetAttribute("ForgeGUIPrior_Ambient") == initial.Ambient, "preset prior is raw base")
	local presetBase = C.getBase()
	Sky.apply("daytime", { Ft=1, Bk=2, Lf=3, Rt=4, Up=5, Dn=6 })
	G.step(); GI.step(0.1)
	check(Lighting:GetAttribute("ForgeGUISkyboxPrior_Ambient") == presetBase.Ambient, "sky prior is preset base")
	Sky.clear(); G.step(); GI.step(0.1)
	colours(C.getBase(), presetBase, "sky clear restores preset")
	Presets.clear(); G.step(); GI.step(0.1)
	colours(C.getBase(), initial, "preset clear under active layers")
	GI.stop(); G.stop(); colours(snapshot(), initial, "preset teardown")
end
reset(); startGrade(); startGI()
local preset = Presets.Presets.dungeon_torchlit
local originalPresetAmbient = preset.lighting.Ambient
local visible = Lighting.Ambient
preset.lighting.Ambient = visible
Presets.apply("dungeon_torchlit"); G.step(); GI.step(0.1)
check(C.getBase().Ambient == visible, "preset input equal to output becomes new base")
Presets.clear(); G.step(); GI.step(0.1)
colours(C.getBase(), initial, "equal-output preset clear restores original base")
preset.lighting.Ambient = originalPresetAmbient
GI.stop(); G.stop()

reset(); startGrade(); startGI()
Presets.apply("dungeon_torchlit")
Presets.clear() -- neither layer stepped between apply and clear
GI.stop(); G.stop()
colours(snapshot(), initial, "preset apply/clear without intervening layer update")
reset(); startGrade()
local success, failure = pcall(function()
	GI.start({ manual = true, getBase = function() error("base callback failed") end })
end)
check(not success and string.find(tostring(failure), "base callback failed") ~= nil, "getBase errors propagate")
check(not GI.stats().running, "failed start does not acquire lifecycle")
GI.start({ manual = true, level = 0 }) -- recover the callback; then clean up
GI.stop(); G.stop()
reset(); startGrade()
local noCamera = Workspace.CurrentCamera
Workspace.CurrentCamera = nil
GI.start({ manual = true, level = 1 })
GI.step(0.1)
GI.setLevel(0); G.setStrength(0); G.step()
colours(snapshot(), initial, "off works without a camera")
GI.stop(); G.stop()
Workspace.CurrentCamera = noCamera


reset()
local failBase = false
startGI(function()
	if failBase then error("stop callback failed") end
	return { ambient = initial.Ambient, outdoor = initial.OutdoorAmbient, bottom = initial.ColorShift_Bottom }
end)
failBase = true
check(not pcall(GI.stop), "stop callback error propagates")
check(not GI.stats().running, "failing callback still stops lifecycle")
colours(snapshot(), initial, "failing callback still removes GI layer")
check(GI.stop() == false, "stop remains idempotent after callback error")

-- Borrowed effects on retained/destroyed cameras, nil gaps and Lighting.
local function foreign(parent)
	local d = instance("DepthOfFieldEffect"); d.Parent = parent
	return d
end
for _, parentKind in { "camera", "Lighting" } do
	for _, destroyOld in { false, true } do
		local a, b = camera(), camera()
		Workspace.CurrentCamera = a
		local old = foreign(if parentKind == "camera" then a else Lighting)
		local nextDof = if parentKind == "camera" then foreign(b) else old
		Fx.start({ depthOfField = true })
		Fx.step(a, 1/60)
		for i = 1, 10 do
			a.CFrame = CFrame.new(0,5,12) * CFrame.Angles(0, i * 0.02, 0)
			Fx.step(a, 1/60)
		end
		check(Fx.motion() > 0, "motion history populated")
		if destroyOld then a:Destroy() end
		Workspace.CurrentCamera = nil
		check(Fx.effect() == nil, "nil camera releases immediately")
		check(old.FocusDistance == 33 and old.FarIntensity == 0.24, "old borrowed state restored")
		check(old:GetAttribute("ForgeGUICameraFxAdopted") == nil, "old adoption cleared")
		Workspace.CurrentCamera = b
		Fx.step(b, 1/60)
		check(Fx.effect() == nextDof, "adopts current view effect")
		local far, near = Fx.motion()
		check(far == 0 and near == 0, "camera change resets motion")
		Fx.stop(); Fx.stop()
		check(nextDof.FocusDistance == 33 and nextDof.FarIntensity == 0.24, "stop restores current borrowed state")
		check(not nextDof.destroyed, "foreign effect never destroyed")
		old:Destroy(); nextDof:Destroy(); b:Destroy()
	end
end
-- Direct replacement without a nil interval restores the old adopted effect.
do
	local a, b = camera(), camera()
	local old, nextDof = foreign(a), foreign(b)
	Workspace.CurrentCamera = a
	Fx.start(); Fx.step(a, 1/60)
	old.FocusDistance = 47 -- a foreign edit right before release survives
	Workspace.CurrentCamera = b
	check(old.FocusDistance == 47 and old.FarIntensity == 0.24, "direct swap preserves external effect edit")
	Fx.step(b, 1/60)
	check(Fx.effect() == nextDof, "direct swap adopts new camera effect")
	Fx.stop()
	check(old.Parent == a and nextDof.Parent == b, "retained camera foreign effects survive")
	a:Destroy(); b:Destroy()
end
local a, b = camera(), camera()
Workspace.CurrentCamera = a
Fx.start(); Fx.step(a, 1/60)
local owned = Fx.effect()
Workspace.CurrentCamera = b; Fx.step(b, 1/60)
check(owned.destroyed and Fx.effect().Parent == b, "owned effect follows camera")
local finalOwned = Fx.effect()
Fx.stop()
check(finalOwned.destroyed, "stop destroys owned effect")
-- Every shipped Luau source must at least compile, including original feature modules.
for _, file in fs.readDir(source) do
	if string.match(file, "%.luau$") then
		luau.compile(fs.readFile(source .. file))
	end
end
for _, file in { "post-stack-regression.luau", "light-transport-regression.luau", "unified-lighting-regression.luau" } do
	luau.compile(fs.readFile("docs/evidence/" .. file))
end
print("PASS unified lighting: " .. checks .. " assertions; shipped Luau sources compile")
