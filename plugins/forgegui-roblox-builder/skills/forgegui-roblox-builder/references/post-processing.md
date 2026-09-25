# Camera and post-processing stack

Five client modules that give a Roblox game the camera feel and grade of a modern engine: camera motion blur, frame blending, frame smoothing, a LUT colour grade blended by time of day, eye adaptation and a resting depth of field, plus a graphics preset that picks their levels from measured frame time. Code in `luau/CameraFx.luau`, `luau/FrameSmoothing.luau`, `luau/ColourGrade.luau`, `luau/EyeAdaptation.luau` and `luau/GraphicsPreset.luau`; LUT fitting in `tools/lut_fit.py`, example looks in `tools/make_luts.py`, their fitted output in `luau/LutGrades.luau`.

Reach for it when the game has a third-person or orbiting camera and the brief asks for a cinematic, "Unreal", photoreal or film look, or when a lighting preset alone reads flat. It sits on top of `lighting-presets.md`, it does not replace it: apply the preset for the place's light, then start this stack on the client. Skip it for UI-only games, 2D games and showcase/thumbnail scenes (motion blur and eye adaptation work against a static product shot).

All five are LocalScript modules. Nothing here runs on the server, downloads code or inserts assets.

Install the shared sibling `LightingCompositor` even when using ColourGrade alone. For GI plus post-processing, use [the combined setup](unified-lighting.md).

## Wiring

```lua
-- StarterPlayerScripts/PostStack.client.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Post = ReplicatedStorage:WaitForChild("ForgeGUIPostStack")
local CameraFx = require(Post.CameraFx)
local FrameSmoothing = require(Post.FrameSmoothing)
local ColourGrade = require(Post.ColourGrade)
local EyeAdaptation = require(Post.EyeAdaptation)
local GraphicsPreset = require(Post.GraphicsPreset)
local LutGrades = require(Post.LutGrades)

CameraFx.start({
	isSuppressed = function() return menuOpen end, -- your modal / pause flag
	cinematic = function() return cutsceneSubject end, -- a Vector3 while a shot runs, else nil
})
FrameSmoothing.start({ level = 0.5 })
ColourGrade.start({
	grades = LutGrades.grades,
	keyframes = {
		{ clock = 6.5, grade = "golden_hour" },
		{ clock = 11, grade = "neutral" },
		{ clock = 17.5, grade = "golden_hour" },
		{ clock = 20.5, grade = "moonlight" },
	},
	strength = 1,
})
EyeAdaptation.start({ ignore = function() return { workspace.Enemies } end })
GraphicsPreset.start({
	preset = "Auto",
	isReady = function() return game.Players.LocalPlayer.Character ~= nil end,
	onPreset = function(level, v)
		CameraFx.setMotionBlur(v.motionBlur :: number)
		CameraFx.setFrameBlending(v.frameBlending :: number)
		CameraFx.setDepthOfField(v.depthOfField :: boolean)
		FrameSmoothing.setLevel(v.frameSmoothing :: number)
	end,
})
```

Every module has an idempotent `start(options)` (a second call only updates options) and `stop()`. The setters (`setMotionBlur`, `setFrameBlending`, `setDepthOfField`, `FrameSmoothing.setLevel`, `ColourGrade.setStrength`, `ColourGrade.setKeyframes`, `EyeAdaptation.setEnabled`, `GraphicsPreset.setPreset`) are what a settings panel calls. Each module also exposes its frame function (`CameraFx.step`, `FrameSmoothing.smooth`, `ColourGrade.step`, `EyeAdaptation.step`) and its pure maths for tests.

### Frame order

| Priority | Module | Why there |
| --- | --- | --- |
| `Camera - 1` | FrameSmoothing restore | hands the camera module its own last output before it runs |
| `Camera` | Roblox camera module | unchanged |
| `Camera + 1` | FrameSmoothing smooth | reads the module's new output, writes the eased picture |
| `Last` | CameraFx | reads the final camera for this frame, after every other camera writer |
| `Last + 1` | FrameSmoothing watch | notes where the frame ended, to detect scripts that place the camera |
| RenderStepped | EyeAdaptation | 5 view rays a frame |
| Heartbeat, every 0.1 s | ColourGrade | the grade changes over minutes, not frames |

## Recommended settings panel

The UI is yours; these are the rows, values and defaults that held up in play. Store "Off / Low / High" rows as numbers 0 / 0.5 / 1 so a slider and a three-way choice read the same value.

| Row | Choices | Default | Calls | Set by the preset |
| --- | --- | --- | --- | --- |
| Motion blur | 0–100 % | 50 % (Unreal's default Amount 0.5) | `CameraFx.setMotionBlur(0..1)` | yes (Low: 0) |
| Frame blending | Off / Low / High (1 / 3 / 6 frames) | Low | `CameraFx.setFrameBlending(0 / 0.5 / 1)` | yes (Low: Off) |
| Frame smoothing | Off / Low / High (0 / 18 / 40 ms) | Low | `FrameSmoothing.setLevel(0 / 0.5 / 1)` | yes |
| Depth of field | On / Off | On | `CameraFx.setDepthOfField(bool)` | yes (Low: Off) |
| Colour grade | Off / Natural / Cinematic (0 / 55 / 100 % of the grade) | Cinematic | `ColourGrade.setStrength(0 / 0.5 / 1)` | no |
| Eye adaptation | On / Off | On | `EyeAdaptation.setEnabled(bool)` | no |
| Graphics preset | Auto / Low / Medium / High, shows Custom | Auto | `GraphicsPreset.setPreset(...)` | — |

- Changing any row the preset sets switches the preset to Custom (`setPreset("Custom")`), and the preset then leaves every option alone. Choosing Auto again re-measures.
- Motion blur Off is `setMotionBlur(0)`, not a separate switch; there is no dead zone to tune.
- Eye adaptation Off still applies the colour grade's exposure (see Ownership); the adaptation eases back to 0 instead of snapping.
- Offer the panel from the pause menu as well as the main menu: people turn motion blur off the first time they whip the camera.

`GraphicsPreset.LEVELS` holds the per-level tables for the rows above. Add your game's heavier options (reflections, shadowed lights, clouds) to the same tables and handle them in `onPreset`; that is where levels actually buy frame time.

## Ownership: who writes what

Every module follows the `LightingPresets.luau` convention (owned tag, prior-value attributes, destroy only what is tagged), with its own attribute names so no module's `clear`/`stop` touches another's records.

| Property or instance | Writer | How it composes |
| --- | --- | --- |
| Preset `ColorCorrectionEffect` in Lighting | LightingPresets | static look for the place |
| `ForgeGUI_ColourGrade` ColorCorrectionEffect under the camera, tag `ForgeGUIColourGrade` | ColourGrade | Roblox adds C, S, B and multiplies tints of every CC in view, so the grade stacks on the preset's CC by the engine's own rule. It lives under the camera so LightingPresets (which scans Lighting) never adopts it. |
| `Lighting.Ambient`, `OutdoorAmbient`, `ColorShift_Top` | LightingCompositor | Unlayered base → GI → ColourGrade; shared with `ColorShift_Bottom`. Preset priors contain the unlayered base |
| `Lighting.ExposureCompensation` | LightingPresets / day-night, then EyeAdaptation only | EyeAdaptation writes base + `ForgeGUIGradeExposure` (the attribute ColourGrade publishes) + `extraExposure()` + adaptation; prior `ForgeGUIEyeAdaptationPrior_ExposureCompensation` |
| The one `DepthOfFieldEffect` | CameraFx | adopts the place's (tag `ForgeGUICameraFxAdopted`, priors `ForgeGUICameraFxPrior_*`) or creates `ForgeGUI_CameraFx` under the camera (tag `ForgeGUICameraFx`) |

Rules the modules keep, so none of them fight:

- **Follow, never fight.** A borrowed property is a layer: when its value is not what the module last wrote, someone else wrote it, and that value becomes the new base. A preset applied mid-run, or a day/night script, keeps working; `stop()` puts back the latest external value, not a stale snapshot.
- **One writer per property.** ColourGrade never writes ExposureCompensation; it publishes the Lighting attribute `ForgeGUIGradeExposure`, which EyeAdaptation adds. Two layers on one property would each read the other's write as "external" and compound every frame. If you do not want auto-exposure, run EyeAdaptation with `enabled = false`: it still applies the grade's exposure.
- **Priors survive composition.** LightingPresets and SkyboxPresets capture the compositor base when borrowing its current output. Their separate prior prefixes and reverse clear order remain unchanged. CameraFx and EyeAdaptation correct effect/exposure priors when detecting an external write.
- **Order that needs no correction:** apply the lighting preset, then start the stack; stop the stack, then clear the preset. The regression covers the mid-run case too.
- **Stale sessions.** Effect modules sweep their own tagged instances in Lighting and the current camera. Shared colour state requires the same cached compositor ModuleScript: stop the live modules before replacing/reloading it. A fresh isolated require cannot recover the live compositor state.

`LightingPresets.luau` now captures unlayered colour baselines from the compositor. Its presets set `depthOfField` (mostly `Enabled = false`); CameraFx restores a borrowed effect on camera replacement (including nil gaps), resets its motion history, then adopts the current view's effect or creates one. With CameraFx running the DoF is driven every frame, so the preset's DoF values only return when CameraFx stops. `dungeon_torchlit` wants a resting DoF on: CameraFx's resting DoF replaces it.

## Measured Roblox facts behind it

Measured in Studio during a 2026-09 build; numbers, not impressions.

- **ColorCorrectionEffect acts in display space**, in this order, clamping only at the end: contrast `(x − 0.5)(1 + C) + 0.5`, then saturation around a luma with weights W = (0.34, 0.548, 0.112), then `+ B`, then `× tint`.
- **Several ColorCorrectionEffects do not chain.** Roblox adds their C, S and B and multiplies their tints, so the whole grade is effectively one CC. A curve cannot be built by stacking effects, and split toning (shadows and highlights tinted apart) cannot be done in a CC at all: it goes into the lights (ambients carry the shadow tone, `ColorShift_Top` the highlight tone).
- **ExposureCompensation acts before a filmic tone curve.** Linear scene value → displayed: 0.1 → 0.32, 0.5 → 0.73, 1.0 → 0.9, ≥ 3 → 1.0 (full table in `lut_fit.py`, `TONE_POINTS`). So exposure is the only way to move pixels along a curve, and the fitter uses it as the curve parameter.
- **No LUT support, no velocity buffer.** Hence the offline LUT fit and the depth-of-field motion blur.
- **Motion blur on a depth of field.** For a camera orbiting a pivot f studs away at ω rad/s, a point at depth d moves across the screen at ω·|1 − f/d|: zero at the pivot, growing in front and behind, which is the shape of a DoF focused on the pivot. Smear = amount × screen speed / (30 × horizontal FOV), capped at 5 % of the screen (Unreal's `r.MotionBlur` defaults), mapped to DoF intensity 0.9 at the cap.
- **Frame time with the full stack on High:** ~6 ms median in an open area with ~60 close-up ground meshes, ~11 ms median in a dense town. Auto thresholds: 90th percentile < 18 ms → High (holds 60 fps), < 26 ms → Medium, else Low; a steady 22 ms average for 10 s steps down one level, at most once a minute.
- **LUT fit quality.** Fitting to exposure + one CC leaves 5–10 levels RMS (of 255) on real grades: moonlight 5.3, neon night 8.4, golden hour 8.9, overcast 9.2 (`make_luts.py` looks at 33³). The split-tone residuals carry most of the rest.

## What was tried and did not work

- **A full-screen `BlurEffect` for motion blur.** It blurs the subject along with the world and reads as a smudged lens. Replaced by the DoF model above, which keeps the orbit pivot sharp.
- **Stacking ColorCorrectionEffects to shape a curve** (one for shadows, one for highlights). They merge into one CC, so the second only shifted the first.
- **Writing a smoothed `Camera.CFrame` directly.** The camera module reads CFrame back next frame, so the smoothing fed into itself: drift and a heavy mouse. The restore-before-camera-module trick fixes it.
- **Fitted split tones straight into the lights.** A fitting artifact in one channel (the golden-hour fit's shadow green is 1.148) flooded every shadow with it. The tones are now halved (square root) and renormalised to keep luminance, so they can only shift hue.
- **Full-strength eye adaptation.** Correcting the whole difference looked like a camera's auto-exposure hunting, not an eye. 0.55 of the difference, and slower opening (0.9 stops/s) than closing (1.8 stops/s), as in Unreal.
- **"Natural" at exactly half the grade** read as timid in play; 55 % reads as intended.
- **Measuring Auto during the loading screen.** Menus render far faster than the world; the measurement waits for `isReady()` and 3 s of settling.

## Performance

- CameraFx, FrameSmoothing, ColourGrade and GraphicsPreset are arithmetic on the CPU; their GPU cost is the one DepthOfFieldEffect (and one ColorCorrectionEffect, which merges with any others). Frame blending costs nothing on the GPU.
- EyeAdaptation casts 5 view rays and up to 5 sun rays a frame, with a filter list refreshed once a second.
- The levels buy frame time by switching the DoF off (Low) and by whatever heavier options your game adds to `GraphicsPreset.LEVELS`.

## Fitting your own LUTs

```text
python references/tools/make_luts.py luts                  # optional example looks
python references/tools/lut_fit.py luts/*.cube --out LutGrades.luau
python references/tools/lut_fit.py --selftest              # identity -> zero correction, known CCs round-trip
python references/tools/make_luts.py --selftest            # every example look fits under 20 levels RMS
```

`lut_fit.py` reads any 3D or 1D `.cube` (DOMAIN_MIN/MAX honoured, tables finer than 33 keep 33 of their own nodes), fits exposure, contrast, saturation, brightness and tint by weighted Levenberg–Marquardt (numpy only), measures the leftover split tone, prints each fit's RMS and 95th-percentile error in levels, and writes the Luau module. Grades are keyed by file name (`golden_hour.cube` → `"golden_hour"`), `neutral` first. A fit worse than ~15 levels RMS means the look depends on hue-specific moves Roblox cannot show; pick another or accept a looser version.

## Verification

Run `docs/evidence/post-stack-regression.luau` (install the modules under `ReplicatedStorage.ForgeGUIPostStack`, paste into `execute_luau` in an owned test place). It asserts ownership, restore and idempotence and prints PASS or FAIL. Then play-test on the client, because the render loops only run there:

1. **Motion blur.** Orbit the camera quickly with the mouse and capture mid-turn: the character stays sharp, the background smears. Capture a slow pan: faint smear, no flicker. Open a menu mid-turn: no blur. Set 0 %: none.
2. **Frame smoothing.** Walk and turn with smoothing High, then Off; High should look steadier, not later. A cut (teleport, respawn) snaps rather than swoops.
3. **Colour grade.** Capture the same view at three clock times and with the setting Off / Natural / Cinematic. Check `camera.ForgeGUI_ColourGrade` exists once and `Lighting` carries `ForgeGUIGradeExposure`.
4. **Eye adaptation.** Walk from a dark interior into open sun: the view blooms then settles over one to two seconds. Read `EyeAdaptation.average()` where the base exposure looks right and pass it as `key` if your scene's typical luminance differs from 0.42.
5. **Preset.** Pick Auto after spawning, read `GraphicsPreset.current()`; log the frame times it measured if the pick surprises you.
6. **Stop.** Call `stop()` on each module and confirm the Lighting values and the DoF match what the place had (or what the preset set, if one was applied).

`require` from `execute_luau` returns fresh module instances, not the running game's, so inspect live instances and attributes (or drive the real settings UI) to check what the game is doing.
