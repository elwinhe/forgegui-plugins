# 3D assets: generate the identity, build the structure

A game reads as finished or as a blockout mostly through its 3D assets. A
realistic team shooter built through the Studio MCP (a rail-yard map, five
weapons) played well and still looked like a prototype: every weapon, prop and
vehicle was assembled from boxes and cylinders. ForgeGUI's `generation_model_3d`
exists to close that gap. Use it for every asset that gives the game its
identity, and keep Roblox primitives for what primitives do well.

## Decide the source per asset

| Asset | Default source | Why |
| --- | --- | --- |
| Weapons, tools, held items | ForgeGUI `generation_model_3d` | Seen up close, all the time; parts read as toys |
| Characters, gear (helmets, vests, packs), creatures | ForgeGUI, then `generation_rig_3d` / `generation_animate_3d` when it moves | Silhouette and detail carry the art direction |
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
  it isn't already authorised.
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
owned UUIDs or `mcp-artifact:` refs), `game_style` (routing type), `request_id`.

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
  model's job id as `source_job_id`, then `generation_animate_3d` with the rig's
  job id as `source_job_id` and the `action_id` the live schema requires.
  If a character needs remeshing, do it before rigging; don't assume a remesh
  keeps a rig.

## Triangle and size budgets

Most outputs arrived at about 100,000 triangles, five times Roblox's per-mesh
limit, so plan a remesh for every model, but read the count first: two kit props
in the same run came back at 5,500 and 6,500 triangles, already near budget. Remesh with `generation_remesh_3d`
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

1. **A publishing tool exposed by the connected MCP** that returns a Roblox asset
   id. Use it, then `insert_asset`.
2. **Open Cloud upload** (`POST /assets/v1/assets`, `assetType: "Model"`, the GLB
   as-is) with the user's own API key through a bridge they run. Poll the
   operation for `response.assetId`, check moderation, then `insert_asset`.
3. **Manual import handoff.** Download each GLB into the project folder and ask
   the user to import them in one sitting with Studio's 3D Importer (File >
   Import 3D). Then find the imported MeshParts in the place and continue. This is slower but fully valid. **Don't fall back to building the
   asset from parts because the import needs a manual step.** Ask the user to
   accept the handoff, batch it, and keep generating.

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

## Establish the publication route

Discover deployed ForgeGUI publication first and prefer it when the live route supports
both the requested asset type and intended owner. `insert_asset` needs a Roblox ID;
a GLB URL is not an ID, and an image uploader is not a model uploader.

If explicitly choosing Open Cloud as the fallback, use the resumable uploader:

```sh
python3 references/tools/oc_upload.py model.glb --type Model --name "Prop" \
  --user-id 123456 --receipt model-upload.json
python3 references/tools/oc_upload.py model.glb --type Model --name "Prop" \
  --user-id 123456 --receipt model-upload.json --resume
```

Replace the example ID with the intended owner, or use `--group-id` for a provable group
scope. `ROBLOX_API_KEY` comes only from the environment, never `.env` or arguments.
Read [asset-upload.md](asset-upload.md) for authority checks, formats, batch examples,
receipt recovery and the compatibility shell wrapper. Do not retry ambiguous publication
or automatically fall back after ForgeGUI `outcome_unknown`; reconcile the original request.
An ID alone does not prove moderation approval or usability in the target Studio experience.

Establish this route before paid generation using discovery and local dry-run. Any live
publication test requires authorization. Studio's native 3D Importer remains a manual route.

## What a generated model actually arrives as

Measured across a six-piece weapon kit on 2026-09-20 (five weapons plus a
magazine, `quality: "high"`, uploaded through Open Cloud and inserted with
`insert_asset`). Every one behaved identically, so treat these as the shape of
the problem rather than as one bad import.

**Triangle counts are unchanged.** The hero rifle came back at **100,508
triangles** — five times Roblox's 20,000 per-mesh limit. The provider-side 20k
cap reported on PR #12 is *not* in effect on this endpoint, so budget a
`generation_remesh_3d` for every single model. Remesh hit its target exactly
(12000, 8000, 6000, 14000 requested and delivered) and preserved all three
texture maps on 6 of 6.

**Scale is gone.** Every GLB is normalised so its longest side is 1.0 stud,
whatever the object is. A 90 cm rifle and a 20 cm pistol both arrive the same
size. Restore it from the real-world dimension you prompted for; Roblox is
roughly 28 cm to the stud, so `scale = (realCm / 28) / longestSide`.

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
