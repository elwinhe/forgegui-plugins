--!strict
-- GraphicsPreset: Auto / Low / Medium / High, with Auto picked from measured
-- frame time. It owns no effects: it hands a level and that level's option
-- table to your callback, which sets the other modules. Client only.
--
-- 	local GraphicsPreset = require(path.to.GraphicsPreset)
-- 	GraphicsPreset.start({
-- 		preset = "Auto",
-- 		isReady = function() return player.Character ~= nil end,
-- 		onPreset = function(level, values)
-- 			CameraFx.setMotionBlur(values.motionBlur :: number)
-- 			CameraFx.setFrameBlending(values.frameBlending :: number)
-- 			CameraFx.setDepthOfField(values.depthOfField :: boolean)
-- 			FrameSmoothing.setLevel(values.frameSmoothing :: number)
-- 		end,
-- 	})
-- 	GraphicsPreset.setPreset("High")
--
-- Auto: waits until `isReady()` (the player is in the world, not on a loading
-- screen), lets the frame settle for 3 s, samples RenderStepped frame times for
-- 4 s and picks High when the 90th percentile is under 18 ms, Medium under
-- 26 ms, else Low. Roblox caps most players at 60 fps (16.7 ms frames), so High
-- means "holds 60" and Medium "holds about 40", not raw speed. Frames while the
-- window is unfocused are not counted (Roblox throttles them). While on Auto,
-- frames averaging over 22 ms for 10 s step it down one level, at most once a
-- minute; it never steps up by itself (re-select Auto to re-measure).
--
-- Measured with the full post stack on High: ~6 ms median in an open area with
-- ~60 close-up ground meshes, ~11 ms median in a dense town. The camera effects
-- themselves (CameraFx, FrameSmoothing, ColourGrade) are arithmetic; what the
-- levels trade is the GPU cost of the depth of field and whatever heavier
-- options your game adds to `levels` (reflections, shadows, clouds).
--
-- "Custom": call setPreset("Custom") when the player changes an option a preset
-- sets; the module then leaves every option alone.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GraphicsPreset = {}

export type Level = "Low" | "Medium" | "High"
export type Preset = "Auto" | Level | "Custom"
export type Values = { [string]: number | boolean }
export type Options = {
	preset: Preset?, -- default "Auto"
	onPreset: ((level: Level, values: Values) -> ())?,
	isReady: (() -> boolean)?, -- default: always ready
	levels: { [string]: Values }?, -- replaces the default option tables, keyed by level
	highMs: number?, -- default 18
	mediumMs: number?, -- default 26
}

local SETTLE_SECONDS, SAMPLE_SECONDS = 3, 4
local HIGH_MS, MEDIUM_MS = 18, 26
local SLOW_MS, SLOW_SECONDS, STEP_DOWN_GAP = 22, 10, 60
local ORDER: { Level } = { "Low", "Medium", "High" }

-- The post stack's options per level: 0 / 0.5 / 1 are Off / Low / High, the
-- colour grade's are Off / Natural / Cinematic. Add your game's own keys.
local LEVELS: { [string]: Values } = {
	Low = { motionBlur = 0, frameBlending = 0, frameSmoothing = 0.5, depthOfField = false, colourGrade = 1, eyeAdaptation = true },
	Medium = { motionBlur = 0.5, frameBlending = 0.5, frameSmoothing = 0.5, depthOfField = true, colourGrade = 1, eyeAdaptation = true },
	High = { motionBlur = 0.5, frameBlending = 0.5, frameSmoothing = 0.5, depthOfField = true, colourGrade = 1, eyeAdaptation = true },
}
GraphicsPreset.LEVELS = LEVELS

local opts: Options = {}
local preset: Preset = "Auto"
local level: Level? = nil -- the level applied (nil while measuring or on Custom)
local token = 0 -- bumped on every preset change, cancelling a running measurement
local focused = true
local lastStepDown = -math.huge
local started = false
local connections: { RBXScriptConnection } = {}
local windowTime, windowFrames, slowFor = 0, 0, 0

-- The level a 90th-percentile frame time (ms) earns.
function GraphicsPreset.pick(p90ms: number, highMs: number?, mediumMs: number?): Level
	if p90ms < (highMs or HIGH_MS) then
		return "High"
	end
	return if p90ms < (mediumMs or MEDIUM_MS) then "Medium" else "Low"
end

-- The 90th percentile of frame times given in seconds, returned in ms.
function GraphicsPreset.percentile90(samples: { number }): number
	if #samples == 0 then
		return 0
	end
	local sorted = table.clone(samples)
	table.sort(sorted)
	return sorted[math.ceil(#sorted * 0.9)] * 1000
end

local function apply(picked: Level)
	level = picked
	local tables = opts.levels or LEVELS
	local callback = opts.onPreset
	if callback then
		callback(picked, table.clone(tables[picked] or {}))
	end
end

local function measure(my: number)
	local ready = opts.isReady
	while token == my and ready and not ready() do
		task.wait(0.5)
	end
	task.wait(SETTLE_SECONDS)
	local samples: { number } = {}
	local elapsed = 0
	local sampler = RunService.RenderStepped:Connect(function(dt: number)
		if focused then
			table.insert(samples, dt)
			elapsed += dt
		end
	end)
	while token == my and elapsed < SAMPLE_SECONDS do
		task.wait(0.25)
	end
	sampler:Disconnect()
	if token ~= my or #samples == 0 then
		return
	end
	apply(GraphicsPreset.pick(GraphicsPreset.percentile90(samples), opts.highMs, opts.mediumMs))
end

-- Auto only: a steady slow patch drops one level.
local function watch(dt: number)
	local current = level
	if not (current and focused and preset == "Auto") then
		windowTime, windowFrames, slowFor = 0, 0, 0
		return
	end
	windowTime += dt
	windowFrames += 1
	if windowTime < 1 then
		return
	end
	slowFor = if windowTime / windowFrames * 1000 > SLOW_MS then slowFor + windowTime else 0
	windowTime, windowFrames = 0, 0
	local index = table.find(ORDER, current) or 1
	local now = os.clock()
	if slowFor >= SLOW_SECONDS and index > 1 and now - lastStepDown >= STEP_DOWN_GAP then
		lastStepDown, slowFor = now, 0
		apply(ORDER[index - 1])
	end
end

function GraphicsPreset.setPreset(value: Preset)
	token += 1
	preset = value
	level = nil
	if value == "Custom" then
		return
	elseif value == "Auto" then
		if started then
			task.spawn(measure, token)
		end
	elseif value == "Low" or value == "Medium" or value == "High" then
		apply(value)
	else
		warn(`GraphicsPreset: unknown preset '{value}'`)
	end
end

-- The preset chosen and the level in force (nil while Auto is measuring, or on Custom).
function GraphicsPreset.current(): (Preset, Level?)
	return preset, level
end

function GraphicsPreset.start(options: Options?)
	opts = options or {}
	if not started then
		started = true
		table.insert(connections, UserInputService.WindowFocused:Connect(function()
			focused = true
		end))
		table.insert(connections, UserInputService.WindowFocusReleased:Connect(function()
			focused = false
		end))
		table.insert(connections, RunService.RenderStepped:Connect(watch))
	end
	GraphicsPreset.setPreset(opts.preset or "Auto")
end

function GraphicsPreset.stop()
	token += 1 -- cancels a running measurement
	started = false
	for _, connection in connections do
		connection:Disconnect()
	end
	connections = {}
	level = nil
	windowTime, windowFrames, slowFor = 0, 0, 0
end

return GraphicsPreset
