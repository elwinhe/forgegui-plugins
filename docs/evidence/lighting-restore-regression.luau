-- Appended to the reviewed LightingPresets source in place of its final `return M`.
-- Run the generated standalone regression through Studio MCP in an owned test place.
--
-- Covers the behaviour added when the Looks/PostFX work was folded into this module:
-- prior-value capture, restore on clear(), the glow and haze dials, and reduced mode.
-- Ownership itself (adopt, never duplicate; never destroy by name) is re-checked here
-- too, because the restore path is what would most easily break it.
--
-- The place is left as it was found: the script records Lighting's own values first and
-- restores them at the end, whether it passed or failed.
local Presets = M
local Lighting = game:GetService("Lighting")
local checks = {}

local function check(condition: boolean, label: string)
	assert(condition, label)
	table.insert(checks, label)
end

local function near(actual: any, expected: number, label: string)
	check(
		type(actual) == "number" and math.abs(actual - expected) < 1e-4,
		`{label} (expected {expected}, got {tostring(actual)})`
	)
end

local function childOfClass(className: string): Instance?
	for _, child in Lighting:GetChildren() do
		if child.ClassName == className then
			return child
		end
	end
	return nil
end

-- Whatever the place already had, so the regression can hand it back.
local WATCHED = { "Brightness", "ClockTime", "ExposureCompensation", "FogEnd", "FogStart", "GlobalShadows" }
local placeValues: { [string]: any } = {}
for _, property in WATCHED do
	placeValues[property] = (Lighting :: any)[property]
end
check(Lighting:GetAttribute("ForgeGUIPreset") == nil, "the test place has no preset applied yet")

local ok, failure = xpcall(function()
	-- A stranger of another class that merely shares an owned name must survive untouched.
	local impostor = Instance.new("Folder")
	impostor.Name = "ForgeGUI_Bloom"
	impostor.Parent = Lighting

	-- Stand in for the template's own effects: one adopted Atmosphere with a known
	-- density, and one DepthOfField left disabled the way the Baseplate ships it.
	local existingAtmosphere = childOfClass("Atmosphere")
	local createdAtmosphere = existingAtmosphere == nil
	if createdAtmosphere then
		local made = Instance.new("Atmosphere")
		made.Name = "Atmosphere"
		made.Parent = Lighting
		existingAtmosphere = made
	end
	local atmosphere = existingAtmosphere :: Atmosphere
	local atmospherePrior = atmosphere.Density
	atmosphere.Density = 0.12

	local existingDof = childOfClass("DepthOfFieldEffect")
	local createdDof = existingDof == nil
	if createdDof then
		local made = Instance.new("DepthOfFieldEffect")
		made.Name = "DepthOfField"
		made.Parent = Lighting
		existingDof = made
	end
	local dof = existingDof :: DepthOfFieldEffect
	local dofPrior = dof.Enabled
	dof.Enabled = false

	Lighting.Brightness = 1.75

	-- 1. Apply adopts rather than duplicates, and records what it overwrote.
	local name, report = Presets.apply("dungeon_torchlit")
	check(name == "dungeon_torchlit", "apply returns the preset name")
	check(report.technology == "Future", "the report carries the recommended technology")
	check(#report.failed == 0, `no property was refused (got {table.concat(report.failed, ", ")})`)

	local atmosphereCount, dofCount = 0, 0
	for _, child in Lighting:GetChildren() do
		if child.ClassName == "Atmosphere" then
			atmosphereCount += 1
		elseif child.ClassName == "DepthOfFieldEffect" then
			dofCount += 1
		end
	end
	check(atmosphereCount == 1, "the existing Atmosphere was adopted, not duplicated")
	check(dofCount == 1, "the existing DepthOfField was adopted, not duplicated")
	check(dof.Enabled == true, "an adopted effect the preset needs was switched on")
	check(atmosphere:GetAttribute("ForgeGUIPresetAdopted") == true, "adopted effects are tagged")
	near(atmosphere:GetAttribute("ForgeGUIPrior_Density"), 0.12, "the adopted prior density was recorded")
	check(dof:GetAttribute("ForgeGUIPrior_Enabled") == false, "the adopted prior Enabled was recorded")
	near(Lighting:GetAttribute("ForgeGUIPrior_Brightness"), 1.75, "the prior Lighting brightness was recorded")
	check(Presets.current() == "dungeon_torchlit", "the applied preset reads back from the place")

	-- 2. A second preset must not overwrite the first priors.
	Presets.apply("sunset")
	near(Lighting:GetAttribute("ForgeGUIPrior_Brightness"), 1.75, "the first prior survives a second apply")

	-- 3. The dials move the effect they name, and nothing else.
	Presets.apply("night_neon", { glow = 0.5 })
	local bloom = childOfClass("BloomEffect") :: BloomEffect
	near(bloom.Intensity, 0.55, "glow 0.5 halves bloom intensity")
	near(bloom.Threshold, 1.8, "glow 0.5 raises the bloom threshold")

	Presets.apply("overcast", { haze = 0.5 })
	near(atmosphere.Density, 0.225, "haze 0.5 halves atmosphere density")
	near(atmosphere.Haze, 1.1, "haze 0.5 halves atmosphere haze")

	-- 4. Reduced switches off what is there and creates nothing new.
	local sunRaysBefore = childOfClass("SunRaysEffect")
	local _, reduced = Presets.apply("dungeon_torchlit", { reduced = true })
	check(dof.Enabled == false, "reduced switched off the depth of field")
	check(table.find(reduced.disabled, "DepthOfFieldEffect") ~= nil, "the report lists what was switched off")
	if not sunRaysBefore then
		check(childOfClass("SunRaysEffect") == nil, "reduced never creates an effect just to disable it")
	end

	-- 5. clear() hands the place back.
	check(Presets.clear() == true, "clear reports it had something to do")
	near(Lighting.Brightness, 1.75, "Lighting brightness is restored")
	near(atmosphere.Density, 0.12, "the adopted atmosphere is restored")
	check(dof.Enabled == false, "the adopted depth of field keeps the Enabled state it was found with")
	check(atmosphere:GetAttribute("ForgeGUIPresetAdopted") == nil, "the adoption tag is removed")
	check(atmosphere:GetAttribute("ForgeGUIPrior_Density") == nil, "restored priors are cleaned up")
	check(childOfClass("BloomEffect") == nil, "the bloom this module created was destroyed")
	check(Lighting:GetAttribute("ForgeGUIPreset") == nil, "the place no longer claims a preset")
	check(Presets.clear() == false, "clear on a clean place reports nothing to do")
	check(impostor.Parent == Lighting, "a same-named stranger of another class survives")

	-- Put the borrowed instances back exactly as they were.
	impostor:Destroy()
	if createdAtmosphere then
		atmosphere:Destroy()
	else
		atmosphere.Density = atmospherePrior
	end
	if createdDof then
		dof:Destroy()
	else
		dof.Enabled = dofPrior
	end
end, debug.traceback)

for _, property in WATCHED do
	pcall(function()
		(Lighting :: any)[property] = placeValues[property]
	end)
end

if not ok then
	error(`lighting restore regression failed after {#checks} checks:\n{failure}`)
end
print(`lighting restore regression: {#checks} checks passed`)
for _, label in checks do
	print("  ok", label)
end
