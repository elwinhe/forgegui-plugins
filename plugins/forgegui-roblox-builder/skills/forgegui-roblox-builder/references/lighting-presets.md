# Lighting presets

Five named looks, shipped as reviewed Luau in `luau/LightingPresets.luau`. Apply one after the scene exists, never mid-build. Each preset sets `Lighting` and a post-processing stack (`Atmosphere`, `BloomEffect`, `ColorCorrectionEffect`, `SunRaysEffect`, `DepthOfFieldEffect`) that the module creates once and reconfigures on later applies.

| Preset | Use it for | Signature |
| --- | --- | --- |
| `bright_stylized` | simulators, obbies, tycoons | ClockTime 13.5, saturated, soft shadows, mild bloom |
| `overcast` | survival, farming, quiet exploration | flat grey, desaturated, thick haze, no sun rays |
| `night_neon` | city, arcade, cyberpunk | near-black ambient, heavy bloom so emissives carry (recommend Future) |
| `dungeon_torchlit` | dungeon, cave, horror | sky killed, warm tint, fog close, depth of field on, torches do the work |
| `sunset` | hub worlds, campsites, story beats, arenas | ClockTime 17.6, long shadows, warm bloom, sun rays |

## Choosing without being told

If the request names a genre and no lighting instruction, pick via `GenreHints` (`simulator → bright_stylized`, `dungeon → dungeon_torchlit`, `hub → sunset`, ...). State which preset you chose and why in one line. If the place already has a deliberate `Lighting` setup (non-default `ClockTime`, existing post effects without the `ForgeGUIPreset` attribute), ask before replacing it.

## Applying through Studio MCP

Option A, persistent module: create `ReplicatedStorage.LightingPresets` as a ModuleScript with the file contents via `multi_edit`, then in `execute_luau` (Edit datamodel):

```lua
local Presets = require(game:GetService("ReplicatedStorage").LightingPresets)
print(Presets.apply("sunset"))
```

Option B, one-off: paste the module body into `execute_luau`, replacing the final `return M` with `M.apply("sunset")`.

Both are Edit-mode changes and persist with the place. Verify with `screen_capture` from a representative camera before and after, and once in a playtest, because `Technology = Future` and depth of field read differently at runtime.

## `Lighting.Technology` is manual

`Lighting.Technology` cannot be read or written by scripts, `execute_luau` included (the engine reports a missing `RobloxScript` capability). Each preset carries a recommended `technology` string (`ShadowMap` for the daylight looks, `Future` for `night_neon`, `dungeon_torchlit`, `sunset`). Tell the user to set it once in the Properties panel of `Lighting`; do not claim the preset set it.

## Local lights belong to the scene, not the preset

Presets set the global mood only. `dungeon_torchlit` expects the scene to carry `PointLight`s on torches or crystals (`Brightness 1.5–3`, `Range 20–40`, warm color, `Shadows = true` on a few, not all). `night_neon` expects `Neon` material or `SurfaceLight` on signage. Add those with the particle and prop recipes, not by raising `Ambient`.

## Performance guard

`Technology.Future` with many shadow-casting lights is the main cost. Keep shadow-casting lights under roughly eight in view, prefer `ShadowMap` for large open maps, and disable `DepthOfFieldEffect` when the camera is mostly close. Check with the Studio microprofiler or a low-end device emulation before claiming the preset holds up.

## Removing

`Presets.clear()` deletes only children tagged with the `ForgeGUIPreset` attribute and leaves user-authored lighting alone. It does not restore previous `Lighting` property values; record them with `inspect_instance` first if the user may want them back.
