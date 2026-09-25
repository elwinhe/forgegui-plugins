--!strict
-- ColourGrade: a film-style colour grade from real LUTs, blended by time of day.
-- Client only: require it from a LocalScript.
--
-- 	local ColourGrade = require(path.to.ColourGrade)
-- 	local Luts = require(path.to.LutGrades) -- written by references/tools/lut_fit.py
-- 	ColourGrade.start({
-- 		grades = Luts.grades,
-- 		keyframes = {
-- 			{ clock = 6.5, grade = "golden_hour" },
-- 			{ clock = 12, grade = "neutral" },
-- 			{ clock = 18, grade = "golden_hour" },
-- 			{ clock = 21, grade = "moonlight" },
-- 		},
-- 		strength = 1, -- 0 off, 0.5 natural, 1 cinematic
-- 	})
--
-- Roblox has no LUT support, and every ColorCorrectionEffect in view merges
-- into one: their Contrast, Saturation and Brightness ADD and their tints
-- MULTIPLY (measured), so stacking effects cannot build a curve. Each .cube is
-- therefore fitted offline (lut_fit.py) to the most Roblox can show: an
-- exposure shift along its filmic tone curve plus one colour correction, with
-- the split toning the correction cannot express (shadows and highlights tinted
-- apart) handed to the scene lights: the shadow tone into Ambient and
-- OutdoorAmbient, the highlight tone into ColorShift_Top.
--
-- Between keyframes the two grades blend linearly (wrapping past midnight).
-- Strength scales the whole grade toward neutral: 0 off, 0.5 "Natural" (55 %
-- of the grade: half read as timid in play), 1 "Cinematic". Because Roblox adds
-- CC effects, any other CC in the place (a preset's, a storm's, a damage flash)
-- still stacks on top of this one. That is the intended composition.
--
-- Ownership:
-- - One ColorCorrectionEffect, created under the current camera (never in
--   Lighting, where LightingPresets would adopt it), named ForgeGUI_ColourGrade
--   and tagged ForgeGUIColourGrade = true. stop() destroys only that.
-- - Lighting colours are submitted to the shared sibling LightingCompositor.
--   It composes base -> GI -> grade and restores the latest base when both stop.
-- - It never writes ExposureCompensation. The grade's exposure shift is
--   published as the Lighting attribute ForgeGUIGradeExposure, which
--   EyeAdaptation adds (run it with enabled = false for the grade's exposure
--   without auto-exposure). One writer per property keeps the two from
--   compounding each other every frame.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Compositor = require(script.Parent.LightingCompositor)

local ColourGrade = {}

export type Grade = {
	exposure: number,
	contrast: number,
	saturation: number,
	brightness: number,
	tint: Color3,
	shadowTint: Color3?,
	highlightTint: Color3?,
	rmsError: number?, -- carried by lut_fit output; not used here
	source: string?,
}
export type Keyframe = { clock: number, grade: string | Grade }
export type Options = {
	grades: { [string]: Grade }?, -- named grades, e.g. require(LutGrades).grades
	keyframes: { Keyframe }?, -- default: one neutral key
	strength: number?, -- 0 off, 0.5 natural, 1 cinematic (default 1)
	getClock: (() -> number)?, -- hours 0..24; default Lighting.ClockTime
	splitTone: boolean?, -- tint the lights with the split tone (default true)
	interval: number?, -- seconds between updates (default 0.1)
}

type Key = { clock: number, grade: Grade }

local OWNED_ATTR = "ForgeGUIColourGrade"
local EXPOSURE_ATTR = "ForgeGUIGradeExposure"
local EFFECT_NAME = "ForgeGUI_ColourGrade"
local NATURAL = 0.55 -- the grade share at strength 0.5
local DEFAULT_INTERVAL = 0.1
local WHITE = Color3.new(1, 1, 1)
local NEUTRAL: Grade = {
	exposure = 0,
	contrast = 0,
	saturation = 0,
	brightness = 0,
	tint = WHITE,
	shadowTint = WHITE,
	highlightTint = WHITE,
}

local grades: { [string]: Grade } = {}
local keys: { Key } = { { clock = 12, grade = NEUTRAL } }
local strength = 1
local splitTone = true
local interval = DEFAULT_INTERVAL
local getClock: (() -> number)? = nil

local started = false
local connection: RBXScriptConnection? = nil
local effect: ColorCorrectionEffect? = nil
local applied: Grade = NEUTRAL

-- Grade maths --------------------------------------------------------------------------

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- a..b at t (0 = a, 1 = b).
function ColourGrade.blend(a: Grade, b: Grade, t: number): Grade
	return {
		exposure = lerp(a.exposure, b.exposure, t),
		contrast = lerp(a.contrast, b.contrast, t),
		saturation = lerp(a.saturation, b.saturation, t),
		brightness = lerp(a.brightness, b.brightness, t),
		tint = a.tint:Lerp(b.tint, t),
		shadowTint = (a.shadowTint or WHITE):Lerp(b.shadowTint or WHITE, t),
		highlightTint = (a.highlightTint or WHITE):Lerp(b.highlightTint or WHITE, t),
	}
end

-- The grade share for a strength setting: 0 -> 0, 0.5 -> 0.55, 1 -> 1, linear between.
function ColourGrade.share(value: number): number
	local s = math.clamp(value, 0, 1)
	if s <= 0.5 then
		return NATURAL * s / 0.5
	end
	return NATURAL + (1 - NATURAL) * (s - 0.5) / 0.5
end

-- A split tone as a gentle nudge for a light: the square root halves its
-- strength, and it is rescaled to keep brightness, so it can only shift hue (a
-- fitting artifact in one channel cannot flood the shade).
function ColourGrade.nudge(c: Color3): Color3
	local r, g, b = math.sqrt(c.R), math.sqrt(c.G), math.sqrt(c.B)
	local luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
	if luma <= 1e-6 then
		return WHITE
	end
	return Color3.new(r / luma, g / luma, b / luma)
end

-- Keyframes ------------------------------------------------------------------------------

local function resolve(grade: string | Grade): Grade
	if type(grade) == "string" then
		local found = grades[grade]
		if not found then
			warn(`ColourGrade: unknown grade '{grade}', using neutral`)
			return NEUTRAL
		end
		return found
	end
	return grade
end

function ColourGrade.setKeyframes(keyframes: { Keyframe })
	local list: { Key } = {}
	for _, key in keyframes do
		table.insert(list, { clock = key.clock % 24, grade = resolve(key.grade) })
	end
	table.sort(list, function(a, b)
		return a.clock < b.clock
	end)
	if #list == 0 then
		table.insert(list, { clock = 12, grade = NEUTRAL })
	end
	keys = list
end

-- The full-strength grade at a clock time (hours), blending the two keys around it.
function ColourGrade.gradeAt(clock: number): Grade
	if #keys == 1 then
		return keys[1].grade
	end
	local c = clock % 24
	local after = 1
	while after <= #keys and keys[after].clock <= c do
		after += 1
	end
	local nextKey = keys[if after > #keys then 1 else after]
	local prevKey = keys[if after == 1 then #keys else after - 1]
	local span = (nextKey.clock - prevKey.clock) % 24
	local t = if span > 0 then ((c - prevKey.clock) % 24) / span else 0
	return ColourGrade.blend(prevKey.grade, nextKey.grade, t)
end

-- The effect -------------------------------------------------------------------------------

local function currentEffect(): ColorCorrectionEffect?
	local camera = Workspace.CurrentCamera
	local existing = effect
	if existing and existing.Parent ~= nil and existing.Parent == camera then
		return existing
	end
	if existing then
		existing:Destroy() -- the camera changed; follow it
	end
	if not camera then
		effect = nil
		return nil
	end
	local made = Instance.new("ColorCorrectionEffect")
	made.Name = EFFECT_NAME
	made:SetAttribute(OWNED_ATTR, true)
	made.Parent = camera
	effect = made
	return made
end

-- One update. Public so tests and custom loops can drive it.
function ColourGrade.step()
	local clock = if getClock then getClock() else Lighting.ClockTime
	local g = ColourGrade.blend(NEUTRAL, ColourGrade.gradeAt(clock), ColourGrade.share(strength))
	applied = g
	local cc = currentEffect()
	if cc then
		cc.Contrast = g.contrast
		cc.Saturation = g.saturation
		cc.Brightness = g.brightness
		cc.TintColor = g.tint
		cc.Enabled = true
	end
	Lighting:SetAttribute(EXPOSURE_ATTR, g.exposure)
	if splitTone and strength > 0 then
		Compositor.setGrade(ColourGrade.nudge(g.shadowTint or WHITE), ColourGrade.nudge(g.highlightTint or WHITE))
	else
		Compositor.setGrade(nil, nil)
	end
end

-- The grade on screen now (already scaled by strength).
function ColourGrade.current(): Grade
	return applied
end

function ColourGrade.setStrength(value: number)
	strength = if type(value) == "number" and value == value then math.clamp(value, 0, 1) else 1
end

-- Start / stop ------------------------------------------------------------------------------

-- Cleans up after a session that never called stop() (or a fresh require).
local function sweep()
	local parents: { Instance } = { Lighting }
	local camera = Workspace.CurrentCamera
	if camera then
		table.insert(parents, camera)
	end
	for _, parent in parents do
		for _, child in parent:GetChildren() do
			if child:GetAttribute(OWNED_ATTR) == true then
				child:Destroy()
			end
		end
	end
	Lighting:SetAttribute(EXPOSURE_ATTR, nil)
end

function ColourGrade.start(options: Options?)
	local opts: Options = options or {}
	grades = opts.grades or {}
	splitTone = opts.splitTone ~= false
	interval = math.max(opts.interval or DEFAULT_INTERVAL, 0)
	getClock = opts.getClock
	ColourGrade.setStrength(if opts.strength ~= nil then opts.strength else 1)
	ColourGrade.setKeyframes(opts.keyframes or {})
	if started then
		return
	end
	started = true
	sweep() -- leftovers from a session that never stopped
	local since = math.huge
	connection = RunService.Heartbeat:Connect(function(dt: number)
		since += dt
		if since >= interval then
			since = 0
			ColourGrade.step()
		end
	end)
end

function ColourGrade.stop()
	started = false
	local c = connection
	if c then
		c:Disconnect()
		connection = nil
	end
	Compositor.setGrade(nil, nil)
	local cc = effect
	if cc then
		cc:Destroy()
		effect = nil
	end
	applied = NEUTRAL
	sweep()
end

return ColourGrade
