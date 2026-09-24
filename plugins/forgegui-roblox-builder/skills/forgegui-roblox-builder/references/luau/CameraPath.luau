--!strict
-- CameraPath: short cinematic camera shots through keyframes. Client only.
--
--   local CameraPath = require(ReplicatedStorage.CameraPath)
--   CameraPath.play({
--       { time = 1.2, position = Vector3.new(40, 30, 40), lookAt = Vector3.new(0, 5, 0), fov = 60 },
--       { time = 2.6, cframe = function(subject) return subject * CFrame.new(0, 4, 12) end },
--   }, { blendBack = 0.35, hideGuis = true, onFinished = function(completed) end })
--
-- Keys: `time` is seconds from the start of the shot. When the first key is later
-- than 0 the shot starts from wherever the camera is; a key at 0 is a cut. A key
-- with `cut = true` holds the previous pose and jumps at its time. A key gives
-- either `cframe`, or `position` plus `lookAt`; any of them may be a function of
-- the live subject's CFrame (the character root unless `subject` is given), so a
-- shot keeps up with a running player. Poses are evaluated every frame, never baked.
--
-- The maths, and why:
-- - Positions follow a centripetal Catmull-Rom spline through the keys
--   (Barry-Goldman form, alpha 0.5). The uniform kind loops and cusps when keys
--   bunch up or double back; the centripetal kind never does. The ends use
--   mirrored phantom points, and a cut breaks the spline on both sides.
-- - Timing is eased per segment by the ARRIVING key: Cubic InOut by default,
--   which starts and settles each beat. For a move that should carry its speed
--   through a key, pair Cubic In on the first segment, Linear in the middle and
--   Cubic Out on the last. The build this came from moved its shots from Sine
--   to Cubic easing in its motion pass, hence the default.
-- - With `lookAt` on both keys of a segment the aim point is interpolated and
--   the camera looks at it every frame, which keeps a subject centred through a
--   curve; otherwise rotations slerp. FOV lerps with the same eased alpha.
-- - Easing across a very long distance is a whip-pan: cut instead (a key at the
--   start, then `cut = true` to come back).
--
-- Camera ownership: the shot binds at RenderPriority.Camera + 1 (after the
-- default camera scripts) only while it runs. It borrows Camera.CameraType and
-- FieldOfView, recording ForgeGUIPrior_CameraType / ForgeGUIPrior_FieldOfView on
-- the Camera (first shot wins, so chained shots restore the original) and the
-- CameraSubject in module state. With `hideGuis`, each ScreenGui it disables gets
-- ForgeGUIPrior_Enabled and ForgeGUICameraPath = true. When the shot ends or
-- stop() is called, everything is handed back; stop() is idempotent.
-- UI motion (panels, buttons, modals) is a separate module: see ui-motion.md.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

export type Pose = CFrame | (subject: CFrame) -> CFrame
export type Point = Vector3 | (subject: CFrame) -> Vector3
export type Keyframe = {
	time: number,
	cframe: Pose?,
	position: Point?,
	lookAt: Point?,
	fov: number?, -- default: the previous key's
	ease: Enum.EasingStyle?, -- easing of the segment arriving here, default Cubic
	dir: Enum.EasingDirection?, -- default InOut
	cut: boolean?,
}
export type Shot = { Keyframe }
export type Track = { keys: { Keyframe }, fovs: { number }, duration: number }
export type PlayOptions = {
	subject: (() -> CFrame?)?, -- default: the local character's root
	blendBack: number?, -- seconds easing from the last pose into the live camera, default 0.35
	hideGuis: boolean?, -- disable the player's ScreenGuis while the shot runs
	priority: number?, -- render priority, default Camera + 1
	onFinished: ((completed: boolean) -> ())?,
}
export type Handle = { cancel: () -> (), isPlaying: () -> boolean }

local OWNED_ATTR = "ForgeGUICameraPath"
local PRIOR_PREFIX = "ForgeGUIPrior_"
local RENDER_NAME = "ForgeGUICameraPath"
local MAX_SECONDS = 30

local CameraPath = {}
CameraPath.MAX_SECONDS = MAX_SECONDS

type Active = { track: Track, started: number, subject: CFrame, options: PlayOptions }
type Blend = { from: CFrame, fov: number, target: number, started: number, seconds: number }

local active: Active? = nil
local blend: Blend? = nil
local bound = false
local savedSubject: (BasePart | Humanoid)? = nil
local lastPose, lastFov = CFrame.identity, 70

-- Maths ----------------------------------------------------------------------------------

local function knot(a: Vector3, b: Vector3): number
	return math.max(math.sqrt((b - a).Magnitude), 1e-4)
end

-- Centripetal Catmull-Rom between p1 and p2 for u in [0, 1].
local function catmullRom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: number): Vector3
	local t1 = knot(p0, p1)
	local t2 = t1 + knot(p1, p2)
	local t3 = t2 + knot(p2, p3)
	local t = t1 + (t2 - t1) * u
	local a1 = p0:Lerp(p1, t / t1)
	local a2 = p1:Lerp(p2, (t - t1) / (t2 - t1))
	local a3 = p2:Lerp(p3, (t - t2) / (t3 - t2))
	local b1 = a1:Lerp(a2, t / t2)
	local b2 = a2:Lerp(a3, (t - t1) / (t3 - t1))
	return b1:Lerp(b2, (t - t1) / (t2 - t1))
end

local function point(value: Point, subject: CFrame): Vector3
	if type(value) == "function" then
		return value(subject)
	end
	return value :: Vector3
end

local function aim(eye: Vector3, target: Vector3): CFrame
	if (target - eye).Magnitude < 1e-3 then
		return CFrame.new(eye)
	end
	return CFrame.lookAt(eye, target)
end

-- The key's pose for the subject as it is now.
local function poseAt(key: Keyframe, subject: CFrame): CFrame
	local pose = key.cframe
	if type(pose) == "function" then
		return pose(subject)
	elseif pose then
		return pose :: CFrame
	end
	return aim(point(key.position :: Point, subject), point(key.lookAt :: Point, subject))
end

local function segmentAt(keys: { Keyframe }, t: number): number
	for i = #keys - 1, 1, -1 do
		if t >= keys[i].time then
			return i
		end
	end
	return 1
end

local function isPoint(v: any): boolean
	return typeof(v) == "Vector3" or type(v) == "function"
end

local function validKey(key: any, last: number): boolean
	if type(key) ~= "table" then
		return false
	end
	local t, pose, fov = key.time, key.cframe, key.fov
	if type(t) ~= "number" or t ~= t or t < last or t > MAX_SECONDS then
		return false
	end
	local hasPose = typeof(pose) == "CFrame" or type(pose) == "function"
	if not hasPose and not (isPoint(key.position) and isPoint(key.lookAt)) then
		return false
	end
	return fov == nil or (type(fov) == "number" and fov == fov)
end

-- True for a non-empty list of keys with ascending finite times (at most
-- MAX_SECONDS), a pose each, and numeric FOVs.
function CameraPath.valid(shot: any): boolean
	if type(shot) ~= "table" or #shot == 0 then
		return false
	end
	local last = 0
	for _, key in shot do
		if not validKey(key, last) then
			return false
		end
		last = key.time
	end
	return true
end

-- The shot as a track: the start pose becomes key 0 unless the shot opens with a
-- key at 0, and a key without a FOV keeps the previous one. `shot` is not changed.
function CameraPath.prepare(shot: Shot, from: CFrame, fromFov: number): Track
	local keys: { Keyframe } = {}
	if shot[1].time > 0 then
		table.insert(keys, { time = 0, cframe = from, fov = fromFov })
	end
	for _, key in shot do
		table.insert(keys, key)
	end
	local fovs: { number } = {}
	local fov = fromFov
	for i, key in keys do
		local wanted = key.fov
		if wanted then
			fov = math.clamp(wanted, 1, 120)
		end
		fovs[i] = fov
	end
	return { keys = keys, fovs = fovs, duration = keys[#keys].time }
end

-- The pose and FOV `t` seconds into the track, for the subject as it is now.
function CameraPath.evaluate(track: Track, subject: CFrame, t: number): (CFrame, number)
	local keys, fovs = track.keys, track.fovs
	local n = #keys
	if n == 1 or t >= keys[n].time then
		return poseAt(keys[n], subject), fovs[n]
	end
	local i = segmentAt(keys, t)
	local k1, k2 = keys[i], keys[i + 1]
	local c1 = poseAt(k1, subject)
	if k2.cut then
		return c1, fovs[i]
	end
	local c2 = poseAt(k2, subject)
	local span = k2.time - k1.time
	local u = if span > 0 then math.clamp((t - k1.time) / span, 0, 1) else 1
	local a = TweenService:GetValue(u, k2.ease or Enum.EasingStyle.Cubic, k2.dir or Enum.EasingDirection.InOut)
	local p1, p2 = c1.Position, c2.Position
	local p0 = if i > 1 and not k1.cut then poseAt(keys[i - 1], subject).Position else p1 + (p1 - p2)
	local k3 = keys[i + 2]
	local p3 = if k3 and not k3.cut then poseAt(k3, subject).Position else p2 + (p2 - p1)
	local eye = catmullRom(p0, p1, p2, p3, a)
	local fov = fovs[i] + (fovs[i + 1] - fovs[i]) * a
	local look1, look2 = k1.lookAt, k2.lookAt
	if look1 and look2 and not k1.cframe and not k2.cframe then
		return aim(eye, point(look1, subject):Lerp(point(look2, subject), a)), fov
	end
	return CFrame.new(eye) * c1.Rotation:Lerp(c2.Rotation, a), fov
end

-- Borrowing the camera and the HUD ------------------------------------------------------------

local function remember(instance: Instance, property: string, value: any)
	local key = PRIOR_PREFIX .. property
	if instance:GetAttribute(key) == nil then
		instance:SetAttribute(key, if typeof(value) == "EnumItem" then value.Name else value)
	end
end

local function restoreCamera(camera: Camera)
	local cameraType = camera:GetAttribute(PRIOR_PREFIX .. "CameraType")
	local fov = camera:GetAttribute(PRIOR_PREFIX .. "FieldOfView")
	if type(cameraType) == "string" then
		pcall(function()
			camera.CameraType = (Enum.CameraType :: any)[cameraType]
		end)
	end
	if type(fov) == "number" then
		camera.FieldOfView = fov
	end
	local subject = savedSubject
	savedSubject = nil
	if subject and subject.Parent then
		camera.CameraSubject = subject
	end
	camera:SetAttribute(PRIOR_PREFIX .. "CameraType", nil)
	camera:SetAttribute(PRIOR_PREFIX .. "FieldOfView", nil)
end

-- Hides (true) or restores (false) the local player's enabled ScreenGuis, recording
-- each one it touches. Also useful on its own for clean captures.
function CameraPath.hideGuis(hidden: boolean)
	local player = Players.LocalPlayer
	local gui = player and player:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return
	end
	for _, child in gui:GetChildren() do
		if not child:IsA("ScreenGui") then
			continue
		end
		if hidden and child.Enabled and child:GetAttribute(OWNED_ATTR) == nil then
			remember(child, "Enabled", true)
			child:SetAttribute(OWNED_ATTR, true)
			child.Enabled = false
		elseif not hidden and child:GetAttribute(OWNED_ATTR) == true then
			local prior = child:GetAttribute(PRIOR_PREFIX .. "Enabled")
			child.Enabled = if type(prior) == "boolean" then prior else true
			child:SetAttribute(PRIOR_PREFIX .. "Enabled", nil)
			child:SetAttribute(OWNED_ATTR, nil)
		end
	end
end

-- Playing ---------------------------------------------------------------------------------------

local function defaultSubject(): CFrame?
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.CFrame else nil
end

local function unbind()
	if bound then
		bound = false
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end
end

-- Ends the shot: restore the camera, then (when completed) ease out of the last pose.
local function finish(shot: Active, completed: boolean)
	if active ~= shot then
		return
	end
	active = nil
	local camera = Workspace.CurrentCamera
	local seconds = shot.options.blendBack or 0.35
	if camera then
		restoreCamera(camera)
		if completed and seconds > 0 then
			blend = { from = lastPose, fov = lastFov, target = camera.FieldOfView, started = os.clock(), seconds = seconds }
		end
	end
	if not blend then
		unbind()
	end
	CameraPath.hideGuis(false) -- unconditional: an earlier shot of a chain may have hidden it
	local done = shot.options.onFinished
	if done then
		task.spawn(done, completed)
	end
end

local function stepBlend(camera: Camera, b: Blend)
	local u = (os.clock() - b.started) / b.seconds
	if u >= 1 then
		camera.FieldOfView = b.target
		blend = nil
		unbind()
		return
	end
	local a = TweenService:GetValue(u, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
	camera.CFrame = b.from:Lerp(camera.CFrame, a)
	camera.FieldOfView = b.fov + (b.target - b.fov) * a
end

local function render()
	local camera = Workspace.CurrentCamera
	local shot = active
	if not camera then
		return
	elseif not shot then
		local b = blend
		if b then
			stepBlend(camera, b)
		else
			unbind()
		end
		return
	end
	local getSubject: () -> CFrame? = shot.options.subject or defaultSubject
	shot.subject = getSubject() or shot.subject
	local t = math.min(os.clock() - shot.started, shot.track.duration)
	local ok, pose, fov = pcall(CameraPath.evaluate, shot.track, shot.subject, t)
	if not ok then
		warn(("CameraPath: shot stopped: %s"):format(tostring(pose)))
		finish(shot, false)
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame, camera.FieldOfView = pose, fov
	lastPose, lastFov = pose, fov
	if t >= shot.track.duration then
		finish(shot, true)
	end
end

-- Plays a shot from the camera's current pose, replacing any shot already playing.
function CameraPath.play(shot: Shot, opts: PlayOptions?): Handle
	assert(CameraPath.valid(shot), "CameraPath.play: invalid shot (see CameraPath.valid)")
	local camera = Workspace.CurrentCamera
	assert(camera, "CameraPath.play: no CurrentCamera")
	local options: PlayOptions = opts or {}
	local previous = active
	active = nil -- chained: keep the recorded priors and the hidden HUD
	if previous and previous.options.onFinished then
		task.spawn(previous.options.onFinished, false)
	end
	blend = nil
	remember(camera, "CameraType", camera.CameraType)
	remember(camera, "FieldOfView", camera.FieldOfView)
	savedSubject = savedSubject or camera.CameraSubject
	if options.hideGuis then
		CameraPath.hideGuis(true)
	end
	local getSubject: () -> CFrame? = options.subject or defaultSubject
	local shotState: Active = {
		track = CameraPath.prepare(shot, camera.CFrame, camera.FieldOfView),
		started = os.clock(),
		subject = getSubject() or camera.CFrame,
		options = options,
	}
	active = shotState
	if not bound then
		bound = true
		RunService:BindToRenderStep(RENDER_NAME, options.priority or Enum.RenderPriority.Camera.Value + 1, render)
	end
	return {
		cancel = function()
			finish(shotState, false)
		end,
		isPlaying = function(): boolean
			return active == shotState
		end,
	}
end

-- Stops any shot or blend now and hands the camera and HUD back. Idempotent;
-- returns true when there was something to stop or restore.
function CameraPath.stop(): boolean
	local shot = active
	if shot then
		finish(shot, false)
	end
	local hadBlend = blend ~= nil
	blend = nil
	unbind()
	local camera = Workspace.CurrentCamera
	local borrowed = false
	if camera and camera:GetAttribute(PRIOR_PREFIX .. "CameraType") ~= nil then
		borrowed = true
		restoreCamera(camera)
	end
	CameraPath.hideGuis(false)
	return shot ~= nil or hadBlend or borrowed
end

function CameraPath.isPlaying(): boolean
	return active ~= nil
end

return CameraPath
