# Lighting presets

Five named looks, shipped as reviewed Luau in `luau/LightingPresets.luau`. Apply one after the scene exists, never mid-build. Each preset sets `Lighting` and a post-processing stack (`Atmosphere`, `BloomEffect`, `ColorCorrectionEffect`, `SunRaysEffect`, `DepthOfFieldEffect`). The module reuses its own instances on later applies, and if the place already has an effect of that class (the Baseplate template ships Sky, SunRays, Atmosphere, Bloom and DepthOfField) it adopts and reconfigures that instance instead of stacking a duplicate, which would double bloom and haze. Ownership is decided by attribute, never by name: instances the module created carry `ForgeGUIPreset = true`, adopted ones carry `ForgeGUIPresetAdopted = true`, and an instance that merely shares a `ForgeGUI_*` name is never destroyed; it is adopted only if it is of a class the preset configures, and otherwise ignored. Adopted effects are explicitly set `Enabled = true` when a preset configures them, since templates often ship them disabled; a preset that wants an effect off (`depthOfField.Enabled = false`) still wins.

| Preset | Use it for | Signature |
| --- | --- | --- |
| `bright_stylized` | simulators, obbies, tycoons | ClockTime 13.5, saturated, soft shadows, mild bloom |
| `overcast` | survival, farming, quiet exploration | flat grey, desaturated, thick haze, no sun rays |
| `night_neon` | city, arcade, cyberpunk | near-black ambient, heavy bloom so emissives carry (recommend Future) |
| `dungeon_torchlit` | dungeon, cave, horror | sky killed, warm tint, fog close, depth of field on, torches do the work |
| `sunset` | hub worlds, campsites, story beats, arenas | ClockTime 17.6, long shadows, warm bloom, sun rays |

## Choosing without being told

If the request names a genre and no lighting instruction, pick via `GenreHints` (`simulator → bright_stylized`, `dungeon → dungeon_torchlit`, `hub → sunset`, ...). State which preset you chose and why in one line. If the place already has a deliberate `Lighting` setup (non-default `ClockTime`, or post effects beyond the Baseplate template's default set that carry neither `ForgeGUIPreset` nor `ForgeGUIPresetAdopted`), ask before replacing it. After an apply, `Lighting` itself carries `ForgeGUIPreset = <presetName>`; treat that as a prior preset, not a hand-made setup.

## Applying through Studio MCP

Option A, persistent module: this path was tested in **Roblox Studio 0.739.0.7390687**. The settings below record the working sandbox configuration for that test, not a universal requirement or a proven minimum capability set.

1. Create a `ReplicatedStorage.LightingPresets` ModuleScript for this setup, containing the shipped `luau/LightingPresets.luau` source via the live `multi_edit` schema. If that path already contains an unrelated module, use a fresh name and update the `require` path below.
2. On that module only, set `Sandboxed = true` and configure these tested capabilities: `Basic`, `CreateInstances`, `AccessOutsideWrite`, `Environment`, `RunServerScript`, and `RunClientScript`. Use supported Studio tooling for the properties; do not broaden the caller's permissions, change unrelated scripts, or change global Studio security settings.
3. Require the configured module through `execute_luau` in the Edit datamodel:

```lua
local Presets = require(game:GetService("ReplicatedStorage").LightingPresets)
print(Presets.apply("sunset"))
```

If `require` reports a missing capability, inspect the error and that module's sandbox/capability settings before retrying. A failed module load can remain cached after its source is edited. Recreate only the module created for this setup (or use a fresh module name), restore the same reviewed source and scoped settings, and require that fresh instance. If the current execution context cannot configure those properties, report the restriction rather than adding broader capabilities or weakening Studio security. These module settings do not make `Lighting.Technology` scriptable.

Option B, one-off: paste the module body into `execute_luau`, replacing the final `return M` with `M.apply("sunset")`.

Both are Edit-mode changes and persist with the place. Verify with `screen_capture` from a representative camera before and after, and once in a playtest, because `Technology = Future` and depth of field read differently at runtime.

## `require` from the Studio MCP code runner

A ModuleScript created through `multi_edit` carries extra `Capabilities` (`LoadUnownedAsset` and others), and `execute_luau` in Edit mode may refuse to `require` it: `The current thread cannot require 'LightingPresets' since 'LightingPresets' has additional values for the Capabilities property`. Observed 2026-09-16 with the installed plugin. Workarounds that worked: run the module body through `loadstring` in the same `execute_luau` call, or apply the preset from a server Script in Play, where `require` succeeds. Keep the ModuleScript for gameplay scripts; use `loadstring` only for the one-off Edit-mode apply.

## `Lighting.Technology` is manual

`Lighting.Technology` cannot be read or written by scripts, `execute_luau` included (the engine reports a missing `RobloxScript` capability). Each preset carries a recommended `technology` string (`ShadowMap` for the daylight looks, `Future` for `night_neon`, `dungeon_torchlit`, `sunset`). Tell the user to set it once in the Properties panel of `Lighting`; do not claim the preset set it.

## Local lights belong to the scene, not the preset

Presets set the global mood only. `dungeon_torchlit` expects the scene to carry `PointLight`s on torches or crystals (`Brightness 1.5–3`, `Range 20–40`, warm color, `Shadows = true` on a few, not all). `night_neon` expects `Neon` material or `SurfaceLight` on signage. Add those with the particle and prop recipes, not by raising `Ambient`.

## Performance guard

`Technology.Future` with many shadow-casting lights is the main cost. Keep shadow-casting lights under roughly eight in view, prefer `ShadowMap` for large open maps, and disable `DepthOfFieldEffect` when the camera is mostly close. Check with the Studio microprofiler or a low-end device emulation before claiming the preset holds up.

## Removing

`Presets.clear()` deletes only children whose `ForgeGUIPreset` attribute is `true`; a matching name is not enough. Adopted effects remain with their modified values and only lose the `ForgeGUIPresetAdopted` tag; it does not restore their settings, their previous `Enabled` state, or previous `Lighting` property values. Record those values with `inspect_instance` before applying if the user may want them back.
