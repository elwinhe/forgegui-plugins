--!strict
-- FrameSmoothing: presentation-only camera smoothing, like Unreal's smoothed
-- frame pacing. The picture eases after the camera instead of jumping with
-- every uneven frame, while the camera module's own state is untouched.
-- Client only: require it from a LocalScript.
--
-- 	local FrameSmoothing = require(path.to.FrameSmoothing)
-- 	FrameSmoothing.start({ level = 0.5 }) -- 0 off, 0.5 low (18 ms), 1 high (40 ms)
-- 	FrameSmoothing.setLevel(1)
-- 	FrameSmoothing.stop()
--
-- The restore trick. Roblox's camera module reads Camera.CFrame back when it
-- computes the next frame, so writing a smoothed CFrame naively feeds back into
-- it: the camera drifts and the mouse feels heavy. So, each frame:
-- - at RenderPriority.Camera - 1 the unsmoothed CFrame the module produced
--   last frame is put back, and the module sees its own output;
-- - at RenderPriority.Camera + 1 the module's new output is read as the
--   target, kept, and a smoothed CFrame is written for this frame's picture;
-- - at RenderPriority.Last + 1 the CFrame the frame ends on is noted. If
--   something else moves the camera before the next frame (a script placing
--   it), the restore is skipped and the smoothing starts over from there.
--
-- The filter is two first-order stages in a row (critically damped: no
-- overshoot), frame-time aware (each stage follows 1 - 2^(-dt / stage
-- half-life)), with CFrame:Lerp slerping the rotation. The level picks the whole
-- response's half-life: 0 / 18 ms / 40 ms at 0 / 0.5 / 1, linear between. A
-- hitch counts as at most 50 ms, so it never whips the camera. 18 ms is about
-- one 60 Hz frame of lag and hides frame-time jitter; 40 ms reads as a heavier,
-- filmic camera. More than that and aiming feels late.
--
-- Never smooths unless Camera.CameraType is Custom (scripted shots are
-- Scriptable and must land exactly), and snaps on cuts (a jump over 20 studs or
-- a turn over 60 degrees in one frame), on respawn and when the current camera
-- changes. Creates no instances and borrows no properties: stop() unbinds and
-- hands the camera the module's last unsmoothed CFrame.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FrameSmoothing = {}

export type Options = { level: number? }

type State = { camera: Camera, raw: CFrame, first: CFrame, second: CFrame, seen: CFrame? }

local RESTORE_NAME = "ForgeGUIFrameSmoothingRestore"
local SMOOTH_NAME = "ForgeGUIFrameSmoothing"
local WATCH_NAME = "ForgeGUIFrameSmoothingWatch"
local HALF_LIFE_LOW, HALF_LIFE_HIGH = 0.018, 0.040 -- seconds, at level 0.5 and 1
-- Two equal first-order stages reach half way at about 2.43 stage half-lives,
-- so each stage takes this share of the whole response's half-life.
local STAGE_SHARE = 0.41
local MAX_DT = 1 / 20
local CUT_DISTANCE = 20 -- studs in one frame
local CUT_ANGLE = math.rad(60) -- in one frame
local MOVED_EPSILON = 1e-4

local level = 0.5
local state: State? = nil
local started = false
local respawn: RBXScriptConnection? = nil

-- The whole response's half-life for a level 0..1, in seconds.
function FrameSmoothing.halfLife(value: number): number
	local v = math.clamp(value, 0, 1)
	if v <= 0.5 then
		return HALF_LIFE_LOW * v / 0.5
	end
	return HALF_LIFE_LOW + (HALF_LIFE_HIGH - HALF_LIFE_LOW) * (v - 0.5) / 0.5
end

-- The per-stage blend for one frame of `dt` seconds at a whole-response half-life.
function FrameSmoothing.alpha(dt: number, life: number): number
	if life <= 0 then
		return 1
	end
	return 1 - 2 ^ (-math.clamp(dt, 0, MAX_DT) / (life * STAGE_SHARE))
end

local function isCustom(camera: Camera?): boolean
	return camera ~= nil and camera.CameraType == Enum.CameraType.Custom
end

-- True when the camera module's output jumped from `from` to `to` in one frame.
local function isCut(from: CFrame, to: CFrame): boolean
	if (to.Position - from.Position).Magnitude > CUT_DISTANCE then
		return true
	end
	local _, angle = (from.Rotation:Inverse() * to.Rotation):ToAxisAngle()
	return math.abs(angle) > CUT_ANGLE
end

-- Camera - 1: hand the camera module back its own last output.
local function restore()
	local s = state
	if not s then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera or camera ~= s.camera or not isCustom(camera) then
		state = nil
		return
	end
	local seen = s.seen
	if seen and not camera.CFrame:FuzzyEq(seen, MOVED_EPSILON) then
		state = nil -- something else placed the camera: keep its placement
		return
	end
	camera.CFrame = s.raw
end

-- Camera + 1: read the module's output and write the smoothed picture.
-- Public so tests and custom render loops can drive it.
function FrameSmoothing.smooth(dt: number)
	local camera = Workspace.CurrentCamera
	local life = FrameSmoothing.halfLife(level)
	if not camera or not isCustom(camera) or life <= 0 then
		state = nil
		return
	end
	local target = camera.CFrame
	local s = state
	if not s or s.camera ~= camera or isCut(s.raw, target) then
		state = { camera = camera, raw = target, first = target, second = target, seen = nil }
		return
	end
	local alpha = FrameSmoothing.alpha(dt, life)
	local first = s.first:Lerp(target, alpha)
	local second = s.second:Lerp(first, alpha)
	state = { camera = camera, raw = target, first = first, second = second, seen = nil }
	camera.CFrame = second
end

-- Last + 1: note where the frame left the camera.
local function watch()
	local s = state
	local camera = Workspace.CurrentCamera
	if s and camera == s.camera then
		state = { camera = s.camera, raw = s.raw, first = s.first, second = s.second, seen = camera.CFrame }
	end
end

function FrameSmoothing.setLevel(value: number)
	level = if type(value) == "number" and value == value then math.clamp(value, 0, 1) else 0.5
end

-- The camera module's own (unsmoothed) CFrame this frame, or nil when not smoothing.
function FrameSmoothing.raw(): CFrame?
	local s = state
	return if s then s.raw else nil
end

-- Frame hooks for tests and custom loops: restore() before the camera module,
-- watch() after everything else.
FrameSmoothing.restore = restore
FrameSmoothing.watch = watch

function FrameSmoothing.start(options: Options?)
	FrameSmoothing.setLevel(if options and options.level ~= nil then options.level else 0.5)
	if started then
		return
	end
	started = true
	RunService:BindToRenderStep(RESTORE_NAME, Enum.RenderPriority.Camera.Value - 1, restore)
	RunService:BindToRenderStep(SMOOTH_NAME, Enum.RenderPriority.Camera.Value + 1, FrameSmoothing.smooth)
	RunService:BindToRenderStep(WATCH_NAME, Enum.RenderPriority.Last.Value + 1, watch)
	local player = Players.LocalPlayer
	if player then
		respawn = player.CharacterAdded:Connect(function()
			state = nil -- a respawn snaps
		end)
	end
end

function FrameSmoothing.stop()
	if started then
		started = false
		RunService:UnbindFromRenderStep(RESTORE_NAME)
		RunService:UnbindFromRenderStep(SMOOTH_NAME)
		RunService:UnbindFromRenderStep(WATCH_NAME)
	end
	local connection = respawn
	if connection then
		connection:Disconnect()
		respawn = nil
	end
	restore() -- leave the camera where its module put it, not where the filter was
	state = nil
end

return FrameSmoothing
