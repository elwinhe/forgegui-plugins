# Combined lighting and camera setup

Install the shipped Luau files as sibling ModuleScripts under one folder, `ReplicatedStorage.ForgeGUIPostStack`. **ColourGrade and GlobalIllumination both require the same sibling LightingCompositor**, even when only one feature is used. Do not install separate compositor copies per feature or evaluate each module in an isolated MCP require environment. Normal LocalScript `require` caches the shared ModuleScript.

Install CameraFx, FrameSmoothing, ColourGrade, EyeAdaptation, GraphicsPreset, LutGrades, GlobalIllumination and LightingCompositor for this example. Install ContactShadows, FireLight, WaterReflections and PassageShade as needed; their setup remains in [light transport](light-transport.md). LUT fitting, graphics settings and camera details remain in [post-processing](post-processing.md).

Apply LightingPresets and then SkyboxPresets in Edit mode or on the server for the place baseline. SkyboxPresets uses ServerStorage to preserve original skies and must not run from a production LocalScript. Use the updated preset sources, which recognize the compositor's base when used in the same execution context. Server preset changes replicate as external base updates on each client; client compositor attributes do not replicate back to the server.

Start the runtime stack from **one LocalScript** in StarterPlayerScripts:

```lua
local root = game:GetService("ReplicatedStorage"):WaitForChild("ForgeGUIPostStack")
local GI = require(root.GlobalIllumination)
local Grade = require(root.ColourGrade)
local CameraFx = require(root.CameraFx)
local Smoothing = require(root.FrameSmoothing)
local Eye = require(root.EyeAdaptation)
local Graphics = require(root.GraphicsPreset)
local Luts = require(root.LutGrades)

GI.start({ level = 1 })
Grade.start({
    grades = Luts.grades,
    keyframes = {
        { clock = 6, grade = "golden_hour" },
        { clock = 12, grade = "neutral" },
        { clock = 20, grade = "moonlight" },
    },
})
CameraFx.start()
Smoothing.start({ level = 0.5 })
Eye.start()
Graphics.start({
    preset = "Auto",
    onPreset = function(_, values)
        CameraFx.setMotionBlur(values.motionBlur)
        CameraFx.setFrameBlending(values.frameBlending)
        CameraFx.setDepthOfField(values.depthOfField)
        Smoothing.setLevel(values.frameSmoothing)
    end,
})

local function stop()
    Graphics.stop()
    Smoothing.stop()
    CameraFx.stop()
    Grade.stop()
    GI.stop() -- GI and Grade may stop in either order
    Eye.stop()
end
script.Destroying:Connect(stop)
```

Only LightingCompositor writes Ambient, OutdoorAmbient, ColorShift_Top and ColorShift_Bottom for GI/Grade. Every update recomposes **base → GI → grade**, regardless of which module started or updated first. GI samples ungraded sun colour and smooths probe colour/openness; it never smooths a previously graded output back into its base. GI level Off removes its colour layer immediately (bounce lights still fade); Grade strength Off removes split toning on the next grade step. Stopping one layer recomposes the other; stopping both restores the latest base.

Occasional preset/day-night writes are recognized on the next composition, including stop. The compositor compares against actual engine readback, handling Color3 quantization without a tolerance that discards small external edits. Polling cannot distinguish an external write equal to its last output. For those writes, and for continuous day/night updates, use `LightingCompositor.setBase({ Ambient = ..., OutdoorAmbient = ..., ColorShift_Top = ..., ColorShift_Bottom = ... })` with any subset of those keys. It rejects other properties and non-Color3 values. Or provide GI `getBase = function() return { ambient = ..., outdoor = ..., bottom = ... } end`. Supply raw colours, never the current composed Lighting values; stop the competing direct writer. Callback errors propagate to the caller.

Preset prior prefixes remain independent. Apply LightingPresets then SkyboxPresets; clear SkyboxPresets then LightingPresets. When capturing an active compositor output, presets save its unlayered base. They still work without the compositor installed. Runtime modules do not clear preset records. Stop the live runtime stack before replacing/reloading ModuleScripts: isolated fresh module instances cannot recover the live layer state.

CameraFx restores the old view's adopted DoF on CurrentCamera changes, including a nil transition, and adopts Lighting's DoF first, then the new camera's, or creates its own. Motion and frame history reset on camera changes. Foreign effects are never destroyed. Stop restores all borrowed properties even if the old camera was retained or destroyed; owned effects are removed.

## Verification

The runners below live in the source repository, not the installed skill. First check out the source revision matching your installed plugin (use its release tag or commit as `<installed-revision>`):

```bash
git clone https://github.com/elwinhe/forgegui-plugins.git forgegui-regression
cd forgegui-regression
git checkout --detach <installed-revision>
```

All runner paths below are relative to that checkout. Use its `docs/evidence/post-stack-regression.luau`, `docs/evidence/light-transport-regression.luau`, and `docs/evidence/unified-lighting-regression.luau` with the matching module sources. Do not substitute the latest default branch for an older installed release.

- Offline: `lune run tests/unified-lighting.luau` (Lune 0.10.5). It loads actual module sources with mocked services and quantized Lighting writes, checks both start/stop orders, 160 stable alternating updates per ordering, off/on, repeated lifecycle, external edits, getBase, preset/sky clear, and retained/destroyed/nil camera transitions. It also compiles every shipped Luau source. It is not a Roblox typecheck or a rendering test.
- Studio: in a disposable owned test place, install all sources as siblings and stop the normal stack. Run `docs/evidence/unified-lighting-regression.luau` from a Play client LocalScript. It exercises both modules together and camera swaps. Run the original post-stack and light-transport regressions too using their updated dependency instructions. The combined client test does not invoke SkyboxPresets (ServerStorage boundary); the offline test covers its ownership logic.
- Then inspect real rendering: orbit, respawn, switch cameras, walk between outdoor/interior areas, change presets and grade/GI settings, and verify teardown. Capture matched views and measure frame times; Lune cannot verify engine effect stacking, raycast visuals, camera destruction timing, replication or performance. Historical measurements in the feature guides are not validation of this integration.

No live Studio result is claimed by the offline tests.
