--!strict
-- Skybox presets. The Lighting, Atmosphere, Bloom and SunRays values were read out of supplied template
-- places (daytime, nighttime, cartoony) rather than invented; the six face images are generated — make one
-- 2:1 panorama, cut it with scripts/sky_faces.py, and pass the ids in.
--
-- Shares the ownership convention of LightingPresets.luau: effects this module creates are named
-- ForgeGUI_* and tagged with the attribute ForgeGUIPreset = true, existing ones it reuses are tagged
-- ForgeGUIPresetAdopted = true, and clear() removes only what it owns. Run LightingPresets.apply() first
-- and this second: the skybox preset's values are matched to the panorama and should win where the two
-- overlap (TimeOfDay, Brightness, Ambient, OutdoorAmbient, ShadowSoftness, the Environment*Scale pair,
-- GlobalShadows, and the Atmosphere / Bloom / SunRays effects).
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
	globalShadows: boolean,
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
		globalShadows = true,
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

local OWNED_ATTR = "ForgeGUIPreset"
local ADOPTED_ATTR = "ForgeGUIPresetAdopted"

-- Resolve an effect by ownership, never by name, so a template's own Atmosphere/Bloom/SunRays is
-- reconfigured in place instead of being shadowed by a second instance of the same class.
local function ensureEffect(Lighting: Instance, className: string, name: string): Instance
	local adopted: Instance? = nil
	local candidate: Instance? = nil
	for _, child in ipairs(Lighting:GetChildren()) do
		if child.ClassName == className then
			if child:GetAttribute(OWNED_ATTR) == true then
				return child
			elseif adopted == nil and child:GetAttribute(ADOPTED_ATTR) == true then
				adopted = child
			elseif candidate == nil then
				candidate = child
			end
		end
	end
	local existing = adopted or candidate
	if existing then
		existing:SetAttribute(ADOPTED_ATTR, true)
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst:SetAttribute(OWNED_ATTR, true)
	inst.Parent = Lighting
	return inst
end

-- What apply() replaces: every Sky under Lighting, the Lighting properties listed in the header, and the
-- first Atmosphere / BloomEffect / SunRaysEffect it finds (reconfigured in place, not duplicated). The Sky
-- sweep is deliberate and not optional: supplied template places were observed shipping two or three stacked
-- Sky instances, Roblox renders only one of them, and a new Sky parented alongside them may never be the one
-- shown. Everything else is left alone. clear() undoes only what this module created.
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
	sky.Name = "ForgeGUI_Sky"
	sky:SetAttribute(OWNED_ATTR, true)
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
	Lighting.GlobalShadows = preset.globalShadows

	local atmosphere = ensureEffect(Lighting, "Atmosphere", "ForgeGUI_Atmosphere") :: Atmosphere
	atmosphere.Density = preset.atmosphere.density
	atmosphere.Offset = preset.atmosphere.offset
	atmosphere.Color = preset.atmosphere.color
	atmosphere.Decay = preset.atmosphere.decay
	atmosphere.Glare = preset.atmosphere.glare
	atmosphere.Haze = preset.atmosphere.haze

	local bloom = ensureEffect(Lighting, "BloomEffect", "ForgeGUI_Bloom") :: BloomEffect
	bloom.Intensity = preset.bloom.intensity
	bloom.Size = preset.bloom.size
	bloom.Threshold = preset.bloom.threshold
	bloom.Enabled = true

	local rays = ensureEffect(Lighting, "SunRaysEffect", "ForgeGUI_SunRays") :: SunRaysEffect
	rays.Intensity = preset.sunRays.intensity
	rays.Enabled = true

	return sky
end

-- Remove only the instances this module created, decided by the ownership attribute and never by name.
-- Adopted effects keep their (now modified) values and lose only the adoption tag. Lighting properties are
-- not restored; re-apply a LightingPresets preset if you need those back.
function Presets.clear()
	local Lighting = game:GetService("Lighting")
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:GetAttribute(OWNED_ATTR) == true then
			child:Destroy()
		elseif child:GetAttribute(ADOPTED_ATTR) == true then
			child:SetAttribute(ADOPTED_ATTR, nil)
		end
	end
end

return Presets
