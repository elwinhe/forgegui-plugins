-- Run as a Play client LocalScript in a disposable test place with normal stack stopped.
-- Install sources together under ReplicatedStorage.ForgeGUIPostStack.
-- No live Studio execution is implied by this file.
local root = game:GetService("ReplicatedStorage"):WaitForChild("ForgeGUIPostStack")
local L = game:GetService("Lighting")
local W = game:GetService("Workspace")
local G, GI, Fx = require(root.ColourGrade), require(root.GlobalIllumination), require(root.CameraFx)
local C = require(root.LightingCompositor)
local props = { "Ambient", "OutdoorAmbient", "ColorShift_Top", "ColorShift_Bottom" }
local saved, attributes = {}, L:GetAttributes()
for _, p in props do saved[p] = L[p] end
local oldCamera = W.CurrentCamera
local cameras, parked = {}, {}
for _, child in L:GetChildren() do
    if child:IsA("DepthOfFieldEffect") then
        table.insert(parked, child)
        child.Parent = nil
    end
end
local checks = 0
local function check(ok, label) assert(ok, label); checks += 1 end
local function near(a, b)
    return math.abs(a.R-b.R) < 0.005 and math.abs(a.G-b.G) < 0.005 and math.abs(a.B-b.B) < 0.005
end
local function snapshot()
    local values = {}
    for _, p in props do values[p] = L[p] end
    return values
end
local function same(values, expected, label)
    for _, p in props do check(near(values[p], expected[p]), label .. " " .. p) end
end
local function camera()
    local c = Instance.new("Camera")
    c.CameraType = Enum.CameraType.Scriptable
    c.CFrame, c.Focus = CFrame.new(0, 100000, 12), CFrame.new(0, 100000, 0)
    c.Parent = W
    table.insert(cameras, c)
    return c
end
local function foreign(parent)
    local d = Instance.new("DepthOfFieldEffect")
    d.FocusDistance, d.FarIntensity, d.Enabled = 33, 0.24, false
    d.Parent = parent
    return d
end
local function startGrade()
    G.start({ keyframes = { { clock = 0, grade = {
        exposure = 0, contrast = 0, saturation = 0, brightness = 0,
        tint = Color3.new(1,1,1), shadowTint = Color3.new(0.5,0.8,1), highlightTint = Color3.new(1,0.7,0.5),
    } } } })
    G.step()
end
local function startGI()
    GI.start({ manual = true, level = 1, getFocus = function() return Vector3.new(0,100000,0) end })
    GI.step(0.1)
end
local ok, failure = xpcall(function()
    W.CurrentCamera = camera()
    local baseline = {
        Ambient = Color3.fromRGB(60,70,80), OutdoorAmbient = Color3.fromRGB(100,110,120),
        ColorShift_Top = Color3.fromRGB(180,150,120), ColorShift_Bottom = Color3.fromRGB(70,60,50),
    }
    local stable
    for _, gradeFirst in { true, false } do
        for _, gradeStopsFirst in { true, false } do
            for p, v in baseline do L[p] = v end
            if gradeFirst then startGrade(); startGI() else startGI(); startGrade() end
            local expected = snapshot()
            if stable then same(expected, stable, "start order") else stable = expected end
            for i = 1, 160 do
                if i % 2 == 0 then G.step(); GI.step(0.1) else GI.step(0.1); G.step() end
                same(snapshot(), expected, "no compounding")
            end
            local external = Color3.fromRGB(30,40,50)
            L.Ambient = external
            G.step(); GI.step(0.1)
            check(near(C.getBase().Ambient, external), "external base")
            GI.setLevel(0); G.setStrength(0); G.step()
            check(near(L.Ambient, external), "off preserves base")
            GI.setLevel(1); G.setStrength(1); GI.step(0.1); G.step()
            if gradeStopsFirst then
                G.stop()
                local remaining = snapshot()
                GI.step(0.1); same(snapshot(), remaining, "GI survives grade stop")
                GI.stop()
            else
                GI.stop()
                local remaining = snapshot()
                G.step(); same(snapshot(), remaining, "grade survives GI stop")
                G.stop()
            end
            local restored = table.clone(baseline); restored.Ambient = external
            same(snapshot(), restored, "both stop")
            G.stop(); GI.stop(); same(snapshot(), restored, "repeated stop")
        end
    end
    for _, destroyOld in { false, true } do
        local a, b = camera(), camera()
        local old, nextDof = foreign(a), foreign(b)
        W.CurrentCamera = a
        Fx.start()
        Fx.step(a, 1/60)
        for i = 1, 10 do
            a.CFrame *= CFrame.Angles(0, 0.02, 0)
            Fx.step(a, 1/60)
        end
        check(Fx.motion() > 0, "motion accumulated")
        if destroyOld then a:Destroy() end
        Fx.step(nil, 1/60) -- exercise nil even if engine auto-selects another camera
        check(math.abs(old.FocusDistance-33) < 0.001, "old borrowed focus restored")
        W.CurrentCamera = b
        Fx.step(b, 1/60)
        check(Fx.effect() == nextDof, "new camera adopted")
        local far, nearMotion = Fx.motion()
        check(far == 0 and nearMotion == 0, "history reset")
        Fx.stop()
        check(nextDof.Parent == b and math.abs(nextDof.FocusDistance-33) < 0.001, "foreign survives stop")
    end
    local a, b = camera(), camera()
    local global = foreign(L)
    W.CurrentCamera = a
    Fx.start(); Fx.step(a, 1/60)
    W.CurrentCamera = b; Fx.step(b, 1/60)
    check(Fx.effect() == global, "Lighting effect re-adopted")
    Fx.stop()
    check(global.Parent == L and math.abs(global.FocusDistance-33) < 0.001, "Lighting effect restored")
    global:Destroy()
end, debug.traceback)
Fx.stop(); G.stop(); GI.stop()
W.CurrentCamera = oldCamera
for _, c in cameras do c:Destroy() end
for _, child in parked do child.Parent = L end
for p, value in saved do L[p] = value end
for key in L:GetAttributes() do
    if attributes[key] == nil then L:SetAttribute(key, nil) end
end
for key, value in attributes do L:SetAttribute(key, value) end
assert(ok, failure)
print("PASS combined Studio regression: " .. checks .. " checks")
