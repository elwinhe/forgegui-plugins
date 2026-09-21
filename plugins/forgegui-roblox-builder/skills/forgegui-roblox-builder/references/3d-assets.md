# 3D assets: generate the identity, build the structure

A game reads as finished or as a blockout mostly through its 3D assets. A
realistic team shooter built through the Studio MCP (a rail-yard map, five
weapons) played well and still looked like a prototype: every weapon, prop and
vehicle was assembled from boxes and cylinders. ForgeGUI's `generation_model_3d`
exists to close that gap. Use it for every asset that gives the game its
identity, and keep Roblox primitives for what primitives do well.

Publishing and animation inputs below were checked against the
[backend contract at `9815cfa`](https://github.com/farewellagain18-byte/gitreposit/blob/9815cfa2096f4d5ac755b337348b9a282f2c7743/docs/mcp/tool-contract.json).
This is a source snapshot, not proof that the connected deployment enables every
capability; discover its live schemas and availability before use.

## Decide the source per asset

| Asset | Default source | Why |
| --- | --- | --- |
| Weapons, tools, held items | ForgeGUI `generation_model_3d` | Seen up close, all the time; parts read as toys |
| Characters, creatures | ForgeGUI; rig and animate only compatible deforming characters | Silhouette and detail carry the art direction; provider rigs require compatibility checks |
| Rigid gear (helmets, vests, packs) | ForgeGUI, attached or welded in Studio | Moving with a character does not itself require rigging or paid animation |
| Vehicles, machines, signature props (forklift, generator, crane cab) | ForgeGUI | Landmarks players navigate by |
| Set dressing seen within ~40 studs (barrels, crates, pallets, benches, lamps) | A generated kit, placed many times | One good crate beats forty box crates |
| Floors, walls, platforms, stairs, road, terrain | Roblox parts, terrain, materials | Collision, level design iteration, cheap |
| Collision proxies, spawn markers, triggers | Roblox parts (invisible) | Gameplay geometry, never art |
| Distant backdrop (skyline, far buildings) | Parts + Textures | Seen from far away; a window Texture per facade costs no triangles |

A part-built stand-in is fine as a **blockout**: build it, play-test the layout
and gameplay, and log it in the asset ledger as `status: "blockout"`. A build
is not finished while identity assets are still blockouts, unless the user
declined generation or the import handoff (record which).

## Plan a kit, not a scene

Generate a small kit and place it many times:

- List every identity asset and every dressing prop that appears more than once.
  Merge near-duplicates ("wooden crate", "supply crate" → one crate with two
  colours).
- Typical first pass for a map-based game: 1-5 weapons or held items, 1 character
  set, 8-20 kit props, 1-3 landmarks. State the count and ask for the budget if
  it isn't already authorised. These are asset counts, not paid-operation totals.
- Count the whole pipeline against the approved paid-call ceiling: base models,
  separately generated moving parts, any generated reference images, remeshes,
  rigging, animations, and permitted retries. For example, five weapons plus five
  magazines and ten remeshes require 20 paid calls, not ten. Reserve planned
  follow-up calls before starting; if actual geometry or scope requires more than
  the remaining allowance, obtain approval for the increased total first. Report
  credit cost as unknown unless billing evidence supplies it.
- Generate one hero asset first per category (a weapon, a piece of gear, a
  prop) and check it: the `thumbnail` in `generation_status`, then the triangle
  count. Carry its look to the rest of the kit through the prompt: repeat the
  same art-direction and material sentence word for word.
- Don't pass a finished model in `reference_asset_ids`. In a 2026-09-19 run,
  `generation_model_3d` rejected model artifacts there ("An input asset was not
  found for this account") and every such job failed at once; resubmitting
  without the reference worked. Image artifacts (a concept image from
  `generation_image`) are the reference type to try.
- Submit in small batches and check status between them. In the same run, 26
  model jobs sent within about two minutes: 14 succeeded, and 12 of the later ones
  came back `outcome_unknown` within seconds of submission. An `outcome_unknown`
  job can't be retried or regenerated without risking a double charge, so a burst
  can cost you those items. Remeshes sent three or four at a time all succeeded.

## Prompting `generation_model_3d`

Live schema (check before use): `prompt`, `quality` (`standard`/`high`),
`pose_mode` (`a-pose`/`t-pose`, characters), `reference_asset_ids` (up to 4
owned UUIDs or `mcp-artifact:` refs), `game_style` (routing type), `request_id`,
and optional `delivery` when exposed (see "Getting it into Studio").

- One object per generation, centred, no ground plane, base or backdrop. Say so.
- Real-world scale words ("about 90 cm long", "chest-height crate") help the
  proportions; you still scale in Studio.
- Name the materials and wear: "parkerised steel receiver, textured black polymer
  grip, worn edges", "painted steel container, rust streaks, stencilled code".
- Say what it is for: "first-person weapon, seen large on screen", "background
  prop seen from 20 studs".
- `quality: "high"` for weapons, characters and landmarks; `standard` for kit
  props. The schema defaults to `high`, so set `standard` explicitly.
- **Moving parts are separate generations.** `generation_model_3d` has no
  option to split a model into parts, and ForgeGUI's `auto_separate` works on
  images, not meshes. Generate the rifle body and, separately, its magazine (and
  a pistol's slide, a shotgun's pump), each described to match the body in the
  prompt, so reload and fire animations can move them. Say in the body's prompt
  that the part is missing ("magazine well empty, no magazine inserted"). Alternatively try Studio's
  `segment_mesh` on the imported mesh (up to five named parts, returned as a new
  Model beside the source) and verify the split; don't assume it cuts where you
  need.
- Check the body's thumbnail for the part anyway. In testing, a pistol frame
  prompted on its own still came back with its slide modelled on, so the separate
  slide would overlap it. Then either use the body whole (and animate the whole
  item) or cut the part away with `segment_mesh` after import.
- Characters for rigging: `pose_mode: "a-pose"`, then `generation_rig_3d` with the
  completed model's job id as `source_job_id`. After rigging succeeds, call the
  free `animation_actions` with the rig's job id as `source_job_id`; choose a
  returned `action_key` and retain its `catalog_version`. Pass both unchanged to
  `generation_animate_3d` with that same rig job id and a stable `request_id`.
  `action_id` is a deprecated compatibility selector, not the default recipe;
  do not combine it with the canonical selectors or invent action IDs. If action
  discovery is unavailable, report the compatibility blocker before animation.
  Rigging and animation output a **provider rig, without Roblox R15 retargeting**.
  Verify the intended Studio character/animation integration before paying for
  these steps. Rigid accessories usually need attachments or welds instead.
  If a character needs remeshing, do it before rigging; don't assume a remesh
  keeps a rig.

## Triangle and size budgets

In the 2026-09-19 run, most outputs arrived at about 100,000 triangles;
two kit props came back at 5,500 and 6,500 triangles. These are observations from
that run, not a guarantee about future outputs or a reason to remesh every model.
Inspect actual per-mesh geometry and file size against the chosen import route's
current limits and the scene budget. Remesh only when needed and within the
approved paid-call allowance. Use `generation_remesh_3d`
(`source_job_id`, `target_polycount`, `topology`); it kept all three texture maps
in testing and took about 20 seconds. Keep `topology:
"triangle"` (the default) so the target reads as a triangle count. Starting
points:

| Asset | Target triangles |
| --- | --- |
| First-person weapon | 4,000-10,000 |
| Third-person weapon / held item | 1,500-4,000 (or the same mesh if under budget) |
| Character | 8,000-20,000 |
| Kit prop | 500-4,000 |
| Landmark / vehicle | 5,000-20,000 |

PR #1 reported limits of 20,000 triangles per mesh and 20 MB per file on the
tested upload route (SKILL.md §4); check the current limits for your route.

## Getting it into Studio

Establish the route when you plan the kit, not after generating (SKILL.md §4):

1. **Generation-time publishing.** Inspect the deployed `generation_model_3d`
   schema and available capability information before spending. If supported
   and enabled, use `delivery: {"mode": "publish", "platform": "roblox"}` when
   the intended ownership matches. The inspected backend contract publishes to
   ForgeGUI's **server-configured group**; callers cannot select an arbitrary
   user or group. Verify the destination and target experience's access first.
   Omitted delivery or `delivery: {"mode": "direct"}` returns files only.
   Poll `generation_status`, inspect publishing status, moderation and access,
   and require the returned Roblox asset ID before `insert_asset`; model
   generation success alone is not publication success.
   This publishes the original generation, **not a later remesh**. The inspected
   `generation_remesh_3d` schema has no `delivery` field. If the final asset needs
   remeshing, preflight a separate route for that remeshed artifact before
   spending; do not insert the original published ID as though it were the remesh.
2. **A separate publishing tool exposed by the connected MCP.** Verify its
   accepted artifact, ownership, permissions, moderation and returned Roblox
   asset ID, then `insert_asset`. Do not assume this tool exists merely because
   generation-time publishing exists.
3. **Open Cloud upload** (`POST /assets/v1/assets`, `assetType: "Model"`, the GLB
   as-is) with the user's own API key through a bridge they run. Poll the
   operation for `response.assetId`, check moderation, then `insert_asset`.
4. **Manual import handoff.** Download each GLB into the project folder and ask
   the user to import them in one sitting with Studio's 3D Importer (File >
   Import 3D). Then find the imported MeshParts in the place and continue. This is slower but fully valid. **Don't fall back to building the
   asset from parts because the import needs a manual step.** Ask the user to
   accept the handoff, batch it, and keep generating within the approved ceiling.

If publishing is disabled, absent from the deployed schema, or targets the wrong
owner, select a verified alternative above. If none is available and the user has
not accepted the manual handoff, stop spending on that asset. Do not regenerate
an existing or ambiguous job to change delivery; retain its identifiers and
resolve its status before arranging import of the existing artifact.

Record in the ledger for every asset (`references/project-manifest.md`): job id,
artifact ref, Roblox asset id or instance path, and status (`generated`, then
`handoff` while it waits for a manual import, `inserted`, `verified`).

## Placing it

- Measure scale against a 5-stud character or the scene's doors (about 7 studs).
  PR #1's imported sample arrived at one stud per authored metre, so a 90 cm
  rifle is under a stud long; scale the model, don't guess.
- Set `PivotTo` from the model's base (props) or grip (held items). Anchor
  environment props. Set `CollisionFidelity` to `Box` or `Hull` for props;
  `PreciseConvexDecomposition` only where players climb or shots must hit exact
  shapes. Set `CanQuery`/`CanTouch` off on pure decoration.
- Held items: add attachments by measurement (Muzzle, Grip, AimPoint, Eject)
  and weld moving parts to the body so animation code can offset them.
- Place the kit through a spawner or Packages so one change updates every copy.
- Verify every placement with `screen_capture` from a player's eye height, and
  check triangle count and draw distance in a play test.

## When primitives are the right answer

Structure, collision, blockouts, and anything the user explicitly wants built in
Studio. Primitives are not the fallback for "generation is paid" or "import needs
a click"; those are reasons to ask, not to downgrade silently.
