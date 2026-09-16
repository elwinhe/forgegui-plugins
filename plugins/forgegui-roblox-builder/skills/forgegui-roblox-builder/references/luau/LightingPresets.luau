--!strict
-- LightingPresets: named, reviewed Lighting + post-processing configurations.
-- Ship as a ModuleScript (ReplicatedStorage.LightingPresets) or paste the body into
-- execute_luau / the command bar and call `apply("sunset")`.
--
-- Idempotent: post-processing instances are created once and tagged with the
-- attribute ForgeGUIPreset = true; later applies reconfigure them instead of stacking.
-- Nothing here downloads code or inserts assets.
-- Lighting.Technology is NOT scriptable (Studio Properties panel only); presets record a
-- recommended technology in `technology` for the agent to report, never to set.

local Lighting = game:GetService("Lighting")

export type Preset = {
	description: string,
	technology: string, -- recommended Lighting.Technology; set manually in Studio Properties
	lighting: { [string]: any },
	atmosphere: { [string]: any }?,
	bloom: { [string]: any }?,
	colorCorrection: { [string]: any }?,
	sunRays: { [string]: any }?,
	depthOfField: { [string]: any }?,
}

local function c3(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Presets: { [string]: Preset } = {
	bright_stylized = {
		technology = "ShadowMap",
		description = "Clean daytime look for simulators, obbies and tycoons. Saturated, soft shadows, mild bloom.",
		lighting = {
			ClockTime = 13.5,
			Brightness = 2.4,
			Ambient = c3(120, 120, 130),
			OutdoorAmbient = c3(140, 150, 170),
			ColorShift_Top = c3(255, 250, 240),
			ColorShift_Bottom = c3(200, 205, 215),
			EnvironmentDiffuseScale = 0.6,
			EnvironmentSpecularScale = 0.6,
			ExposureCompensation = 0.15,
			GlobalShadows = true,
			ShadowSoftness = 0.35,
			FogEnd = 100000,
		},
		atmosphere = { Density = 0.28, Offset = 0.2, Color = c3(199, 210, 232), Decay = c3(106, 130, 170), Glare = 0.15, Haze = 0.8 },
		bloom = { Intensity = 0.3, Size = 24, Threshold = 1.5 },
		colorCorrection = { Brightness = 0.02, Contrast = 0.1, Saturation = 0.2, TintColor = c3(255, 255, 255) },
		sunRays = { Intensity = 0.06, Spread = 0.6 },
		depthOfField = { Enabled = false },
	},
	overcast = {
		technology = "ShadowMap",
		description = "Flat grey daylight for survival, farming and quiet exploration. Low contrast, no sun rays.",
		lighting = {
			ClockTime = 11,
			Brightness = 1.2,
			Ambient = c3(128, 132, 140),
			OutdoorAmbient = c3(150, 155, 165),
			ColorShift_Top = c3(220, 225, 235),
			ColorShift_Bottom = c3(180, 185, 195),
			EnvironmentDiffuseScale = 0.9,
			EnvironmentSpecularScale = 0.3,
			ExposureCompensation = -0.1,
			GlobalShadows = true,
			ShadowSoftness = 0.9,
			FogColor = c3(196, 200, 208),
			FogStart = 200,
			FogEnd = 1400,
		},
		atmosphere = { Density = 0.45, Offset = 0.5, Color = c3(200, 204, 212), Decay = c3(150, 155, 165), Glare = 0, Haze = 2.2 },
		bloom = { Intensity = 0.1, Size = 16, Threshold = 2 },
		colorCorrection = { Brightness = 0, Contrast = -0.05, Saturation = -0.25, TintColor = c3(235, 240, 250) },
		sunRays = { Intensity = 0, Spread = 1 },
		depthOfField = { Enabled = false },
	},
	night_neon = {
		technology = "Future",
		description = "Dark city or arcade night. Near-black ambient so emissive parts and neons carry the scene.",
		lighting = {
			ClockTime = 0.5,
			Brightness = 0.6,
			Ambient = c3(18, 16, 32),
			OutdoorAmbient = c3(28, 24, 48),
			ColorShift_Top = c3(120, 80, 200),
			ColorShift_Bottom = c3(30, 20, 60),
			EnvironmentDiffuseScale = 0.25,
			EnvironmentSpecularScale = 0.8,
			ExposureCompensation = 0.4,
			GlobalShadows = true,
			ShadowSoftness = 0.2,
			FogColor = c3(12, 10, 24),
			FogStart = 120,
			FogEnd = 900,
		},
		atmosphere = { Density = 0.35, Offset = 0, Color = c3(60, 40, 110), Decay = c3(20, 15, 40), Glare = 0.4, Haze = 1.6 },
		bloom = { Intensity = 1.1, Size = 40, Threshold = 0.9 },
		colorCorrection = { Brightness = -0.02, Contrast = 0.25, Saturation = 0.35, TintColor = c3(225, 215, 255) },
		sunRays = { Intensity = 0, Spread = 1 },
		depthOfField = { Enabled = false },
	},
	dungeon_torchlit = {
		technology = "Future",
		description = "Enclosed dungeon or cave. Kill the sky, let PointLights on torches do the work, warm tint.",
		lighting = {
			ClockTime = 0,
			Brightness = 0.2,
			Ambient = c3(22, 18, 16),
			OutdoorAmbient = c3(18, 16, 20),
			ColorShift_Top = c3(0, 0, 0),
			ColorShift_Bottom = c3(0, 0, 0),
			EnvironmentDiffuseScale = 0.15,
			EnvironmentSpecularScale = 0.35,
			ExposureCompensation = 0.6,
			GlobalShadows = true,
			ShadowSoftness = 0.5,
			FogColor = c3(10, 8, 8),
			FogStart = 40,
			FogEnd = 320,
		},
		atmosphere = { Density = 0.5, Offset = 0, Color = c3(60, 40, 30), Decay = c3(20, 12, 10), Glare = 0, Haze = 1.2 },
		bloom = { Intensity = 0.7, Size = 32, Threshold = 1.1 },
		colorCorrection = { Brightness = -0.03, Contrast = 0.2, Saturation = -0.1, TintColor = c3(255, 225, 195) },
		sunRays = { Intensity = 0, Spread = 1 },
		depthOfField = { Enabled = true, FarIntensity = 0.25, FocusDistance = 40, InFocusRadius = 30, NearIntensity = 0.4 },
	},
	sunset = {
		technology = "Future",
		description = "Golden hour for hub worlds, campsites and story beats. Long shadows, warm bloom, visible sun rays.",
		lighting = {
			ClockTime = 17.6,
			Brightness = 2.0,
			Ambient = c3(90, 70, 80),
			OutdoorAmbient = c3(130, 100, 110),
			ColorShift_Top = c3(255, 170, 110),
			ColorShift_Bottom = c3(120, 80, 110),
			EnvironmentDiffuseScale = 0.5,
			EnvironmentSpecularScale = 0.7,
			ExposureCompensation = 0.25,
			GlobalShadows = true,
			ShadowSoftness = 0.4,
			FogColor = c3(230, 160, 120),
			FogStart = 300,
			FogEnd = 2200,
		},
		atmosphere = { Density = 0.38, Offset = 0.35, Color = c3(255, 175, 130), Decay = c3(150, 80, 90), Glare = 0.55, Haze = 1.9 },
		bloom = { Intensity = 0.6, Size = 36, Threshold = 1.2 },
		colorCorrection = { Brightness = 0.03, Contrast = 0.12, Saturation = 0.15, TintColor = c3(255, 235, 215) },
		sunRays = { Intensity = 0.22, Spread = 0.85 },
		depthOfField = { Enabled = false },
	},
}

-- Genre hints used by the skill to pick a preset without an explicit lighting instruction.
local GenreHints: { [string]: string } = {
	simulator = "bright_stylized",
	obby = "bright_stylized",
	tycoon = "bright_stylized",
	survival = "overcast",
	farming = "overcast",
	city = "night_neon",
	arcade = "night_neon",
	cyberpunk = "night_neon",
	dungeon = "dungeon_torchlit",
	cave = "dungeon_torchlit",
	horror = "dungeon_torchlit",
	hub = "sunset",
	campsite = "sunset",
	story = "sunset",
	arena = "sunset",
}

local function setProps(instance: Instance, props: { [string]: any })
	for name, value in props do
		local ok, err = pcall(function()
			(instance :: any)[name] = value
		end)
		if not ok then
			warn(("LightingPresets: could not set %s.%s (%s)"):format(instance.Name, name, tostring(err)))
		end
	end
end

local function ensureEffect(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst:SetAttribute("ForgeGUIPreset", true)
	inst.Parent = Lighting
	return inst
end

local M = {}
M.Presets = Presets
M.GenreHints = GenreHints

function M.list(): { string }
	local names = {}
	for name in Presets do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function M.forGenre(genre: string): string?
	return GenreHints[string.lower(genre)]
end

function M.apply(presetName: string)
	local preset = Presets[presetName]
	assert(preset, ("LightingPresets: unknown preset '%s'. Known: %s"):format(presetName, table.concat(M.list(), ", ")))

	setProps(Lighting, preset.lighting)
	Lighting:SetAttribute("ForgeGUIPreset", presetName)

	if preset.atmosphere then
		setProps(ensureEffect("Atmosphere", "ForgeGUI_Atmosphere"), preset.atmosphere)
	end
	if preset.bloom then
		setProps(ensureEffect("BloomEffect", "ForgeGUI_Bloom"), preset.bloom)
	end
	if preset.colorCorrection then
		setProps(ensureEffect("ColorCorrectionEffect", "ForgeGUI_ColorCorrection"), preset.colorCorrection)
	end
	if preset.sunRays then
		setProps(ensureEffect("SunRaysEffect", "ForgeGUI_SunRays"), preset.sunRays)
	end
	if preset.depthOfField then
		setProps(ensureEffect("DepthOfFieldEffect", "ForgeGUI_DepthOfField"), preset.depthOfField)
	end
	return presetName
end

-- Remove only what this module created; user-authored Lighting children are untouched.
function M.clear()
	for _, child in Lighting:GetChildren() do
		if child:GetAttribute("ForgeGUIPreset") == true then
			child:Destroy()
		end
	end
	Lighting:SetAttribute("ForgeGUIPreset", nil)
end

return M
