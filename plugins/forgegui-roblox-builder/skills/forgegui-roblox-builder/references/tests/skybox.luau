--!nocheck
-- From the skill root: lune run references/tests/skybox
-- Real Lune Roblox instances; no Studio, uploads, rendering, or live scene mutation.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Instance, Color3 = roblox.Instance, roblox.Color3
local checks = 0
local function check(condition, label)
	assert(condition, label)
	checks += 1
end
local lighting = Instance.new("Lighting")
local storage = Instance.new("ServerStorage")
local env = {
	Instance = Instance, Color3 = Color3,
	game = { GetService = function(_, name)
		return if name == "Lighting" then lighting elseif name == "ServerStorage" then storage else error(name)
	end },
}
local function load(name)
	return luau.load(fs.readFile("references/luau/" .. name .. ".luau"), {
		debugName = name, environment = env,
	})()
end
local function make(class, name, parent)
	local object = Instance.new(class)
	-- Lune has no default for legacy Skybox texture properties.
	if class == "Sky" then
		for _, key in { "Ft", "Bk", "Lf", "Rt", "Up", "Dn" } do
			object["Skybox" .. key] = "rbxassetid://456"
		end
	end
	object.Name = name
	object.Parent = parent
	return object
end
local faces = { Ft = 123, Bk = 124, Lf = 125, Rt = 126, Up = 127, Dn = 128 }
local watched = {
	Lighting = { "TimeOfDay", "Brightness", "Ambient", "OutdoorAmbient", "ShadowSoftness",
		"EnvironmentDiffuseScale", "EnvironmentSpecularScale", "GlobalShadows" },
	Atmosphere = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" },
	BloomEffect = { "Intensity", "Size", "Threshold", "Enabled" },
	SunRaysEffect = { "Intensity", "Spread", "Enabled" },
	Sky = { "SkyboxFt", "SkyboxBk", "SkyboxLf", "SkyboxRt", "SkyboxUp", "SkyboxDn", "StarCount" },
}
local function capture(root, result)
	result = result or {}
	local props = {}
	for _, key in watched[root.ClassName] or {} do props[key] = root[key] end
	result[root] = { parent = root.Parent, name = root.Name, props = props, attrs = root:GetAttributes() }
	for _, child in root:GetChildren() do capture(child, result) end
	return result
end
local function scene()
	return capture(storage, capture(lighting))
end
local function equalMap(actual, expected, label)
	for key, value in expected do check(actual[key] == value, label .. ": " .. key) end
	for key in actual do check(expected[key] ~= nil, label .. ": unexpected " .. key) end
end
local function sameScene(expected)
	local actual = scene()
	for object, prior in expected do
		check(actual[object] ~= nil, "original instance survives: " .. prior.name)
		check(object.Parent == prior.parent and object.Name == prior.name, "parent/name restored: " .. prior.name)
		equalMap(actual[object].props, prior.props, "properties " .. prior.name)
		equalMap(actual[object].attrs, prior.attrs, "attributes " .. prior.name)
	end
	for object in actual do check(expected[object] ~= nil, "no leaked instance: " .. object.Name) end
end

local first = make("Sky", "ForgeGUI_Sky", lighting)
first:SetAttribute("UserMetadata", "keep")
first:SetAttribute("ForgeGUIPreset", true) -- other owner's Sky is borrowed, never destroyed
first.StarCount = 73
local child = make("Folder", "SkyChild", first)
child:SetAttribute("Value", 42)
local second = make("Sky", "OriginalSky2", lighting)
make("Folder", "ForgeGUI_Sky", lighting)
make("Folder", "ForgeGUI_Bloom", lighting)
make("Folder", "ForgeGUI_OriginalSkies", storage)
local atmosphere = make("Atmosphere", "OriginalAtmosphere", lighting)
atmosphere.Density = 0.12
atmosphere.Haze = 1.25
local bloom = make("BloomEffect", "ForgeGUI_Bloom", lighting)
bloom.Intensity = 0.37
bloom.Enabled = false
local rays = make("SunRaysEffect", "OriginalRays", lighting)
rays.Intensity = 0.13
rays.Enabled = false
local extraBloom = make("BloomEffect", "UnrelatedSecondBloom", lighting)
extraBloom.Intensity = 0.71
lighting.Brightness = 1.75
lighting.TimeOfDay = "06:12:34"
lighting.GlobalShadows = false
local baseline = scene()
local skybox = load("SkyboxPresets")

local function invalidRequests()
	local before = scene()
	check(not pcall(skybox.apply, "unknown", faces), "unknown preset rejected")
	sameScene(before)
	for _, invalid in { false, "bad", 3 } do
		check(not pcall(skybox.apply, "daytime", invalid), "non-table rejected")
		sameScene(before)
	end
	check(not pcall(skybox.apply, "daytime", nil), "nil faces rejected")
	sameScene(before)
	for _, key in { "Ft", "Bk", "Lf", "Rt", "Up", "Dn" } do
		local missing = table.clone(faces)
		missing[key] = nil
		check(not pcall(skybox.apply, "daytime", missing), "missing " .. key .. " rejected")
		sameScene(before)
		for _, invalid in { 0, -1, 1.5, math.huge, -math.huge, 0/0, 9007199254740992, "123", false } do
			local bad = table.clone(faces)
			bad[key] = invalid
			check(not pcall(skybox.apply, "daytime", bad), "invalid " .. key .. " rejected")
			sameScene(before)
		end
	end
end
invalidRequests()
local applied = skybox.apply("daytime", faces)
check(applied.Parent == lighting, "apply returns active Sky")
check(first.Parent == second.Parent and first.Parent.Parent == storage, "all original skies retained outside Lighting")
check(child.Parent == first and first:GetAttribute("UserMetadata") == "keep", "Sky identity/children/attributes preserved")
for key, id in faces do check(applied["Skybox" .. key] == "rbxassetid://" .. id, "face assignment " .. key) end
check(bloom.Enabled and rays.Enabled, "borrowed disabled effects enabled")
check(extraBloom.Intensity == baseline[extraBloom].props.Intensity, "additional effect untouched")
invalidRequests() -- invalid reapply cannot damage the active preset or saved baseline
skybox = load("SkyboxPresets")
skybox.apply("nighttime", faces)
check(lighting.Brightness == 4, "reloaded apply changes preset")
check(lighting:GetAttribute("ForgeGUISkyboxPrior_Brightness") == 1.75, "first baseline retained across reload/reapply")
skybox.apply("cartoony", faces)
load("SkyboxPresets").clear()
sameScene(baseline)
load("SkyboxPresets").clear()
sameScene(baseline)

-- Empty-effect path: skybox-owned effects are removed, colliding folders survive.
for _, effect in { atmosphere, bloom, rays, extraBloom } do effect:Destroy() end
baseline = scene()
skybox.apply("daytime", faces)
for _, class in { "Atmosphere", "BloomEffect", "SunRaysEffect" } do
	check(lighting:FindFirstChildOfClass(class):GetAttribute("ForgeGUISkyboxPreset") == true, "created effect ownership " .. class)
end
load("SkyboxPresets").clear()
sameScene(baseline)

-- Layer the actual modules. Lighting-owned effects survive skybox clear, and
-- the two independent baselines unwind in reverse apply order.
-- Remove the test's foreign-owned Sky: LightingPresets.clear owns that tag.
first:SetAttribute("ForgeGUIPreset", nil)
baseline = scene()
local lightPreset = load("LightingPresets")
local _, report = lightPreset.apply("sunset")
check(#report.failed == 0, "lighting apply succeeds headlessly")
local litBaseline = scene()
skybox.apply("daytime", faces)
skybox.apply("nighttime", faces)
load("SkyboxPresets").clear()
sameScene(litBaseline)
check(load("LightingPresets").clear(), "lighting clear succeeds after skybox clear")
sameScene(baseline)
load("SkyboxPresets").clear()
sameScene(baseline)
check(not load("LightingPresets").clear(), "second lighting clear harmless")

print(`skybox regression: {checks} assertions passed (headless Lune; Studio not verified)`)
