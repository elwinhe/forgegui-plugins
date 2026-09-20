# Skybox from one panorama

A Roblox `Sky` takes six square images (`SkyboxFt`, `Bk`, `Lf`, `Rt`, `Up`, `Dn`).
Six separately generated images will not meet at the edges. Generate one
equirectangular panorama instead and cut it locally; faces cut from one image meet
by construction.

1. **Generate one panorama.** The prompt says: "seamless 360° equirectangular
   panorama, 2:1, horizon exactly at the vertical middle, left and right edges
   continue into each other, no ground objects near the bottom edge". Add the
   manifest's `art_direction` and pass its `style_refs`. If the client supplied a
   skybox template, use its words in the prompt; a template image is a reference
   only once it is in ForgeGUI's ID space (see SKILL.md §3).
2. **Check it before cutting.** It must be 2:1; `sky_faces.py` refuses anything
   else. Look at the left and right edges side by side: that wrap seam is the one
   place a generated panorama can break, and it lands on `SkyboxBk`, behind the
   camera at spawn.
3. **Cut.** `python3 scripts/sky_faces.py pano.png out/ --size 1024` writes the six
   PNGs. `--selftest` checks the face directions and three shared edges.
4. **Upload each face** as `assetType: "Image"` (§4), keeping the six ids in the
   ledger under one entry.
5. **Apply** with a preset: `references/luau/SkyboxPresets.luau` carries the
   client's three template moods (`daytime`, `nighttime`, `cartoony`) read from the
   places they supplied, and `Presets.apply(name, faces)` clears any existing `Sky`,
   sets the six faces and matches their Lighting, Atmosphere, Bloom and SunRays.
   Their own templates ship two or three stacked `Sky` instances, and Roblox renders
   only one, so clearing first is what makes a preset land. Set
   `CelestialBodiesShown = false` if the art already paints a sun or moon.
6. **Verify** in Studio by looking forward, right, back, left, up and down from
   spawn. The script's face mapping was measured in Studio on 19 Sep 2026: Roblox
   shows `SkyboxLf` on the +X side, `SkyboxUp` turned 90° clockwise and `SkyboxDn`
   90° counter-clockwise, and the script already undoes all three. If a later Studio
   build changes this, fix it with `ROTATE` and `FACES` in `sky_faces.py`, not by
   hand in an image editor. Bring Studio to the front before capturing: a background
   window's viewport does not redraw.
