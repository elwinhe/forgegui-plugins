--!strict
-- LightingPresets: named, reviewed Lighting + post-processing configurations.
-- Ship as a ModuleScript (ReplicatedStorage.LightingPresets) or paste the body into
-- execute_luau / the command bar and call `apply("sunset")`.
--
-- Idempotent: post-processing instances are created once and tagged with the
-- attribute ForgeGUIPreset = true; later applies reconfigure them instead of stacking.
-- Ownership: the module only ever destroys instances carrying ForgeGUIPreset = true.
-- A name match alone is never treated as ownership. Existing effects it reuses are
-- tagged ForgeGUIPresetAdopted = true and explicitly enabled when a preset needs them.
-- Nothing here downloads code or inserts assets.
-- Lighting.Technology is NOT scriptable (Studio Properties panel only); presets record a
-- recommended technology in `technology` for the agent to report, never to set.
--
-- Reversible: every property this module overwrites is recorded first, as a
-- ForgeGUIPrior_<Property> attribute on the instance that owns it, so `clear()`
-- puts a borrowed place back the way it was found. Applying a look to someone
-- else's place must not be a one-way door. Priors are written once, at the first
-- apply, so a second preset never overwrites the original values.
--
-- Two dials sit on top of the presets, because they are the two settings a real
-- scene most often needs moved, and the two people most often edit a preset to
-- reach: `glow` (bloom) and `haze` (atmosphere). Both are multipliers, so the
-- preset stays the single source of the look.

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
	-- Effect fields switched off by `apply(name, { reduced = true })`, cheapest loss
	-- of look first. Never lists `atmosphere`: it has no Enabled property, and its
	-- haze is usually load-bearing for the look rather than decoration.
	reduced: { string }?,
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
		reduced = { "sunRays" },
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
		reduced = { "sunRays" },
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
		-- A Threshold under 1 blooms nearly every lit surface. It is deliberate here
		-- only because the ambient is near-black and the emissives are meant to carry
		-- the scene. In a place with ordinary lit walls, pass glow < 1, which raises
		-- the threshold as well as lowering intensity.
		bloom = { Intensity = 1.1, Size = 40, Threshold = 0.9 },
		colorCorrection = { Brightness = -0.02, Contrast = 0.25, Saturation = 0.35, TintColor = c3(225, 215, 255) },
		sunRays = { Intensity = 0, Spread = 1 },
		depthOfField = { Enabled = false },
		reduced = { "sunRays" },
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
		reduced = { "depthOfField", "sunRays" },
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
		reduced = { "sunRays" },
	},
	-- Menus, shops and item showcases are lit for legibility, not for mood: no fog,
	-- no rays, no depth of field, and the atmosphere neutralised rather than left
	-- alone, because a place that already carries one would otherwise haze the item.
	studio_showcase = {
		technology = "ShadowMap",
		description = "Even, shadowless light for menus, shops, item showcases and thumbnails. No fog, no haze, no rays.",
		lighting = {
			ClockTime = 14,
			Brightness = 2,
			Ambient = c3(140, 140, 148),
			OutdoorAmbient = c3(160, 160, 168),
			ColorShift_Top = c3(255, 255, 255),
			ColorShift_Bottom = c3(235, 235, 240),
			EnvironmentDiffuseScale = 1,
			EnvironmentSpecularScale = 0.5,
			ExposureCompensation = 0,
			GlobalShadows = true,
			ShadowSoftness = 1,
			FogStart = 0,
			FogEnd = 100000,
		},
		atmosphere = { Density = 0, Offset = 0, Glare = 0, Haze = 0 },
		bloom = { Intensity = 0.25, Size = 28, Threshold = 1.6 },
		colorCorrection = { Brightness = 0.01, Contrast = 0.08, Saturation = 0.1, TintColor = c3(255, 255, 255) },
		sunRays = { Intensity = 0, Spread = 1 },
		depthOfField = { Enabled = false },
		reduced = {},
	},
}

-- Genre hints used by the skill to pick a preset without an explicit lighting instruction.
local GenreHints: { [string]: string } = {
	simulator = "bright_stylized",
	obby = "bright_stylized",
	tycoon = "bright_stylized",
	roleplay = "bright_stylized",
	survival = "overcast",
	farming = "overcast",
	city = "night_neon",
	arcade = "night_neon",
	cyberpunk = "night_neon",
	racing = "night_neon",
	shooter = "night_neon",
	scifi = "night_neon",
	dungeon = "dungeon_torchlit",
	cave = "dungeon_torchlit",
	horror = "dungeon_torchlit",
	hub = "sunset",
	campsite = "sunset",
	story = "sunset",
	arena = "sunset",
	adventure = "sunset",
	menu = "studio_showcase",
	shop = "studio_showcase",
	showcase = "studio_showcase",
	thumbnail = "studio_showcase",
}

local OWNED_ATTR = "ForgeGUIPreset"
local ADOPTED_ATTR = "ForgeGUIPresetAdopted"
local PRIOR_PREFIX = "ForgeGUIPrior_"

-- Post-processing classes in apply order. `hasEnabled` is false for Atmosphere,
-- which has no Enabled property; setting one warns and is skipped.
local EFFECTS = {
	{ field = "atmosphere", className = "Atmosphere", name = "ForgeGUI_Atmosphere", hasEnabled = false },
	{ field = "bloom", className = "BloomEffect", name = "ForgeGUI_Bloom", hasEnabled = true },
	{ field = "colorCorrection", className = "ColorCorrectionEffect", name = "ForgeGUI_ColorCorrection", hasEnabled = true },
	{ field = "sunRays", className = "SunRaysEffect", name = "ForgeGUI_SunRays", hasEnabled = true },
	{ field = "depthOfField", className = "DepthOfFieldEffect", name = "ForgeGUI_DepthOfField", hasEnabled = true },
}

local function isOwned(inst: Instance): boolean
	return inst:GetAttribute(OWNED_ATTR) == true
end

-- Prior values travel as attributes on the instance that owns the property, so a
-- revert works from a later session, another script or the command bar, with no
-- state held in this module. An EnumItem is stored as its name, which assigns back
-- cleanly and is a supported attribute type everywhere.
local function storable(value: any): any
	if typeof(value) == "EnumItem" then
		return value.Name
	end
	return value
end

local function rememberPrior(instance: Instance, property: string)
	local key = PRIOR_PREFIX .. property
	if instance:GetAttribute(key) ~= nil then
		return -- the first apply wins; a second preset must not overwrite the real prior
	end
	local ok, value = pcall(function()
		local current = (instance :: any)[property]
		local output = instance:GetAttribute("ForgeGUILightingOutput_" .. property)
		local base = instance:GetAttribute("ForgeGUILightingBase_" .. property)
		local input = instance:GetAttribute("ForgeGUILightingInput_" .. property)
		if input ~= nil and current == input then return current end
		return if output ~= nil and current == output and base ~= nil then base else current
	end)
	if not ok or value == nil or typeof(value) == "Instance" then
		return
	end
	pcall(function()
		instance:SetAttribute(key, storable(value))
	end)
end

-- Mark explicit preset inputs even when they equal the compositor's visible output.
local function markBaseInput(instance: Instance, property: string)
	if instance == Lighting and instance:GetAttribute("ForgeGUILightingOutput_" .. property) ~= nil then
		instance:SetAttribute("ForgeGUILightingInput_" .. property, (instance :: any)[property])
	end
end

local function restorePriors(instance: Instance)
	for key, value in instance:GetAttributes() do
		if string.sub(key, 1, #PRIOR_PREFIX) == PRIOR_PREFIX then
			local property = string.sub(key, #PRIOR_PREFIX + 1)
			pcall(function()
				(instance :: any)[property] = value
				markBaseInput(instance, property)
			end)
			instance:SetAttribute(key, nil)
		end
	end
end

-- `remember` is set for anything this module did not create: Lighting itself, and
-- adopted effects. Instances it created are destroyed by clear(), so their prior
-- values are the defaults they were born with.
local function setProps(instance: Instance, props: { [string]: any }, remember: boolean, failed: { string })
	for name, value in props do
		if remember then
			rememberPrior(instance, name)
		end
		local ok, err = pcall(function()
			(instance :: any)[name] = value
			markBaseInput(instance, name)
		end)
		if not ok then
			table.insert(failed, `{instance.ClassName}.{name}`)
			warn(("LightingPresets: could not set %s.%s (%s)"):format(instance.Name, name, tostring(err)))
		end
	end
end

-- Post effects stack: a second Atmosphere/Bloom/ColorCorrection next to the template's own
-- doubles the effect. Resolution order, by ownership rather than by name:
--   1. an instance of this class that this module created (ForgeGUIPreset = true);
--   2. an instance of this class this module adopted on an earlier apply (ForgeGUIPresetAdopted);
--   3. the first existing instance of this class, which becomes adopted;
--   4. otherwise create one.
-- An instance that merely shares our name is never destroyed; it is adopted only if its class is
-- one the preset configures, and otherwise ignored.
local function findEffect(className: string): Instance?
	local adopted: Instance? = nil
	local candidate: Instance? = nil
	for _, child in Lighting:GetChildren() do
		if child.ClassName ~= className then
			continue
		end
		if isOwned(child) then
			return child
		end
		if adopted == nil and child:GetAttribute(ADOPTED_ATTR) == true then
			adopted = child
		elseif candidate == nil then
			candidate = child
		end
	end
	return adopted or candidate
end

-- Returns the instance and whether this module created it. A class the client does
-- not know (an older engine) returns nil rather than erroring the whole apply.
local function ensureEffect(className: string, name: string): (Instance?, boolean)
	local existing = findEffect(className)
	if existing then
		if isOwned(existing) then
			return existing, true
		end
		existing:SetAttribute(ADOPTED_ATTR, true)
		return existing, false
	end
	local ok, created = pcall(function()
		local inst = Instance.new(className)
		inst.Name = name
		inst:SetAttribute(OWNED_ATTR, true)
		inst.Parent = Lighting
		return inst
	end)
	if not ok then
		return nil, false
	end
	return created, true
end

local function multiplier(options: { [string]: any }?, key: string): number
	local value = if options then options[key] else nil
	if type(value) ~= "number" or value ~= value then
		return 1
	end
	return math.clamp(value, 0, 3)
end

-- Glow is the property most often wrong in a Roblox scene and the one people most
-- want to dial without editing a preset. The multiplier scales bloom intensity and
-- moves the threshold the other way, so turning glow down makes fewer pixels bloom
-- as well as blooming them less.
local function scaleGlow(spec: { [string]: any }, glow: number): { [string]: any }
	if glow == 1 then
		return spec
	end
	local scaled = table.clone(spec)
	if type(scaled.Intensity) == "number" then
		scaled.Intensity = math.max(0, scaled.Intensity * glow)
	end
	if type(scaled.Threshold) == "number" and glow > 0 then
		scaled.Threshold = math.clamp(scaled.Threshold / math.max(glow, 0.25), 0.5, 4)
	end
	return scaled
end

-- Haze is the other dial a place most often needs. A preset tuned at ground level
-- reads well at 50 studs and swallows anything at 200, which is where skylines and
-- floating islands live. The multiplier scales Atmosphere density and haze together.
local function scaleHaze(spec: { [string]: any }, haze: number): { [string]: any }
	if haze == 1 then
		return spec
	end
	local scaled = table.clone(spec)
	if type(scaled.Density) == "number" then
		scaled.Density = math.clamp(scaled.Density * haze, 0, 1)
	end
	if type(scaled.Haze) == "number" then
		scaled.Haze = math.clamp(scaled.Haze * haze, 0, 10)
	end
	return scaled
end

export type ApplyOptions = {
	glow: number?, -- bloom multiplier, 0 to 3 (1 = the preset as tuned)
	haze: number?, -- atmosphere multiplier, 0 to 3
	reduced: boolean?, -- switch the preset's `reduced` effects off, for low-end targets
}

export type Report = {
	preset: string,
	technology: string, -- report this; the module cannot set Lighting.Technology
	glow: number,
	haze: number,
	disabled: { string }, -- effect classes switched off by `reduced`
	failed: { string }, -- "Class.Property" entries the engine refused
}

local M = {}
M.Presets = Presets
M.GenreHints = GenreHints
M.EFFECTS = EFFECTS

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

-- The same lookup from a free-text brief ("a neon racing game"), for picking a
-- preset out of the request itself. An exact preset name wins over a genre word.
function M.forText(text: string): string?
	if type(text) ~= "string" then
		return nil
	end
	local key = (string.gsub(string.lower(text), "%-+", "_"))
	if Presets[key] then
		return key
	end
	local spaced = (string.gsub(key, "_", " "))
	for phrase, preset in GenreHints do
		if string.find(spaced, phrase, 1, true) then
			return preset
		end
	end
	return nil
end

-- Returns the preset name (so `print(apply("sunset"))` still reads well) and a
-- report of what was dialled, switched off and refused.
function M.apply(presetName: string, options: ApplyOptions?): (string, Report)
	local preset = Presets[presetName]
	assert(preset, ("LightingPresets: unknown preset '%s'. Known: %s"):format(presetName, table.concat(M.list(), ", ")))

	local glow = multiplier(options :: any, "glow")
	local haze = multiplier(options :: any, "haze")
	local reduced = options ~= nil and options.reduced == true
	local failed: { string } = {}
	local disabled: { string } = {}

	local skip: { [string]: boolean } = {}
	if reduced then
		for _, field in preset.reduced or {} do
			skip[field] = true
		end
	end

	setProps(Lighting, preset.lighting, true, failed)
	Lighting:SetAttribute(OWNED_ATTR, presetName)

	for _, entry in EFFECTS do
		local spec = (preset :: any)[entry.field]
		if spec then
			if skip[entry.field] then
				-- Off costs less than configured-and-on, but only an instance that is
				-- already there is worth touching: creating one to disable it saves
				-- nothing and leaves a stranger in the place.
				local existing = findEffect(entry.className)
				if existing and entry.hasEnabled then
					local borrowed = not isOwned(existing)
					if borrowed then
						existing:SetAttribute(ADOPTED_ATTR, true)
					end
					setProps(existing, { Enabled = false }, borrowed, failed)
					table.insert(disabled, entry.className)
				end
			else
				local instance, owned = ensureEffect(entry.className, entry.name)
				if instance then
					local resolved = spec
					if entry.className == "BloomEffect" then
						resolved = scaleGlow(resolved, glow)
					elseif entry.className == "Atmosphere" then
						resolved = scaleHaze(resolved, haze)
					end
					-- Presets are written for an effect that is on. An adopted instance may
					-- have been left disabled by the template or the user (the Baseplate
					-- ships DepthOfField off), so enable it explicitly unless the preset
					-- says otherwise.
					if entry.hasEnabled and resolved.Enabled == nil then
						resolved = table.clone(resolved)
						resolved.Enabled = true
					end
					setProps(instance, resolved, not owned, failed)
				else
					table.insert(failed, `{entry.className}.new`)
				end
			end
		end
	end

	return presetName,
		{
			preset = presetName,
			technology = preset.technology,
			glow = glow,
			haze = haze,
			disabled = disabled,
			failed = failed,
		}
end

-- Removes only what this module created, decided by the ownership attribute and never
-- by name, and hands every borrowed instance back with the values it had. Adopted
-- effects keep their class and parent; only the properties a preset overwrote are
-- restored, including the Enabled state it changed.
-- Returns false when no preset is applied.
function M.clear(): boolean
	if Lighting:GetAttribute(OWNED_ATTR) == nil then
		return false
	end
	for _, child in Lighting:GetChildren() do
		if isOwned(child) then
			child:Destroy()
		elseif child:GetAttribute(ADOPTED_ATTR) == true then
			restorePriors(child)
			child:SetAttribute(ADOPTED_ATTR, nil)
		end
	end
	restorePriors(Lighting)
	Lighting:SetAttribute(OWNED_ATTR, nil)
	return true
end

-- The preset currently applied, read from the place itself rather than module state.
function M.current(): string?
	local name = Lighting:GetAttribute(OWNED_ATTR)
	return if type(name) == "string" then name else nil
end

return M
