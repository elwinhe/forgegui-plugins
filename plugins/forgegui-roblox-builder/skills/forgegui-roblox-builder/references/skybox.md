# Skybox from one panorama

A Roblox `Sky` takes six square images (`SkyboxFt`, `Bk`, `Lf`, `Rt`, `Up`, `Dn`).
Six separately generated images will not meet at the edges. Generate one
equirectangular panorama instead. Prefer server preparation when enabled; use the
local converter only as the explicit fallback below.

1. **Preflight, then reuse or generate one panorama.** Discover `asset_capabilities`
   and the live `asset_prepare` schema before spending. Call `asset_capabilities({})`;
   use the skybox preparation route only when enabled for this account and the
   requested profile/size. Respect preview restrictions and unavailable reasons;
   do not bypass scope, entitlement or ownership failures. Preflight a separate
   publication route and target creator/experience access as in SKILL.md §4.
   Reuse an owned panorama when suitable; otherwise generate within the approved budget.

   **Panorama prompt.** The prompt says: "seamless 360° equirectangular
   panorama, 2:1, horizon exactly at the vertical middle, left and right edges
   continue into each other, no ground objects near the bottom edge". Add the
   manifest's `art_direction` and pass its `style_refs`. If a skybox template was
   supplied, use its words in the prompt; a template image is a reference
   only once it is in ForgeGUI's ID space (see SKILL.md §3).
2. **Prepare on the server (preferred).** The source must be exactly 2:1 and
   resolve to an owned image UUID or `mcp-artifact:<job UUID>:<index>`, not a local
   path, external URL, Roblox ID or provider task ID. Replace the illustrative
   artifact reference below with the actual owned panorama reference:

   ```json
   {
     "request_id": "skybox-hub-v1-1024",
     "asset": {
       "kind": "skybox",
       "source_ref": "mcp-artifact:11111111-1111-4111-8111-111111111111:0",
       "projection": "equirectangular",
       "face_size": 1024,
       "orientation_profile": { "id": "roblox-sky-cubemap", "version": 1 },
       "yaw_degrees": 0
     }
   }
   ```

   `face_size` is 512 or 1024; optional `yaw_degrees` is -360 through 360.
   Reuse `request_id` only with identical parameters. Record the returned `job_id`
   and poll `generation_status({"job_id": "<returned job UUID>"})` with bounded
   backoff until terminal success and `result.prepared_bundle`. Keep pending or
   unknown jobs in the ledger instead of resubmitting with a fresh ID. Read tool
   errors as well as transport status; stop on rejection or terminal failure.
   Retain bundle/profile identifiers and all six `members[].member_key` →
   `members[].asset_ref` mappings. Auxiliary previews are not face members.
   Preparation does not charge generation credits and **does not publish**; obey
   the live quotas and route restrictions.

   Server-prepared members already follow the requested orientation profile.
   Use their `SkyboxFt/Bk/Lf/Rt/Up/Dn` keys, never array order. Do not run
   `sky_faces.py`, apply its `ROTATE` table, swap faces or rotate them again.
   The inspected v1 server profile reports `studio_orientation_verified: false`;
   a prepared bundle is not evidence of correct Studio rendering. Verify all six
   views and report mismatches with the profile version rather than silently
   mixing the server and local mappings.

3. **Local fallback only.** If server preparation is absent or unavailable, and
   an authorized local file/publication route exists, disclose the fallback and
   run `python3 scripts/sky_faces.py pano.png out/ --size 1024`. Do not use local
   conversion to evade an ownership/access rejection. The source must be 2:1;
   the script refuses anything else. Correct the source dimensions while keeping
   the horizon near the middle before retrying. This writes the six
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
4. **Publish separately.** Discover the supported publishing tool and its live
   schema; preparation artifacts are not Roblox IDs. Publish each keyed member
   through an enabled image route (Open Cloud uses `assetType: "Image"`, §4), or
   retain the prepared bundle/local files for an accepted manual handoff. Confirm
   the actual configured creator/group and experience access, and keep publication
   IDs, returned `asset_id`, asset type, creator metadata and status in the ledger.
   Map `asset_id` to decimal-string `roblox_asset_id` there. Require ready delivery
   and verify rendering; pending moderation with an ID is not readiness. Preserve
   IDs on failure/unknown outcomes and reconcile rather than generating again.
   Map the six ready image IDs by member key: `SkyboxFt` → `faces.Ft`, and likewise
   `Bk`, `Lf`, `Rt`, `Up`, `Dn`. The Luau API accepts positive safe-integer numbers;
   validate conversion from ledger strings without rounding. Never use a Decal
   container ID, artifact reference, bundle ID or URL as a face image ID.
5. **Apply** with a preset: `references/luau/SkyboxPresets.luau` carries three moods
   (`daytime`, `nighttime`, `cartoony`) whose values were read out of supplied
   template places rather than invented. `Presets.apply(name, faces)` sets the six
   faces and the matching Lighting, Atmosphere, Bloom and SunRays. Set
   `CelestialBodiesShown = false` if the art already paints a sun or moon.

   **Preservation and restoration.** All six face IDs are validated before any
   scene mutation. Apply moves existing direct-child `Sky` instances out of
   `Lighting` into a tagged folder in `ServerStorage`, preserving the original
   instances, children and attributes, so only the new sky renders. It overwrites
   `TimeOfDay`, `Brightness`, `Ambient`, `OutdoorAmbient`, `ShadowSoftness`,
   `EnvironmentDiffuseScale`, `EnvironmentSpecularScale`, `GlobalShadows`, and
   adopts the first Atmosphere, BloomEffect and SunRaysEffect (preferring those
   already owned/adopted). Unrelated instances and same-named objects survive.
   `clear()` returns the retained skies to Lighting, restores Lighting and borrowed
   effect values including Enabled, and removes only skybox-owned instances.
   Reapply retains the first baseline; a fresh module/session can clear it because
   storage and `ForgeGUISkyboxPrior_*` attributes live in the place. Repeated clear
   is harmless. Keep the tagged storage and attributes until clearing.

   **Ordering.** Apply `LightingPresets` **first**, `SkyboxPresets` **second**;
   clear `SkyboxPresets` **first**, `LightingPresets` **second**. Clear the skybox
   before changing the underlying lighting preset, then reapply it. Skybox tags
   `ForgeGUISkyboxPreset` / `ForgeGUISkyboxPresetAdopted` and prior attributes
   are distinct from lighting's `ForgeGUIPreset` / `ForgeGUIPresetAdopted` and
   `ForgeGUIPrior_*`: skybox clear restores borrowed lighting-owned effects rather
   than deleting them, then lighting clear restores the original scene.

6. **Verify** in Studio by looking forward, right, back, left, up and down from
   spawn. For the **local fallback**, the script's face mapping was measured in Studio on 19 Sep 2026: Roblox
   shows `SkyboxLf` on the +X side, `SkyboxUp` turned 90° clockwise and `SkyboxDn`
   90° counter-clockwise, and the script already undoes all three. If a later Studio
   build changes this, fix it with `ROTATE` and `FACES` in `sky_faces.py`, not by
   hand in an image editor. `--selftest` pins the `ROTATE` table against an
   accidental sign or index change, but only the in-Studio captures in
   `evidence/spike-skybox/` show that those are the turns Studio actually needs;
   re-capture there if you change them. Bring Studio to the front before capturing: a background
   window's viewport does not redraw.

Headless restoration regression (from the skill root): `lune run references/tests/skybox`.
It checks instance identity, borrowed values, reload/reapply, ownership, and invalid
inputs; it does not verify rendering, moderation, or Studio engine behavior.
