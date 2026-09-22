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
Delivery response handling was checked against
[`projectJob` at `75254cb`](https://github.com/farewellagain18-byte/gitreposit/blob/75254cb000883eb5492d80fa7ccc38e8f09198ac/supabase/functions/forgegui-mcp/server.ts#L453).

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
  prop). For direct delivery, inspect available stored previews and model
  artifacts; measure triangle counts from actual geometry where possible,
  not an assumed response field. For published delivery, wait for
  `delivery.status == "ready"`, then insert and inspect the model in Studio;
  the public response does not expose a thumbnail or model file. If geometry
  approval or remeshing must precede publication, choose direct delivery during
  preflight and establish the later import route. Carry its look to the rest of
  the kit through the prompt: repeat the same art-direction and material
  sentence word for word.
- Don't pass a finished model in `reference_asset_ids` or
  `style_reference_asset_ids`. The inspected schema requires object and style
  references to resolve to images, and in a 2026-09-19 run
  `generation_model_3d` rejected model artifacts there ("An input asset was not
  found for this account") and every such job failed at once; resubmitting
  without the reference worked. Image artifacts (a concept image from
  `generation_image`) are the reference type that fits the contract.
- Submit in small batches and check status between them. In the same run, 26
  model jobs sent within about two minutes: 14 succeeded, and 12 of the later ones
  came back `outcome_unknown` within seconds of submission. An `outcome_unknown`
  job can't be retried or regenerated without risking a double charge, so a burst
  can cost you those items. Remeshes sent three or four at a time all succeeded.

## Prompting `generation_model_3d`

Live schema (check before use): `prompt`, `quality` (`standard`/`high`),
`pose_mode` (`a-pose`/`t-pose`, characters), `reference_asset_ids` and
`style_reference_asset_ids` (up to 4 owned UUIDs or `mcp-artifact:` refs each,
and both must resolve to images), `game_style` (routing type), `request_id`,
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
- Check the body's available preview/model for direct delivery, or the inserted
  Studio model after published delivery is ready, for the part anyway. In
  testing, a pistol frame
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

New generations using ForgeGUI's direct-P2 defaults request at most **5,000
triangles for standard quality** or **15,000 for high**, with `quad: false`.
These are provider request limits, not prompt suggestions; see the
[P2 implementation at `f83ab2a8`](https://github.com/farewellagain18-byte/gitreposit/blob/f83ab2a8/supabase/functions/_shared/tripo-client.ts).
The roughly 100,000-triangle outputs observed in the 2026-09-19 run are not the
expected behavior of this path. Confirm the connected deployment uses these
defaults; older jobs and model overrides may follow a different path.

The generation finalization path does not independently validate the returned
GLB's triangle count. Triangle limits also do not guarantee file size: embedded
textures can make a low-poly model large. Do not treat P2 as an unconditional
20,000-triangle or 20 MB output guarantee.
For direct delivery, inspect actual per-mesh geometry and file size against the
chosen import route's current limits and the scene budget. For published
delivery, inspect geometry after insertion in Studio; report unavailable
measurements rather than assuming compliance or waiting for hidden files.
Remesh only when needed and within the
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

Before paid work, follow [publishing connections](publishing-connections.md) for live discovery, explicit intended-creator selection, active status/type/route/scopes and safe ledger identity. Proposed selectors await final export parity. Direct delivery needs no connection; no creator change or shared-group fallback is allowed on failure. Roblox publishing keys go only through authenticated ForgeGUI settings, never agent chat, MCP arguments, commands or the ledger.

For the preferred inspect/transform-before-publication path, follow
`preparation-installation.md`: generate/reuse a direct artifact, call
`asset_prepare`, inspect `result.prepared_bundle`, and pass the **prepared Model
member** to `artifact_publish`. This supports an existing owned direct result or
remesh without regeneration when the account's routes are usable. Do not apply
the baked transform a second time in Studio. The routes below remain alternatives
when preparation is unnecessary or unavailable.

Establish the route when you plan the kit, not after generating (SKILL.md §4):

1. **Generation-time publishing.** Inspect the deployed `generation_model_3d`
   schema and available capability information before spending. If supported
   and enabled, use publish/roblox with the selected `connection_id` only when
   that selector is live supported. The original selector-free shape
   `delivery: {"mode": "publish", "platform": "roblox"}` is the explicit legacy
   **server-configured group** choice only. Never pass arbitrary user/group
   overrides. Verify the destination and target experience's access first.
   Omitted delivery or `delivery: {"mode": "direct"}` returns files only.
   Poll `generation_status` until `delivery.status == "ready"`, verify access,
   then use the returned Roblox asset ID with `insert_asset` and inspect in
   Studio. Save `publication_id`, decimal-string `asset_id`, `asset_type` and
   creator metadata (legacy `creator_group_id` when present) as returned; retain the asset ID as a
   string in records and adapt it only as required by the insertion schema.
   Published responses deliberately set `result: null` and suppress raw files
   on submission, polling and replay. Do not require `result.artifacts`, a GLB
   URL or a thumbnail, or keep polling to obtain those hidden fields.
   `pending_moderation` may already include an asset ID but is not ready;
   continue bounded status polling. For `failed`, report the publication error;
   for `needs_reconciliation`, stop and report the required operator
   reconciliation. Preserve all identifiers in either case and do not regenerate
   to switch delivery. Generation success or an asset ID alone is not readiness.
   Generation-time publishing exposes the original model before the client can
   approve its geometry. If inspection or remeshing must happen before any
   externally visible publication, choose direct mode during preflight and
   establish a separate later import route.
   This publishes the original generation, **not a later remesh**. The inspected
   `generation_remesh_3d` schema has no `delivery` field. If the final asset needs
   remeshing, preflight a separate route for that remeshed artifact before
   spending; do not insert the original published ID as though it were the remesh.
2. **A separate publishing tool exposed by the connected MCP.** Verify its
   accepted artifact, ownership, permissions, moderation and returned Roblox
   asset ID, then `insert_asset`. Do not assume this tool exists merely because
   generation-time publishing exists.
3. **Legacy Open Cloud upload**, retained as a separate workflow, not a connection setup or failure fallback. Never collect or handle Roblox publishing keys for this connection workflow. Existing local users have
   `references/tools/oc_upload.py` with a mandatory receipt and an explicit
   destination. See [Establish the publication route](#establish-the-publication-route)
   below. Check moderation, then `insert_asset`.
4. **Manual import handoff.** Download each GLB into the project folder and ask
   the user to import them in one sitting with Studio's 3D Importer (File >
   Import 3D). Then find the imported MeshParts in the place and continue. This is slower but fully valid. **Don't fall back to building the
   asset from parts because the import needs a manual step.** Ask the user to
   accept the handoff, batch it, and keep generating within the approved ceiling.

If publishing is disabled, absent from the deployed schema, or targets the wrong
owner, select a verified alternative above. If none is available and the user has
not accepted the manual handoff, stop spending on that asset. Do not regenerate
an existing or ambiguous job to change delivery; retain its identifiers and
resolve its status before arranging import of the existing artifact. Never republish integrated outputs, even if a publication ID is temporarily missing.

Record in the ledger for every asset (`references/project-manifest.md`): job id,
delivery mode, available direct artifact refs or published delivery metadata
(`publication_id`, decimal-string `roblox_asset_id` mapped from the API response's
`asset_id`, `asset_type`, returned creator metadata including legacy `creator_group_id` when present, and delivery status), plus the Studio
instance path when inserted. Use `roblox_asset_id` for manifest reuse and
reconciliation. Do not invent
an artifact ref for published output. Track local status separately (`generated`, then
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

## Establish the publication route

Discover deployed ForgeGUI publication first and prefer it when the live route supports
both the requested asset type and intended owner. `insert_asset` needs a Roblox ID;
a GLB URL is not an ID, and an image uploader is not a model uploader.

For separate legacy local users only, the resumable uploader remains available. Connection callers must use authenticated ForgeGUI settings and must not collect keys or execute local uploads as a fallback. Historical command examples:

```sh
python3 references/tools/oc_upload.py model.glb --type Model --name "Prop" \
  --user-id 123456 --receipt model-upload.json
python3 references/tools/oc_upload.py model.glb --type Model --name "Prop" \
  --user-id 123456 --receipt model-upload.json --resume
```

Replace the example ID with the intended owner, or use `--group-id` for a provable group
scope in that separate legacy workflow. The helper reads a pre-provisioned environment credential; connection callers must not request it or populate the environment.
Read [asset-upload.md](asset-upload.md) for authority checks, formats, batch examples,
receipt recovery and the compatibility shell wrapper. Do not retry ambiguous publication
or automatically fall back after ForgeGUI `outcome_unknown`; reconcile the original request.
An ID alone does not prove moderation approval or usability in the target Studio experience.

Establish this route before paid generation using discovery and local dry-run. Any live
publication test requires authorization. Studio's native 3D Importer remains a manual route.

## What a generated model actually arrives as

Measured across a six-piece weapon kit on 2026-09-20 (five weapons plus a
magazine, `quality: "high"`, uploaded through Open Cloud and inserted with
`insert_asset`). These are observations from that kit and deployment, not
universal properties of current model outputs.

**Triangle counts in that kit.** The hero rifle had **100,508 triangles**.
Remesh hit the requested targets (12000, 8000, 6000, 14000) and preserved all
three texture maps on 6 of 6. This does not establish current endpoint defaults
or justify remeshing every model. Use ForgeGUI preparation measurements when
available, or inspect actual per-mesh geometry in the source or Studio, against
the intended import limits and scene budget. Request paid remeshing only when
those measurements show a need and the user has authorized the cost. If
measurements are unavailable, report the gap rather than remeshing speculatively.

**Scale in that kit.** The imported models had a longest side of about 1 stud.
Do not assume that normalization for other models. Measure the actual imported
bounds and choose the intended dimensions in studs from the scene's scale.
Use `scaleFactor = intendedDimensionStuds / measuredImportedDimensionStuds`
on the corresponding axis, retaining proportions; for `Model:ScaleTo`, multiply
the current `GetScale()` by that factor. Verify the resulting bounds in Studio.
Real-world prompt dimensions express intent, not a guaranteed import scale.

**Textures are not on `TextureID`.** They arrive as a `SurfaceAppearance` child
carrying four separate maps (ColorMap, NormalMap, RoughnessMap, MetalnessMap).
Reading `TextureID` reports `""` and looks like the textures were lost. They
were not — check for the `SurfaceAppearance`.

**The hierarchy is nested and packaged.** You get `Model > Model > MeshPart`,
wrapped in a Package, unanchored, `PrimaryPart` unset, `CollisionFidelity` at
Default. Flatten it, destroy the `PackageLink`, and set `PrimaryPart` yourself.

Two ordering traps, both of which look like the write silently failed:

1. **A property written in the same call that destroyed the `PackageLink` is
   discarded.** The instance is still a package member for that frame. Destroy
   the link in one `execute_luau`, write properties in the next.
2. **`CollisionFidelity` is ignored while the MeshPart is still streaming.**
   `ContentProvider:PreloadAsync` the meshes, wait, *then* set it — otherwise it
   reads back as Default however many times you assign it.

A normalisation pass that handles all of the above, in order, is the only way a
kit of this size stays consistent; doing it by hand per asset is where the
inconsistencies come from.

## Rigging: what `generation_rig_3d` actually gives you

Tested 2026-09-20 on a generated A-pose character. Two things matter, and they
point in opposite directions.

**The good surprise.** The call returns more than a rigged mesh. Alongside
`rigged_glb` it hands back `running_glb` and `walking_glb` — two preset
animations (`preset:run`, `preset:walk` in the glTF), already bound to the
skeleton, at no extra call. `generation_animate_3d` is not needed for a basic
locomotion set. Nothing in the tool description says so.

**The blocker.** The skeleton is a 41-joint skinned rig. Uploaded through Open
Cloud and inserted, it arrives as:

```
1 MeshPart + 41 Bone + AnimationController + SurfaceAppearance
Humanoid: false    Motor6D: 0
```

A Roblox R15 character is 15 MeshParts joined by **Motor6D** under a
**Humanoid**. A skinned mesh driven by Bones is a different thing entirely: it
will not accept R15 animations, `Humanoid:LoadAnimation` has nothing to bind to,
and none of the standard character systems (states, health, tools, collisions)
apply to it.

So for any brief that says *"animations on the standard Roblox rig, no
auto-rigging of generated meshes"*, **`generation_rig_3d` produces the thing being excluded, not
the thing being asked for.** It is auto-rigging a generated mesh by definition.

Satisfying that category needs a different route: author or source an animation
against Roblox's own R15 skeleton, upload it with Open Cloud as
`assetType: "Animation"`, and play it through `Animator:LoadAnimation` on a
standard character. ForgeGUI has no part in that path today.

Use `generation_rig_3d` when you want a self-contained animated prop or NPC and
you control its playback. Do not use it to satisfy a standard-rig requirement.
Rigging also does not remesh: the rigged GLB came back at the original 100,518
triangles, so it is still over Roblox's per-mesh limit, and remeshing after
rigging risks the skin weights.

## Wiring generated models into a running game

Inserting a model proves the import. It does not put the model in the game. On the project these
notes come from, every generated prop was placed in the map by hand, looked right in Edit, and was
gone in Play: the map service destroys and rebuilds `Workspace.Map` at server start, as most
procedurally built maps do. The viewmodel was still built from Parts for the same reason nothing
referenced the generated rifle. The user's verdict on that build was "none of our generated things
are in there", and it was accurate.

- **Keep an asset library, and make game code consume it.** Normalised models live in
  `ReplicatedStorage.Assets.{Weapons,Props,Gear}`; the map builder clones props from it, the
  viewmodel clones the equipped weapon from it, the character dresser clones gear from it. Count
  generated placements at runtime (tag or name-prefix them) and put the count in the self-test.
- **Record each asset as data** (mesh id, the four `SurfaceAppearance` map ids, real size, pivot,
  attachments, fit attributes) so the library can be rebuilt from a JSON file with
  `InsertService:CreateMeshPartAsync(meshId, collisionFidelity, renderFidelity)`. That call takes
  collision fidelity at creation and returns a bare MeshPart: no package, no nested Model, no
  discarded writes, no streaming race. It needs the mesh id, which you only learn by inserting the
  uploaded Model once.
- **The generator does not fix a forward axis.** In one kit the long guns came back muzzle +Z, the
  pistol muzzle -X, worn gear front -X, and the two arms opposite each other. Measure every asset
  and store a pivot that puts grip at the origin and the barrel down -Z; then `Tool.Grip`, the
  viewmodel offset and a `ViewportFrame` camera are each one line.
- **`Model:ScaleTo` is absolute, not relative.** `ScaleTo(0.7)` on a model already restored to real
  size does not shrink it by 30%, it sets it to 0.7 of its import size. Use
  `model:ScaleTo(model:GetScale() * k)`.
- **Seat props on the ground from their bounding box**, not from a guessed Y: pivot to the target,
  read `GetBoundingBox`, lift by the difference. Scale landmarks to the span the layout was tuned
  around and keep the original Parts underneath as invisible collision proxies, so sightlines and
  pathfinding do not change when the art does.
- **Rigid gear on the stock R15 rig needs no rigging.** Weld a helmet or plate carrier to `Head` or
  `UpperTorso` with a `WeldConstraint`, storing `FitPart` and `FitOffset` on the asset so new gear
  needs no code. Blocky R15 swallows a realistically proportioned vest: scale the mesh
  non-uniformly (depth about x2, width about x1.25). Spawn everyone on a uniform body via
  `LoadCharacterWithHumanoidDescription`, because a personal avatar can be any shape and no fixed
  offset survives that. Make the kit `CanQuery = false` and `Massless` so hits land on the body and
  movement does not change.
- **Show the model in the UI.** A `ViewportFrame` renders a generated MeshPart with its
  `SurfaceAppearance`, inside a `CanvasGroup`, in a real ScreenGui. A loadout screen with the actual
  rifle turning slowly beats any icon, and costs no generation. Sway either side of a three-quarter
  view rather than spinning; a spin spends half its time showing the muzzle end-on.
- **Fresh uploads render white for a while.** Texture maps stream after the mesh. Call
  `ContentProvider:PreloadAsync` on the `SurfaceAppearance`s and wait before judging a capture; one
  landmark took about 90 seconds.
- **Light sources have to be lights.** A generated floodlight mast that casts nothing is set
  dressing. Give each a `SpotLight` aimed into the play space, and remember a SpotLight reaches 60
  studs: perimeter masts cannot light the middle of a 260-stud map, so hang work lights from the
  central landmark as well.

## First-person hands: solve them from the weapon, do not offset them

Generated forearms are static meshes: a closed fist, a cupped palm, each about 40 cm long and
ending in a cut. Two things go wrong when they are positioned by hand-tuned offsets:

- **The library pivot is not the grip.** A pivot measured "at the grip" sat between the pistol grip
  and the magazine, so a fist placed on it floated in front of the trigger guard, holding nothing.
  Write down, per weapon, where hands actually go, in the weapon's own space at real size: `grip`
  (centre of the pistol grip), `support` (underside of the handguard), `magWell`, and the sight
  height. Read them off a side-on capture against a half-stud ruler of neon parts.
- **Solve each arm from the gun's pose**: hand at the point, forearm (+Z) aimed at an elbow position
  below and outside the frame in camera space, thumb side as close to the weapon's up vector as
  that allows (`CFrame.fromMatrix`). The cut end then never shows; carry a plain sleeve cylinder on
  past the frame edge to be sure. Reload becomes a route the support hand walks between named
  points, and every weapon gets it for free.
- Check it by capturing the side view AND the eye view. One generated pistol came out of the
  pipeline pointing at its own user: the muzzle was on +Z and nobody had looked.
- A fully metallic PBR weapon 15 cm from the lens at dusk renders as a black cut-out: metals have no
  diffuse response and the sky it reflects is dark. `SurfaceAppearance` maps cannot be changed at
  runtime, so build a first-person variant at edit time with the metalness map removed, and carry a
  short-range fill light with the camera.
- Run additive motion (look sway, strafe roll, landing dip, recoil) on springs, not lerps, so it
  overshoots and settles; blend poses (hip, aim, sprint, draw, reload) underneath.

## Third person on the stock rig: IKControl, not a Tool

Making the weapon a `Tool` gets the stock one-armed hold with the support arm hanging at the side.
Mount the weapon to `UpperTorso` with a `Motor6D` whose `C1` is the mesh's `PivotOffset` (so `C0`
places the grip pivot), and add two `IKControl`s under the Humanoid (`Type = Position`,
`ChainRoot = *UpperArm`, `EndEffector = *Hand`, `Target` = an Attachment on the weapon at the same
grip and support points). IKControl runs after the animation step on every client and is an
Instance, so it replicates: the stock walk, run, jump and fall keep driving the body while both
hands stay on the gun, for players and server-owned NPCs alike. No custom rig and no animation
assets to upload.

- A blocky R15 arm is short. Bring the weapon in to the chest and pull the support target back from
  the far end of the handguard.
- **Do not set `Pole`.** An elbow hint cost more reach than the arm has: the support hand stopped
  0.8 studs short with it and 0.2 without.
- A server-owned rig has no running `Animate` script. Play idle, walk, run, jump and fall yourself
  from `Humanoid.Running` and `StateChanged`.
- IK does not evaluate in Edit. Verify in Play by reading the distance from `EndEffector.Position`
  to `Target.WorldPosition`.
