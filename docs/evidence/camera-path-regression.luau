-- Appended to the reviewed CameraPath source in place of its final `return CameraPath`:
--   python plugins/forgegui-roblox-builder/skills/forgegui-roblox-builder/references/tools/paste_module.py \
--     plugins/forgegui-roblox-builder/skills/forgegui-roblox-builder/references/luau/CameraPath.luau \
--     docs/evidence/camera-path-regression.luau > paste.luau
--
-- Part 1 (anywhere, Edit mode included): validation, track preparation and the
-- path maths (keys are hit exactly, cuts hold, look-at keys aim at their target).
-- Part 2 (only on a client with a character, i.e. in Play): play() takes the camera
-- and stop() hands CameraType, FieldOfView and the hidden HUD back; stop() is
-- idempotent. Part 2 reports itself skipped elsewhere rather than passing silently.
local checks = {}

local function check(condition: boolean, label: string)
	assert(condition, label)
	table.insert(checks, label)
end

local function close(a: Vector3, b: Vector3, label: string)
	check((a - b).Magnitude < 1e-3, `{label} (expected {b}, got {a})`)
end

-- Part 2 body: play() borrows the camera and HUD, stop() hands them back.
local function borrowCamera(player: Player, camera: Camera, target: Vector3)
	local typeBefore, fovBefore = camera.CameraType, camera.FieldOfView
	local lift = camera.CFrame.Position + Vector3.new(0, 20, 0)
	local handle = CameraPath.play({ { time = 5, position = lift, lookAt = target, fov = 40 } }, { hideGuis = true })
	check(handle.isPlaying() and CameraPath.isPlaying(), "play starts a shot")
	check(camera:GetAttribute("ForgeGUIPrior_CameraType") == typeBefore.Name, "the prior CameraType is recorded")
	check(camera:GetAttribute("ForgeGUIPrior_FieldOfView") == fovBefore, "the prior FieldOfView is recorded")
	check(CameraPath.stop() == true, "stop reports it had something to do")
	check(camera.CameraType == typeBefore and camera.FieldOfView == fovBefore, "stop restores CameraType and FieldOfView")
	check(camera:GetAttribute("ForgeGUIPrior_CameraType") == nil, "stop removes the camera priors")
	for _, gui in player:WaitForChild("PlayerGui"):GetChildren() do
		check(gui:GetAttribute("ForgeGUICameraPath") == nil, "no ScreenGui is left hidden: " .. gui.Name)
	end
	check(not handle.isPlaying() and CameraPath.stop() == false, "a second stop reports nothing to do")

	-- A chain: the first shot hides the HUD, the second does not ask; its natural end still restores it.
	CameraPath.play({ { time = 5, position = lift, lookAt = target } }, { hideGuis = true })
	local finished = false
	CameraPath.play({ { time = 0.2, position = lift, lookAt = target } }, { blendBack = 0, onFinished = function()
		finished = true
	end })
	local deadline = os.clock() + 3
	while not finished and os.clock() < deadline do
		task.wait()
	end
	check(finished, "the chained shot finishes on its own")
	check(camera.CameraType == typeBefore, "the chain's end restores CameraType")
	for _, gui in player:WaitForChild("PlayerGui"):GetChildren() do
		check(gui:GetAttribute("ForgeGUICameraPath") == nil, "no ScreenGui is left hidden after a chain: " .. gui.Name)
	end
end

local ok, failure = xpcall(function()
	-- Part 1: maths.
	local target = Vector3.new(0, 0, 0)
	local shot: Shot = {
		{ time = 1, position = Vector3.new(10, 0, 0), lookAt = target, fov = 50 },
		{ time = 2, cframe = CFrame.new(20, 5, 0) },
		{ time = 3, position = Vector3.new(0, 10, 10), lookAt = target, cut = true },
	}
	check(CameraPath.valid(shot), "a well-formed shot is valid")
	check(not CameraPath.valid({}), "an empty shot is invalid")
	check(not CameraPath.valid({ { time = 1 } }), "a key without a pose is invalid")
	check(not CameraPath.valid({ { time = 2, cframe = CFrame.new() }, { time = 1, cframe = CFrame.new() } }), "keys out of order are invalid")
	check(not CameraPath.valid({ { time = CameraPath.MAX_SECONDS + 1, cframe = CFrame.new() } }), "an overlong shot is invalid")

	local from = CFrame.new(0, 0, -10)
	local track = CameraPath.prepare(shot, from, 70)
	check(#track.keys == 4 and track.duration == 3, "a start pose becomes key 0")
	check(#shot == 3, "prepare leaves the caller's shot alone")
	local subject = CFrame.new()
	local p0, f0 = CameraPath.evaluate(track, subject, 0)
	close(p0.Position, from.Position, "t = 0 is the start pose")
	check(f0 == 70, "t = 0 keeps the start FOV")
	local p1, f1 = CameraPath.evaluate(track, subject, 1)
	close(p1.Position, Vector3.new(10, 0, 0), "a key's position is hit exactly")
	check(f1 == 50, "a key's FOV is hit exactly")
	close(p1.LookVector, (target - Vector3.new(10, 0, 0)).Unit, "a look-at key aims at its target")
	local _, fHalf = CameraPath.evaluate(track, subject, 0.5)
	check(fHalf > 50 and fHalf < 70, "the FOV eases between keys")
	local hold = CameraPath.evaluate(track, subject, 2.5)
	close(hold.Position, Vector3.new(20, 5, 0), "a cut holds the previous pose until its time")
	local last = CameraPath.evaluate(track, subject, 3)
	close(last.Position, Vector3.new(0, 10, 10), "the cut lands on its key")
	local follow = CameraPath.prepare({ { time = 1, cframe = function(s: CFrame): CFrame
		return s * CFrame.new(0, 0, 5)
	end } }, from, 70)
	close(CameraPath.evaluate(follow, CFrame.new(100, 0, 0), 1).Position, Vector3.new(100, 0, 5), "a function key follows the live subject")

	-- Part 2: borrowing the camera (client with a character only).
	local player = game:GetService("Players").LocalPlayer
	local camera = Workspace.CurrentCamera
	if not (player and player.Character and camera) then
		print("camera path regression: part 2 skipped (needs a client with a character, run in Play)")
	else
		borrowCamera(player, camera, target)
	end
end, debug.traceback)

CameraPath.stop()

if not ok then
	error(`camera path regression failed after {#checks} checks:\n{failure}`)
end
print(`camera path regression: {#checks} checks passed`)
