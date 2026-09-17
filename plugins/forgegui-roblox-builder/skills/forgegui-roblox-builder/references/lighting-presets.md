# Lighting presets

Six named looks, shipped as reviewed Luau in `luau/LightingPresets.luau`. Apply one after the scene exists, never mid-build. Each preset sets `Lighting` and a post-processing stack (`Atmosphere`, `BloomEffect`, `ColorCorrectionEffect`, `SunRaysEffect`, `DepthOfFieldEffect`). The module reuses its own instances on later applies, and if the place already has an effect of that class (the Baseplate template ships Sky, SunRays, Atmosphere, Bloom and DepthOfField) it adopts and reconfigures that instance instead of stacking a duplicate, which would double bloom and haze. Ownership is decided by attribute, never by name: instances the module created carry `ForgeGUIPreset = true`, adopted ones carry `ForgeGUIPresetAdopted = true`, and an instance that merely shares a `ForgeGUI_*` name is never destroyed; it is adopted only if it is of a class the preset configures, and otherwise ignored. Adopted effects are explicitly set `Enabled = true` when a preset configures them, since templates often ship them disabled; a preset that wants an effect off (`depthOfField.Enabled = false`) still wins.

| Preset | Use it for | Signature |
| --- | --- | --- |
| `bright_stylized` | simulators, obbies, tycoons | ClockTime 13.5, saturated, soft shadows, mild bloom |
| `overcast` | survival, farming, quiet exploration | flat grey, desaturated, thick haze, no sun rays |
| `night_neon` | city, arcade, cyberpunk, racing | near-black ambient, heavy bloom so emissives carry (recommend Future) |
| `dungeon_torchlit` | dungeon, cave, horror | sky killed, warm tint, fog close, depth of field on, torches do the work |
| `sunset` | hub worlds, campsites, story beats, arenas | ClockTime 17.6, long shadows, warm bloom, sun rays |
| `studio_showcase` | menus, shops, item showcases, thumbnails | even and shadowless, no fog, haze neutralised, nothing competing with the item |

## Choosing without being told

If the request names a genre and no lighting instruction, pick via `GenreHints` (`simulator → bright_stylized`, `dungeon → dungeon_torchlit`, `hub → sunset`, `shop → studio_showcase`, ...). `forGenre("dungeon")` looks up one word; `forText("a neon racing game")` scans a whole brief and returns the same names, with an exact preset name winning over a genre word. State which preset you chose and why in one line. If the place already has a deliberate `Lighting` setup (non-default `ClockTime`, or post effects beyond the Baseplate template's default set that carry neither `ForgeGUIPreset` nor `ForgeGUIPresetAdopted`), ask before replacing it. After an apply, `Lighting` itself carries `ForgeGUIPreset = <presetName>`; treat that as a prior preset, not a hand-made setup.

## Dials: fitting a preset to the place

A preset is tuned at ground level on an ordinary scene. Two multipliers cover the adjustments a real place actually needs, so the preset stays the single source of the look:

```lua
local name, report = Presets.apply("sunset", { glow = 0.6, haze = 0.5, reduced = false })
-- report = { preset, technology, glow, haze, disabled = {...}, failed = {...} }
```

- **`glow`** (0–3) scales `BloomEffect.Intensity` and moves `Threshold` the other way, so turning glow down makes fewer pixels bloom as well as blooming them less. Reach for it when the scene has lit walls rather than real emissives.
- **`haze`** (0–3) scales `Atmosphere.Density` and `Haze` together. A look tuned for 50-stud sightlines swallows anything at 200, which is where skylines and floating islands live; `haze = 0.5` was what made the next island visible in a floating-island build.
- **`reduced = true`** switches off the effects each preset lists as droppable (depth of field first, then sun rays) for low-end targets. It only disables effects that already exist — it never creates one just to turn it off — and `clear()` restores the `Enabled` state it changed. `Atmosphere` is never in that list: it has no `Enabled` property and its haze usually carries the look.

`apply` returns the preset name first, so `print(Presets.apply("sunset"))` still reads well, and the report second. Read `report.failed` before claiming a look was applied: it lists any `Class.Property` the engine refused.

## Bloom is the setting most often wrong

`BloomEffect` has three properties and only one of them decides whether a scene looks intentional:

- **`Threshold`** gates *what* blooms. Below roughly 1.0 nearly every lit surface qualifies, so walls, floors and props all glow and the result reads as a broken camera. Gate it to real light sources: torches, neon, the sun, emissive signage. `night_neon` sits at 0.9 deliberately — its ambient is near-black and its emissives are meant to carry the scene — so in a place with ordinary lit walls, pass `glow` below 1.
- **`Intensity`** decides how hard those pixels bloom. 0.2 to 0.7 covers almost everything worth shipping; above 1.0 is a stylistic commitment, not a default.
- **`Size`** is the spread. A large size over a small bright area looks like fog, not glow.

Roblox publishes no recommended ranges for these; the numbers above are our tuning from Studio passes, not vendor guidance.

Tonemapping (`ColorGradingEffect`) is deliberately not part of any preset. It re-maps the whole image and interacts with every emissive in the place, so it is a per-project decision to make once and check, not something a lighting preset should change underneath a build.

## Applying through Studio MCP

Option A, persistent module: this path was tested in **Roblox Studio 0.739.0.7390687**. The settings below record the working sandbox configuration for that test, not a universal requirement or a proven minimum capability set.

1. Create a `ReplicatedStorage.LightingPresets` ModuleScript for this setup, containing the shipped `luau/LightingPresets.luau` source via the live `multi_edit` schema. If that path already contains an unrelated module, use a fresh name and update the `require` path below.
2. On that module only, set `Sandboxed = true` and configure these tested capabilities: `Basic`, `CreateInstances`, `AccessOutsideWrite`, `Environment`, `RunServerScript`, and `RunClientScript`. Use supported Studio tooling for the properties; do not broaden the caller's permissions, change unrelated scripts, or change global Studio security settings.
3. Require the configured module through `execute_luau` in the Edit datamodel:

```lua
local Presets = require(game:GetService("ReplicatedStorage").LightingPresets)
local name, report = Presets.apply("sunset", { haze = 0.6 })
print(name, report.technology, #report.failed)
```

If `require` reports a missing capability, inspect the error and that module's sandbox/capability settings before retrying. A failed module load can remain cached after its source is edited. Recreate only the module created for this setup (or use a fresh module name), restore the same reviewed source and scoped settings, and require that fresh instance. If the current execution context cannot configure those properties, report the restriction rather than adding broader capabilities or weakening Studio security. These module settings do not make `Lighting.Technology` scriptable.

Option B, one-off: paste the module body into `execute_luau`, replacing the final `return M` with `print(M.apply("sunset"))`.

Both are Edit-mode changes and persist with the place. Verify with `screen_capture` from a representative camera before and after, and once in a playtest, because `Technology = Future` and depth of field read differently at runtime.

## `require` from the Studio MCP code runner

A ModuleScript created through `multi_edit` carries extra `Capabilities` (`LoadUnownedAsset` and others), and `execute_luau` in Edit mode may refuse to `require` it: `The current thread cannot require 'LightingPresets' since 'LightingPresets' has additional values for the Capabilities property`. Observed 2026-09-16 with the installed plugin. Workarounds that worked: run the module body through `loadstring` in the same `execute_luau` call, or apply the preset from a server Script in Play, where `require` succeeds. Keep the ModuleScript for gameplay scripts; use `loadstring` only for the one-off Edit-mode apply.

## `Lighting.Technology` is manual

`Lighting.Technology` cannot be read or written by scripts, `execute_luau` included (the engine reports a missing `RobloxScript` capability). Each preset carries a recommended `technology` string (`ShadowMap` for the daylight and showcase looks, `Future` for `night_neon`, `dungeon_torchlit`, `sunset`), echoed back in `report.technology`. Tell the user to set it once in the Properties panel of `Lighting`; do not claim the preset set it.

## Local lights belong to the scene, not the preset

Presets set the global mood only. `dungeon_torchlit` expects the scene to carry `PointLight`s on torches or crystals (`Brightness 1.5–3`, `Range 20–40`, warm color, `Shadows = true` on a few, not all). `night_neon` expects `Neon` material or `SurfaceLight` on signage. Add those with the particle and prop recipes, not by raising `Ambient`.

Materials and geometry also outrank the whole effect stack: vary `Material` deliberately, break long flat runs with trim or props, and keep prop scale plausible against a 5-stud character. Post-processing cannot rescue flat geometry, and mismatched scale is the strongest amateur tell after incoherent colour.

## Performance guard

`Technology.Future` with many shadow-casting lights is the main cost. Keep shadow-casting lights under roughly eight in view, prefer `ShadowMap` for large open maps, and disable `DepthOfFieldEffect` when the camera is mostly close — `apply(name, { reduced = true })` does that last one for you. Check with the Studio microprofiler or a low-end device emulation before claiming the preset holds up.

## Removing

`Presets.clear()` puts the place back. It destroys only children whose `ForgeGUIPreset` attribute is `true` (a matching name is never enough), and restores every property it overwrote on anything it borrowed: adopted effects get their values and their previous `Enabled` state back, `Lighting` gets its own scalars back, and the `ForgeGUIPresetAdopted` tag is removed. It returns `false` when no preset is applied.

Restoration works through attributes rather than module state, so it survives a new session, another script or the command bar: each overwritten property is recorded once, at the first apply, as `ForgeGUIPrior_<Property>` on the instance that owns it (an enum is stored as its name). Because the *first* apply wins, switching presets several times and then clearing still returns the original values rather than the previous preset's. Two consequences worth knowing: a property the module never wrote is never restored, and deleting those attributes by hand loses the ability to revert that property.
