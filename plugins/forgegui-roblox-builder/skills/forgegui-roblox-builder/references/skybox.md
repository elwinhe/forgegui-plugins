# Skybox from one panorama

A Roblox `Sky` takes six square images (`SkyboxFt`, `Bk`, `Lf`, `Rt`, `Up`, `Dn`).
Six separately generated images will not meet at the edges. Generate one
equirectangular panorama instead and cut it locally; faces cut from one image meet
by construction.

1. **Generate one panorama.** The prompt says: "seamless 360° equirectangular
   panorama, 2:1, horizon exactly at the vertical middle, left and right edges
   continue into each other, no ground objects near the bottom edge". Add the
   manifest's `art_direction` and pass its `style_refs`. If a skybox template was
   supplied, use its words in the prompt; a template image is a reference
   only once it is in ForgeGUI's ID space (see SKILL.md §3).
2. **Check it before cutting.** It must be 2:1; `sky_faces.py` refuses anything
   else, so pad or resize first, keeping the horizon near the middle.
3. **Cut.** `python3 scripts/sky_faces.py pano.png out/ --size 1024` writes the six
   PNGs. Faces cut from one image meet along their shared edges by construction; the
   join where the panorama's own two ends meet is the exception, and generators do not
   reliably close it — one measured panorama differed by 6.2 mean channel units across
   that join against 1.1 for ordinary neighbouring columns, which shows in Studio as a
   vertical line through one face. The cutter closes that join first (`--band`, 64 columns
   by default, 0 to disable): it takes the step across the wrap, per row and per channel,
   and ramps half of it out of each side. Averaging the two edges instead would blend parts
   of the sky that face opposite directions, so it ghosts detail and disturbs a panorama
   that already wrapped; ramping the step moves only a smooth offset, is bounded by half
   the measured step, and leaves a seamless input untouched. It prints the step it removed
   rather than a re-measured "after", which the correction would force to zero either way.
   `--selftest` checks the six face directions, four shared edges, the `ROTATE` table, and
   all three seam properties. The seam correction is verified by that selftest and by
   measuring the panorama, not by a Studio capture: the in-Studio seam captures on record
   were taken against an earlier averaging version, so re-capture if you need a visual check.
4. **Upload each face** as `assetType: "Image"` (§4), keeping the six ids in the
   ledger under one entry.
5. **Apply** with a preset: `references/luau/SkyboxPresets.luau` carries three moods
   (`daytime`, `nighttime`, `cartoony`) whose values were read out of supplied
   template places rather than invented. `Presets.apply(name, faces)` sets the six
   faces and the matching Lighting, Atmosphere, Bloom and SunRays. Set
   `CelestialBodiesShown = false` if the art already paints a sun or moon.

   **What it replaces.** Every `Sky` under `Lighting`; `TimeOfDay`, `Brightness`,
   `Ambient`, `OutdoorAmbient`, `ShadowSoftness`, `EnvironmentDiffuseScale`,
   `EnvironmentSpecularScale`, `GlobalShadows`; and the first `Atmosphere`,
   `BloomEffect` and `SunRaysEffect` it finds, reconfigured in place rather than
   duplicated. The `Sky` sweep is deliberate: template places have been observed
   shipping two or three stacked `Sky` instances, Roblox renders only one, so a new
   `Sky` parented beside them may never be the one shown. Everything else is left
   alone, and `Presets.clear()` removes only the instances the module created.

   **Ordering.** It shares `LightingPresets.luau`'s ownership convention —
   `ForgeGUI_*` names, the `ForgeGUIPreset` / `ForgeGUIPresetAdopted` attributes,
   `clear()` — so the two sit beside a template's own effects instead of fighting
   them. Run `LightingPresets.apply()` **first** and `SkyboxPresets.apply()`
   **second**: the skybox values are matched to the panorama and should win where
   the two overlap.
6. **Verify** in Studio by looking forward, right, back, left, up and down from
   spawn. The script's face mapping was measured in Studio on 19 Sep 2026: Roblox
   shows `SkyboxLf` on the +X side, `SkyboxUp` turned 90° clockwise and `SkyboxDn`
   90° counter-clockwise, and the script already undoes all three. If a later Studio
   build changes this, fix it with `ROTATE` and `FACES` in `sky_faces.py`, not by
   hand in an image editor. `--selftest` pins the `ROTATE` table against an
   accidental sign or index change, but only in-Studio captures show that those are
   the turns Studio actually needs; re-capture if you change them. Bring Studio to the front before capturing: a background
   window's viewport does not redraw.
