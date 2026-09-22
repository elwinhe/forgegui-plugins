--!strict
-- Skybox presets. The Lighting, Atmosphere, Bloom and SunRays values were read out of supplied template
-- places (daytime, nighttime, cartoony) rather than invented; the six face images are generated — make one
-- 2:1 panorama, prefer server asset_prepare (local scripts/sky_faces.py fallback), and pass the ids in.
--
-- Shares the ownership convention of LightingPresets.luau: effects this module creates are named
-- ForgeGUI_* and tagged with the attribute ForgeGUISkyboxPreset = true, existing ones it reuses are tagged
-- ForgeGUISkyboxPresetAdopted = true. The tag is deliberately distinct from the one LightingPresets uses,
-- so neither module's clear() removes the other's effects. Run LightingPresets.apply() first
-- and this second; clear in reverse order: the skybox preset's values are matched to the panorama and should win where the two
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

local OWNED_ATTR = "ForgeGUISkyboxPreset"
local ADOPTED_ATTR = "ForgeGUISkyboxPresetAdopted"

local PRIOR_PREFIX = "ForgeGUISkyboxPrior_"
local STORAGE_ATTR = "ForgeGUISkyboxStorage"
local FACE_KEYS = { "Ft", "Bk", "Lf", "Rt", "Up", "Dn" }

-- Persist the first baseline on each borrowed instance, independently of LightingPresets.
local function setProps(instance: Instance, props: { [string]: any })
	for property, value in props do
		local key = PRIOR_PREFIX .. property
		if instance:GetAttribute(OWNED_ATTR) ~= true and instance:GetAttribute(key) == nil then
			instance:SetAttribute(key, (instance :: any)[property])
		end
		(instance :: any)[property] = value
	end
end

local function restorePriors(instance: Instance)
	for key, value in instance:GetAttributes() do
		if string.sub(key, 1, #PRIOR_PREFIX) == PRIOR_PREFIX then
			(instance :: any)[string.sub(key, #PRIOR_PREFIX + 1)] = value
			instance:SetAttribute(key, nil)
		end
	end
end

-- Storage is found by tag, never by name, and survives module reloads/place saves.
local function skyStorage(): Instance
	local storage = game:GetService("ServerStorage")
	for _, child in storage:GetChildren() do
		if child:IsA("Folder") and child:GetAttribute(STORAGE_ATTR) == true then
			return child
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = "ForgeGUI_OriginalSkies"
	folder:SetAttribute(STORAGE_ATTR, true)
	folder.Parent = storage
	return folder
end

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

-- Validate the entire request before touching the scene. IDs must be exactly representable
-- positive integers; invalid faces (including NaN/infinity) cannot partially replace a sky.
function Presets.apply(name: string, faces: Faces): Sky
	local preset = Presets.byName[name]
	assert(preset, "unknown skybox preset: " .. tostring(name))
	assert(type(faces) == "table", "skybox faces must be a table")
	local textures: { [string]: string } = {}
	for _, face in FACE_KEYS do
		local id = (faces :: any)[face]
		assert(type(id) == "number" and id > 0 and id <= 9007199254740991 and id % 1 == 0,
			"invalid skybox face ID: " .. face)
		textures[face] = "rbxassetid://" .. string.format("%.0f", id)
	end
	local Lighting = game:GetService("Lighting")

	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Sky") then
			if child:GetAttribute(OWNED_ATTR) == true then
				child:Destroy()
			else
				child.Parent = skyStorage()
			end
		end
	end

	local sky = Instance.new("Sky")
	sky.Name = "ForgeGUI_Sky"
	sky:SetAttribute(OWNED_ATTR, true)
	for _, face in FACE_KEYS do
		(sky :: any)["Skybox" .. face] = textures[face]
	end
	sky.CelestialBodiesShown = preset.celestialBodiesShown
	sky.StarCount = preset.starCount
	sky.SunAngularSize = preset.sunAngularSize
	sky.MoonAngularSize = preset.moonAngularSize
	sky.Parent = Lighting

	setProps(Lighting, {
		TimeOfDay = preset.timeOfDay,
		Brightness = preset.brightness,
		Ambient = preset.ambient,
		OutdoorAmbient = preset.outdoorAmbient,
		ShadowSoftness = preset.shadowSoftness,
		EnvironmentDiffuseScale = preset.environmentDiffuseScale,
		EnvironmentSpecularScale = preset.environmentSpecularScale,
		GlobalShadows = preset.globalShadows,
	})

	local atmosphere = ensureEffect(Lighting, "Atmosphere", "ForgeGUI_Atmosphere")
	setProps(atmosphere, {
		Density = preset.atmosphere.density, Offset = preset.atmosphere.offset,
		Color = preset.atmosphere.color, Decay = preset.atmosphere.decay,
		Glare = preset.atmosphere.glare, Haze = preset.atmosphere.haze,
	})
	local bloom = ensureEffect(Lighting, "BloomEffect", "ForgeGUI_Bloom")
	setProps(bloom, {
		Intensity = preset.bloom.intensity, Size = preset.bloom.size,
		Threshold = preset.bloom.threshold, Enabled = true,
	})
	local rays = ensureEffect(Lighting, "SunRaysEffect", "ForgeGUI_SunRays")
	setProps(rays, { Intensity = preset.sunRays.intensity, Enabled = true })

	return sky
end

-- Clear skybox before LightingPresets so overlapping baselines unwind in reverse order.
-- No module-local state: a fresh module/session can restore the same instances and values.
function Presets.clear()
	local Lighting = game:GetService("Lighting")
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:GetAttribute(OWNED_ATTR) == true then
			child:Destroy()
		elseif child:GetAttribute(ADOPTED_ATTR) == true then
			restorePriors(child)
			child:SetAttribute(ADOPTED_ATTR, nil)
		end
	end
	restorePriors(Lighting)
	for _, folder in game:GetService("ServerStorage"):GetChildren() do
		if folder:IsA("Folder") and folder:GetAttribute(STORAGE_ATTR) == true then
			for _, child in folder:GetChildren() do
				if child:IsA("Sky") then
					child.Parent = Lighting
				end
			end
			-- Do not delete unrelated content someone added while the preset was active.
			if #folder:GetChildren() == 0 then
				folder:Destroy()
			end
		end
	end
end

return Presets
