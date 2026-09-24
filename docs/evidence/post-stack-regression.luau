-- Regression for the camera + post-processing stack (references/post-processing.md).
-- Install the shipped modules as ModuleScripts under ReplicatedStorage.ForgeGUIPostStack
-- (CameraFx, FrameSmoothing, ColourGrade, EyeAdaptation, GraphicsPreset, LutGrades and,
-- optionally, LightingPresets), then paste this whole file into execute_luau in an owned
-- test place (Edit, or a Play client; not the server). `require` from execute_luau
-- returns fresh module instances, which is what this wants: it drives each module's
-- public `step` directly instead of waiting for render frames.
--
-- Covers: ownership (adopt, never duplicate, destroy only the owned tag), prior-value
-- attributes and their clean-up, following an external writer instead of fighting it,
-- restore on stop, idempotent start/stop, the stale-session sweep, composition with
-- LightingPresets, and the maths each module's header claims (Unreal smear, frame-blend
-- counts, 18/40 ms half-lives, the 0.55 "Natural" share, keyframe wrap past midnight,
-- metering clamps, 18/26 ms picks).
--
-- The place is left as it was found: Lighting and camera values are recorded first and
-- put back at the end, whether the run passed or failed. Prints PASS or FAIL.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local root = ReplicatedStorage:FindFirstChild("ForgeGUIPostStack")
assert(root, "install the modules under ReplicatedStorage.ForgeGUIPostStack first")
local function loadModule(name: string): any
	local module = root:FindFirstChild(name)
	return if module and module:IsA("ModuleScript") then require(module) :: any else nil
end
local CameraFx = assert(loadModule("CameraFx"), "CameraFx missing")
local FrameSmoothing = assert(loadModule("FrameSmoothing"), "FrameSmoothing missing")
local ColourGrade = assert(loadModule("ColourGrade"), "ColourGrade missing")
local EyeAdaptation = assert(loadModule("EyeAdaptation"), "EyeAdaptation missing")
local GraphicsPreset = assert(loadModule("GraphicsPreset"), "GraphicsPreset missing")
local LutGrades = loadModule("LutGrades")
local LightingPresets = loadModule("LightingPresets")

local camera = Workspace.CurrentCamera :: Camera
local checks: { string } = {}

local function check(condition: boolean, label: string)
	assert(condition, label)
	table.insert(checks, label)
end

local function near(actual: any, expected: number, label: string, tolerance: number?)
	check(
		type(actual) == "number" and math.abs(actual - expected) <= (tolerance or 1e-3),
		`{label} (expected {expected}, got {tostring(actual)})`
	)
end

local function sameColour(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 1e-3 and math.abs(a.G - b.G) < 1e-3 and math.abs(a.B - b.B) < 1e-3
end

local function times(a: Color3, b: Color3): Color3
	return Color3.new(math.min(a.R * b.R, 1), math.min(a.G * b.G, 1), math.min(a.B * b.B, 1))
end

local function countOf(className: string): number
	local n = 0
	for _, parent in { Lighting :: Instance, camera :: Instance } do
		for _, child in parent:GetChildren() do
			if child.ClassName == className then
				n += 1
			end
		end
	end
	return n
end

local function hasPrefix(instance: Instance, prefix: string): boolean
	for key in instance:GetAttributes() do
		if string.sub(key, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

-- What the place had, so the run can hand it back.
local WATCHED = { "Ambient", "OutdoorAmbient", "ColorShift_Top", "ExposureCompensation", "ClockTime" }
local placeValues: { [string]: any } = {}
for _, property in WATCHED do
	placeValues[property] = (Lighting :: any)[property]
end
local cameraType, cameraCFrame, cameraFocus = camera.CameraType, camera.CFrame, camera.Focus
local parked: { { effect: Instance, parent: Instance } } = {} -- place DoFs lifted out for a test

local function parkPlaceDofs(keep: Instance?)
	for _, parent in { Lighting :: Instance, camera :: Instance } do
		for _, child in parent:GetChildren() do
			if child:IsA("DepthOfFieldEffect") and child ~= keep then
				table.insert(parked, { effect = child, parent = parent })
				child.Parent = nil
			end
		end
	end
end

-- CameraFx ------------------------------------------------------------------------------

local function testCameraFxMaths()
	near(CameraFx.intensityFor(0, 0.5, 1.6), 0, "no screen speed, no smear")
	near(CameraFx.intensityFor(1000, 0.5, 1.6), 0.9, "the smear caps at 5 % of the screen (intensity 0.9)")
	near(CameraFx.intensityFor(1.2, 0.5, 1.6), 0.9 * (0.5 * 1.2 / (30 * 1.6)) / 0.05, "smear = amount * speed / (30 * hFov)")
	check(CameraFx.blendFrames(0) == 1 and CameraFx.blendFrames(0.5) == 3 and CameraFx.blendFrames(1) == 6, "frame blending averages 1 / 3 / 6 frames")
end

local function orbit(steps: number, degrees: number, pivot: Vector3)
	for _ = 1, steps do
		local offset = camera.CFrame.Position - pivot
		local turned = CFrame.Angles(0, math.rad(degrees), 0) * offset
		camera.CFrame = CFrame.lookAt(pivot + turned, pivot)
		CameraFx.step(camera, 1 / 60)
	end
end

local function testCameraFxAdopted()
	local dof = Instance.new("DepthOfFieldEffect")
	dof.Name = "PlaceDepthOfField"
	dof.FocusDistance, dof.InFocusRadius, dof.FarIntensity, dof.NearIntensity = 33, 11, 0.2, 0.3
	dof.Parent = Lighting
	parkPlaceDofs(dof)
	local pivot = Vector3.new(0, 50, 0)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(pivot + Vector3.new(0, 4, 14), pivot)
	camera.Focus = CFrame.new(pivot)

	CameraFx.start({ motionBlur = 0.5, frameBlending = 0.5 })
	CameraFx.start({ motionBlur = 0.5, frameBlending = 0.5 }) -- idempotent
	CameraFx.step(camera, 1 / 60)
	check(CameraFx.effect() == dof, "CameraFx adopts the place's depth of field")
	check(countOf("DepthOfFieldEffect") == 1, "and does not add a second one")
	check(dof:GetAttribute("ForgeGUICameraFxAdopted") == true, "the adopted effect is tagged")
	near(dof:GetAttribute("ForgeGUICameraFxPrior_FocusDistance"), 33, "its prior focus distance is recorded")

	orbit(6, 2, pivot)
	local movingFar = CameraFx.motion()
	check(movingFar > 0, "orbiting the pivot raises the far motion blur")
	orbit(1, 90, pivot)
	local cutFar, cutNear = CameraFx.motion()
	check(cutFar == 0 and cutNear == 0, "a 90-degree jump is a cut: no flash of blur")

	CameraFx.start({
		motionBlur = 0.5,
		isSuppressed = function()
			return true
		end,
	})
	orbit(20, 2, pivot)
	local suppressedFar = CameraFx.motion()
	check(suppressedFar == 0, "no motion blur while suppressed (modal, pause)")

	dof.InFocusRadius = 44 -- someone else writes mid-run
	CameraFx.step(camera, 1 / 60)
	CameraFx.stop()
	CameraFx.stop() -- idempotent
	near(dof.InFocusRadius, 44, "stop follows the latest external write")
	near(dof.FocusDistance, 33, "stop restores the adopted focus distance")
	check(dof.Parent == Lighting, "the adopted effect is never destroyed")
	check(not hasPrefix(dof, "ForgeGUICameraFx"), "adoption tag and priors are removed")
	dof:Destroy()
end

local function testCameraFxOwned()
	parkPlaceDofs(nil)
	CameraFx.start({ depthOfField = true })
	CameraFx.step(camera, 1 / 60)
	local made = CameraFx.effect()
	check(made ~= nil and made.Parent == camera, "with none in the place, CameraFx creates one under the camera")
	check(made ~= nil and made:GetAttribute("ForgeGUICameraFx") == true, "the created effect carries the owned tag")
	CameraFx.stop()
	check(made ~= nil and made.Parent == nil, "stop destroys the effect it created")

	-- A session that never stopped: a fresh require's stop() still cleans up.
	local stale = Instance.new("DepthOfFieldEffect")
	stale.FocusDistance = 77
	stale:SetAttribute("ForgeGUICameraFxAdopted", true)
	stale:SetAttribute("ForgeGUICameraFxPrior_FocusDistance", 20)
	stale.Parent = Lighting
	CameraFx.stop()
	near(stale.FocusDistance, 20, "stop sweeps a stale adopted effect back to its prior")
	check(not hasPrefix(stale, "ForgeGUICameraFx"), "and removes its attributes")
	stale:Destroy()
end

-- FrameSmoothing ------------------------------------------------------------------------

local function settleTime(level: number): number
	local life = FrameSmoothing.halfLife(level)
	local first, second, t, dt = 0, 0, 0, 1 / 1000
	while second < 0.5 do
		local a = FrameSmoothing.alpha(dt, life)
		first += (1 - first) * a
		second += (first - second) * a
		t += dt
	end
	return t
end

local function testFrameSmoothing()
	near(FrameSmoothing.halfLife(0), 0, "frame smoothing Off has no lag")
	near(FrameSmoothing.halfLife(0.5), 0.018, "Low is an 18 ms half-life")
	near(FrameSmoothing.halfLife(1), 0.040, "High is a 40 ms half-life")
	near(settleTime(0.5), 0.018, "the two-stage filter really reaches half way in 18 ms", 0.002)
	near(settleTime(1), 0.040, "and in 40 ms on High", 0.004)

	FrameSmoothing.setLevel(1)
	camera.CameraType = Enum.CameraType.Custom
	local a = CFrame.new(0, 60, 0)
	camera.CFrame = a
	FrameSmoothing.smooth(1 / 60)
	local b = a + Vector3.new(1, 0, 0)
	camera.CFrame = b
	FrameSmoothing.smooth(1 / 60)
	local x = camera.CFrame.Position.X
	check(x > 0 and x < 1, "the picture eases toward the camera module's output")
	check(FrameSmoothing.raw() == b, "the module's own output is kept")
	FrameSmoothing.watch()
	FrameSmoothing.restore()
	check(camera.CFrame == b, "before the camera module runs, it gets its own output back")
	camera.CFrame = b + Vector3.new(50, 0, 0)
	FrameSmoothing.smooth(1 / 60)
	check(camera.CFrame.Position.X == b.Position.X + 50, "a 50-stud jump is a cut and snaps")
	camera.CameraType = Enum.CameraType.Scriptable
	FrameSmoothing.smooth(1 / 60)
	check(FrameSmoothing.raw() == nil, "a Scriptable camera is never smoothed")
	FrameSmoothing.stop()
end

-- ColourGrade ---------------------------------------------------------------------------

local WARM = {
	exposure = 0.2,
	contrast = 0.1,
	saturation = -0.1,
	brightness = 0.02,
	tint = Color3.new(1, 0.9, 0.8),
	shadowTint = Color3.new(0.9, 1, 1.1),
	highlightTint = Color3.new(1.1, 1, 0.9),
}
local COOL = {
	exposure = -0.2,
	contrast = -0.1,
	saturation = 0.1,
	brightness = 0,
	tint = Color3.new(0.8, 0.9, 1),
}

local function testColourGradeMaths()
	near(ColourGrade.share(0), 0, "colour grade Off is neutral")
	near(ColourGrade.share(0.5), 0.55, "Natural is 55 % of the grade")
	near(ColourGrade.share(1), 1, "Cinematic is the whole grade")
	ColourGrade.setKeyframes({ { clock = 18, grade = COOL }, { clock = 6, grade = WARM } })
	near(ColourGrade.gradeAt(6).contrast, 0.1, "a keyframe's own hour is its grade")
	near(ColourGrade.gradeAt(12).contrast, 0, "noon is half way between the 6:00 and 18:00 keys")
	near(ColourGrade.gradeAt(0).exposure, 0, "midnight blends 18:00 into 6:00 across the wrap")
	near(ColourGrade.gradeAt(3).exposure, 0.1, "3:00 is three quarters of the way to 6:00")
end

local function testColourGradeLayers()
	local grey = Color3.fromRGB(128, 128, 128)
	Lighting.Ambient = grey
	local shadow = ColourGrade.nudge(WARM.shadowTint)
	local ccBefore = countOf("ColorCorrectionEffect")
	local noon = function()
		return 12
	end
	ColourGrade.start({ keyframes = { { clock = 0, grade = WARM } }, strength = 1, getClock = noon })
	ColourGrade.start({ keyframes = { { clock = 0, grade = WARM } }, strength = 1, getClock = noon }) -- idempotent
	ColourGrade.step()
	check(countOf("ColorCorrectionEffect") == ccBefore + 1, "ColourGrade adds exactly one colour correction")
	local cc = camera:FindFirstChild("ForgeGUI_ColourGrade") :: ColorCorrectionEffect
	check(cc ~= nil and cc:GetAttribute("ForgeGUIColourGrade") == true, "under the camera, with the owned tag")
	near(cc.Contrast, 0.1, "the effect carries the grade's contrast")
	near(Lighting:GetAttribute("ForgeGUIGradeExposure"), 0.2, "the grade's exposure is published as an attribute")
	near(Lighting.ExposureCompensation, placeValues.ExposureCompensation, "ColourGrade never writes ExposureCompensation")
	check(sameColour(Lighting:GetAttribute("ForgeGUIColourGradePrior_Ambient") :: Color3, grey), "the borrowed ambient's prior is recorded")
	check(sameColour(Lighting.Ambient, times(grey, shadow)), "the shadow tone multiplies into the ambient")

	local external = Color3.fromRGB(100, 110, 120)
	Lighting.Ambient = external -- a day/night script writes mid-run
	ColourGrade.step()
	check(sameColour(Lighting.Ambient, times(external, shadow)), "the tone follows the new external value")

	ColourGrade.setStrength(0)
	ColourGrade.step()
	near(cc.Contrast, 0, "strength 0 neutralises the effect")

	ColourGrade.stop()
	ColourGrade.stop() -- idempotent
	check(cc.Parent == nil, "stop destroys the owned effect")
	check(sameColour(Lighting.Ambient, external), "stop hands back the latest external ambient")
	check(sameColour(Lighting.ColorShift_Top, placeValues.ColorShift_Top), "and the original sun colour")
	check(not hasPrefix(Lighting, "ForgeGUIColourGradePrior_"), "prior attributes are removed")
	check(Lighting:GetAttribute("ForgeGUIGradeExposure") == nil, "the published exposure is removed")
end

local function testLutGradesAndPresets()
	if LutGrades then
		ColourGrade.start({ grades = LutGrades.grades, keyframes = { { clock = 0, grade = "golden_hour" } } })
		ColourGrade.step()
		near(ColourGrade.current().contrast, LutGrades.grades.golden_hour.contrast, "named grades from lut_fit resolve")
		ColourGrade.stop()
	end
	if not LightingPresets or LightingPresets.current() ~= nil then
		return -- absent, or the place already carries a preset this run must not clear
	end
	ColourGrade.start({ keyframes = { { clock = 0, grade = WARM } } })
	ColourGrade.step()
	LightingPresets.apply("sunset") -- applied while the grade's layers are on
	local ours = camera:FindFirstChild("ForgeGUI_ColourGrade")
	check(ours ~= nil and ours:GetAttribute("ForgeGUIPresetAdopted") == nil, "LightingPresets never adopts the grade's effect")
	ColourGrade.step()
	local presetShift = LightingPresets.Presets.sunset.lighting.ColorShift_Top
	ColourGrade.stop()
	check(sameColour(Lighting.ColorShift_Top, presetShift), "a preset applied mid-run survives ColourGrade.stop")
	LightingPresets.clear()
	check(sameColour(Lighting.ColorShift_Top, placeValues.ColorShift_Top), "and LightingPresets.clear still restores the original")
end

-- EyeAdaptation -------------------------------------------------------------------------

local function testEyeAdaptationProbe()
	near(EyeAdaptation.targetFor(0.42, 1), 0, "a scene at the key luminance needs no adaptation")
	near(EyeAdaptation.targetFor(0.42 / 4, 1), 1.1, "two stops darker opens up 2 * 0.55 stops")
	near(EyeAdaptation.targetFor(1e-4, 1), 1.3, "opening up is capped at +1.3")
	near(EyeAdaptation.targetFor(100, 1), -0.7, "closing down is capped at -0.7")

	local part = Instance.new("Part")
	part.Name = "TestKit_3"
	part.Anchored, part.Size, part.Color = true, Vector3.new(20, 20, 1), Color3.new(0.2, 0.4, 0.6)
	part.CFrame = CFrame.new(0, 200, -10)
	part.Parent = Workspace
	EyeAdaptation.start({ enabled = false })
	local hit = EyeAdaptation.cast(Vector3.new(0, 200, 0), Vector3.new(0, 0, -20))
	check(hit ~= nil and sameColour(hit.albedo, part.Color), "a plain part's albedo is its colour")
	EyeAdaptation.start({ enabled = false, albedo = { TestKit = Color3.new(0.9, 0.1, 0.1) } })
	hit = EyeAdaptation.cast(Vector3.new(0, 200, 0), Vector3.new(0, 0, -20))
	check(hit ~= nil and sameColour(hit.albedo, Color3.new(0.9, 0.1, 0.1)), "the injected albedo map wins, by kit name")
	part:Destroy()
end

local function testEyeAdaptationExposure()
	Lighting:SetAttribute("ForgeGUIGradeExposure", 0.2)
	local base = Lighting.ExposureCompensation
	EyeAdaptation.step(1 / 60)
	near(Lighting.ExposureCompensation, base + 0.2, "exposure = base + the grade's exposure")
	near(Lighting:GetAttribute("ForgeGUIEyeAdaptationPrior_ExposureCompensation"), base, "the prior exposure is recorded")
	Lighting.ExposureCompensation = 0.5 -- a preset or day/night script
	EyeAdaptation.step(1 / 60)
	near(Lighting.ExposureCompensation, 0.7, "the base follows an external write")
	EyeAdaptation.setEnabled(true)
	EyeAdaptation.step(0.1)
	check(math.abs(EyeAdaptation.adaptation()) <= 1.8 * 0.1 + 1e-6, "adaptation eases at most 1.8 stops a second")
	EyeAdaptation.stop()
	EyeAdaptation.stop() -- idempotent
	near(Lighting.ExposureCompensation, 0.5, "stop hands back the external exposure")
	check(Lighting:GetAttribute("ForgeGUIEyeAdaptationPrior_ExposureCompensation") == nil, "the prior attribute is removed")
	Lighting:SetAttribute("ForgeGUIGradeExposure", nil)
end

-- GraphicsPreset ------------------------------------------------------------------------

local function testGraphicsPreset()
	check(GraphicsPreset.pick(10) == "High", "a 10 ms 90th percentile earns High")
	check(GraphicsPreset.pick(20) == "Medium", "20 ms earns Medium")
	check(GraphicsPreset.pick(30) == "Low", "30 ms earns Low")
	local frames = table.create(9, 0.010)
	table.insert(frames, 0.050)
	near(GraphicsPreset.percentile90(frames), 10, "the 90th percentile ignores one hitch in ten")
	local seen: { string } = {}
	local lastValues: any = nil
	GraphicsPreset.start({
		preset = "Low",
		onPreset = function(level: string, values: any)
			table.insert(seen, level)
			lastValues = values
		end,
	})
	check(seen[1] == "Low" and lastValues.motionBlur == 0, "Low hands its option table to the callback")
	GraphicsPreset.setPreset("High")
	check(seen[2] == "High", "a new preset calls back again")
	GraphicsPreset.setPreset("Custom")
	local preset, level = GraphicsPreset.current()
	check(preset == "Custom" and level == nil, "Custom leaves every option alone")
	GraphicsPreset.stop()
	GraphicsPreset.stop() -- idempotent
end

-- Run -----------------------------------------------------------------------------------

local ok, failure = xpcall(function()
	testCameraFxMaths()
	testCameraFxAdopted()
	testCameraFxOwned()
	testFrameSmoothing()
	testColourGradeMaths()
	testColourGradeLayers()
	testLutGradesAndPresets()
	testEyeAdaptationProbe()
	testEyeAdaptationExposure()
	testGraphicsPreset()
end, debug.traceback)

for _, module in { CameraFx, FrameSmoothing, ColourGrade, EyeAdaptation, GraphicsPreset } do
	pcall(module.stop)
end
for _, entry in parked do
	entry.effect.Parent = entry.parent
end
for _, property in WATCHED do
	pcall(function()
		(Lighting :: any)[property] = placeValues[property]
	end)
end
camera.CameraType, camera.CFrame, camera.Focus = cameraType, cameraCFrame, cameraFocus

if not ok then
	print(`FAIL post-stack regression after {#checks} checks:\n{failure}`)
	error(failure)
end
print(`PASS post-stack regression: {#checks} checks passed`)
for _, label in checks do
	print("  ok", label)
end
