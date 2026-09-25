local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local path = process.args[1] or "plugins/forgegui-roblox-builder/skills/forgegui-roblox-builder/references/luau/CameraPath.luau"
local now, callback = 0, nil
local attributes = {}
local camera = { CFrame = roblox.CFrame.identity, FieldOfView = 83, CameraType = roblox.Enum.CameraType.Custom }
function camera:GetAttribute(name) return attributes[name] end
function camera:SetAttribute(name, value) attributes[name] = value end
local services = {
	Workspace = { CurrentCamera = camera },
	Players = {},
	RunService = {
		BindToRenderStep = function(_, _, _, fn) callback = fn end,
		UnbindFromRenderStep = function() callback = nil end,
	},
	TweenService = { GetValue = function(_, u) return 1 - (1 - u)^3 end },
}
local module = luau.load(fs.readFile(path), { environment = {
	game = { GetService = function(_, name) return services[name] end },
	CFrame = roblox.CFrame, Vector3 = roblox.Vector3, Enum = roblox.Enum,
	os = { clock = function() return now end }, task = { spawn = function(fn, ...) fn(...) end },
} })()
local checks = 0
local function check(value, label)
	assert(value, label)
	checks += 1
end
for _, fraction in { 0, 0.25, 0.75, 1 } do
	camera.FieldOfView = 83
	local finished = 0
	module.play({ { time = 0, cframe = roblox.CFrame.identity, fov = 35 } }, {
		blendBack = 4,
		onFinished = function(completed) check(completed, "shot completes naturally"); finished += 1 end,
	})
	callback()
	check(camera:GetAttribute("ForgeGUIPrior_FieldOfView") == nil, "finish removes saved FOV")
	now += 4 * fraction
	callback()
	if fraction < 1 then
		check(camera.FieldOfView < 83, "return blend has changed FOV")
		check(module.stop(), "stop reports interrupted blend")
	else
		check(not module.stop(), "completed blend has nothing to stop")
	end
	check(camera.FieldOfView == 83, "stop restores original FOV")
	check(callback == nil, "render binding removed")
	check(finished == 1, "stop does not repeat completion callback")
	check(not module.stop(), "second stop is idempotent")
	check(next(attributes) == nil, "no prior attributes remain")
end
module.play({ { time = 10, cframe = roblox.CFrame.identity, fov = 35 } })
now += 1
callback()
check(module.stop() and camera.FieldOfView == 83, "active shot still restores FOV")
check(not module.stop(), "active shot cleanup is idempotent")
print(`camera path blend: {checks} checks passed`)
