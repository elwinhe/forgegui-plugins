--!strict
-- Skybox presets read from the client's template places (daytime.rbxl, nighttime.rbxl, cartoonyskybox.rbxl,
-- received 19 Sep 2026). Values are theirs; the six faces are yours — generate one 2:1 panorama, cut it with
-- scripts/sky_faces.py, and pass the ids in.
--
-- 	local Presets = require(path.to.SkyboxPresets)
-- 	Presets.apply("daytime", { Ft = 123, Bk = 124, Lf = 125, Rt = 126, Up = 127, Dn = 128 })

export type Faces = { Ft: number, Bk: number, Lf: number, Rt: number, Up: number, Dn: number }

export type Preset = {
	timeOfDay: string,
	brightness: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	shadowSoftness: number,
	environmentDiffuseScale: number,
	environmentSpecularScale: number,
	celestialBodiesShown: boolean,
	starCount: number,
	sunAngularSize: number,
	moonAngularSize: number,
	atmosphere: { density: number, offset: number, color: Color3, decay: Color3, glare: number, haze: number },
	bloom: { intensity: number, size: number, threshold: number },
	sunRays: { intensity: number },
}

local GREY = Color3.fromRGB(70, 70, 70)
local ATMO_COLOR = Color3.fromRGB(199, 199, 199)
local ATMO_DECAY = Color3.fromRGB(106, 112, 125)

local function base(): Preset
	return {
		timeOfDay = "14:30:00",
		brightness = 3,
		ambient = GREY,
		outdoorAmbient = GREY,
		shadowSoftness = 0.2,
		environmentDiffuseScale = 1,
		environmentSpecularScale = 1,
		celestialBodiesShown = true,
		starCount = 3000,
		sunAngularSize = 21,
		moonAngularSize = 11,
		atmosphere = { density = 0.44, offset = 0.25, color = ATMO_COLOR, decay = ATMO_DECAY, glare = 0, haze = 0 },
		bloom = { intensity = 1, size = 24, threshold = 2 },
		sunRays = { intensity = 0.01 },
	}
end

local Presets = {}


Presets.list = { "daytime", "nighttime", "cartoony" }

local daytime = base()

local nighttime = base()
nighttime.timeOfDay = "01:54:00"
nighttime.brightness = 4
nighttime.atmosphere.density = 0.6
nighttime.atmosphere.offset = 0

local cartoony = base()
cartoony.atmosphere.density = 0.4

local byName: { [string]: Preset } = {
	daytime = daytime,
	nighttime = nighttime,
	cartoony = cartoony,
}
Presets.byName = byName

-- Their template places ship two or three stacked Sky instances (daytime 2, cartoony 3 including a leftover
-- "__WORLDFX"). Roblox renders one of them, so always clear the old ones first — this is what apply() does.
function Presets.apply(name: string, faces: Faces): Sky
	local preset = Presets.byName[name]
	assert(preset, "unknown skybox preset: " .. tostring(name))
	local Lighting = game:GetService("Lighting")

	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Sky") then
			child:Destroy()
		end
	end

	local sky = Instance.new("Sky")
	sky.Name = "GeneratedSky"
	sky.SkyboxFt = "rbxassetid://" .. tostring(faces.Ft)
	sky.SkyboxBk = "rbxassetid://" .. tostring(faces.Bk)
	sky.SkyboxLf = "rbxassetid://" .. tostring(faces.Lf)
	sky.SkyboxRt = "rbxassetid://" .. tostring(faces.Rt)
	sky.SkyboxUp = "rbxassetid://" .. tostring(faces.Up)
	sky.SkyboxDn = "rbxassetid://" .. tostring(faces.Dn)
	sky.CelestialBodiesShown = preset.celestialBodiesShown
	sky.StarCount = preset.starCount
	sky.SunAngularSize = preset.sunAngularSize
	sky.MoonAngularSize = preset.moonAngularSize
	sky.Parent = Lighting

	Lighting.TimeOfDay = preset.timeOfDay
	Lighting.Brightness = preset.brightness
	Lighting.Ambient = preset.ambient
	Lighting.OutdoorAmbient = preset.outdoorAmbient
	Lighting.ShadowSoftness = preset.shadowSoftness
	Lighting.EnvironmentDiffuseScale = preset.environmentDiffuseScale
	Lighting.EnvironmentSpecularScale = preset.environmentSpecularScale
	Lighting.GlobalShadows = true

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = preset.atmosphere.density
	atmosphere.Offset = preset.atmosphere.offset
	atmosphere.Color = preset.atmosphere.color
	atmosphere.Decay = preset.atmosphere.decay
	atmosphere.Glare = preset.atmosphere.glare
	atmosphere.Haze = preset.atmosphere.haze
	atmosphere.Parent = Lighting

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = preset.bloom.intensity
	bloom.Size = preset.bloom.size
	bloom.Threshold = preset.bloom.threshold
	bloom.Enabled = true
	bloom.Parent = Lighting

	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect") or Instance.new("SunRaysEffect")
	rays.Intensity = preset.sunRays.intensity
	rays.Enabled = true
	rays.Parent = Lighting

	return sky
end

return Presets
