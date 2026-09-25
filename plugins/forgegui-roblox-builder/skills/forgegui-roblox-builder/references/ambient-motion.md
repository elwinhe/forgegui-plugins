# Ambient motion: wind, dust, foliage, cloth and camera paths

A world with no moving air reads as a screenshot even when every asset is good. This page covers the
motion that is not gameplay: one shared wind, the air made visible around the camera, plants that
answer the wind, and short cinematic camera shots. All of it is client-side, costs little, and only
touches instances it owns or has recorded.

Reviewed code, each a self-contained ModuleScript (ship under `ReplicatedStorage`, start from one
LocalScript):

| Module | What it does |
| --- | --- |
| `luau/Wind.luau` | the shared wind field: `sample()`, `get(position)`, `setStorm(0..1)`; drives `Workspace.GlobalWind` |
| `luau/WindVfx.luau` | lit ribbons, ground wisps, motes, ridge spray and optional leaves around the camera |
| `luau/FoliageSway.luau` | tagged trees, palms, shrubs and banners lean and sway with the wind |
| `luau/CameraPath.luau` | eased Catmull-Rom camera shots with look-at keys; restores the camera when done |

Use it when the brief is an outdoor world (desert, tundra, forest, wasteland, coast) or the user asks for
"atmosphere", "wind", "weather" or "cinematic" camera moves. Skip WindVfx for interiors and space; use
`ParticleRecipes.ambient_dust` there instead (see below).

## Wiring

```lua
-- StarterPlayerScripts/Ambient.client.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Wind = require(ReplicatedStorage.Wind)
local WindVfx = require(ReplicatedStorage.WindVfx)
local FoliageSway = require(ReplicatedStorage.FoliageSway)

Wind.start({ prevailing = Vector3.new(-1, 0, 0) })          -- blows toward -X
WindVfx.start({ wind = Wind, palette = "sand", isPaused = function() return false end })
FoliageSway.start({ wind = Wind, onLeafSource = WindVfx.setLeafSource })

-- A storm decided by the server: replicate one attribute, ease every client into it.
Lighting:GetAttributeChangedSignal("Storm"):Connect(function()
	Wind.setStorm(if Lighting:GetAttribute("Storm") == true then 1 else 0)
end)
```

WindVfx and FoliageSway take the wind as an injected `wind` option. Without it they read
`Workspace.GlobalWind`, so they also work beside a wind system you already have.

## The wind field (`Wind.luau`)

The field is a pure function of time, and the default clock is `Workspace:GetServerTimeNow()`. Every
client therefore sees the same gust at the same moment and nothing is replicated. Gusts sit one per
`gustSlot` seconds, at a hashed time inside the slot, with hashed strength and attack/decay. At the
default slot they arrive 5–16 s apart. The direction veers slowly either side of `prevailing`, with a
small extra swing during a gust.

| Call | Returns / does |
| --- | --- |
| `Wind.start(config?)` / `Wind.stop()` | Heartbeat loop; `stop()` restores `GlobalWind`. Both idempotent |
| `Wind.sample()` | `(direction, strength, gust)`: unit horizontal direction the wind blows toward, unitless strength, gust 0..1 |
| `Wind.get(position)` | velocity in studs/s at a point. The gust is delayed by distance downwind / `gustTravel`, so a gust rolls across a field |
| `Wind.setStorm(level, instant?)` / `Wind.storm()` | storm target 0..1, eased with `stormSeconds` |
| `Wind.speed(strength)` | studs/s for a strength (`speedBase + speedGain * strength`) |
| `Wind.at(t, storm?)` | the pure field, for tests and previews |
| `Wind.configure(partial)` | merge settings. Unknown fields and fields of the wrong type are ignored with a warning |

| Setting | Default | Meaning |
| --- | --- | --- |
| `prevailing` | `(-1, 0, 0)` | direction the wind blows toward |
| `veerDegrees` | 25 | slow swing either side of prevailing (periods 311 s and 173 s) |
| `gustSlot` | 10.5 s | one gust per slot |
| `calm` / `gustGain` | 0.3 / 0.42 | base strength / what a full gust adds (strong gust ≈ 0.7) |
| `stormStrength` / `stormSeconds` | 1.1 / 6 s | storm strength (1.1–1.4 with gusts) / easing time constant |
| `speedBase` / `speedGain` | 3 / 22 | studs/s = 3 + 22 × strength (calm ≈ 10, storm ≈ 27–34) |
| `gustTravel` | 40 studs/s | how fast a gust front rolls downwind in `get()` |
| `setGlobalWind` / `globalWindStep` | true / 0.1 s | drive `Workspace.GlobalWind` at 10 Hz |
| `seed` | 0 | decorrelates two fields; equal seeds agree on every client |
| `clock` | server time | must agree across clients for a shared wind |

`Workspace.GlobalWind` moves terrain grass and every `ParticleEmitter` with `WindAffectsDrag = true`, so
fire smoke, footstep puffs and the WindVfx particles all drift the right way with no extra code.

Ownership: Wind creates no instances. It records the `GlobalWind` it found as
`ForgeGUIPrior_GlobalWind` on Workspace (the first start wins, so a value left by an interrupted run is
what comes back). It marks `ForgeGUIWind = true` while running.

## The air made visible (`WindVfx.luau`)

Everything is lit (`LightInfluence = 1`), so it shows where light falls and disappears in shade, as
real dust does:

- **Ribbons**: faint `Trail`s on moving anchors, 0.5–4 studs above the ground and 15–90 studs ahead
  of the camera. They glide downwind at wind speed with a side-to-side meander, follow the ground
  height, and fade in, out and with distance (45–90 studs). There are more in gusts; in a storm they
  are more numerous, darker and more opaque.
- **Ground wisps**: very faint, large soft-smoke particles dragged downwind from a 150-stud volume 22
  studs upwind of the camera. They are tinted like the terrain material under the camera and scaled
  by how loose that material is (`loose` table: sand and snow 1, ground 0.5, grass 0.25, anything
  unlisted such as paving 0.15).
- **Motes**: fine specks in a 46-stud box around the camera, visible only in sunlight (rate × 0.35 at
  night).
- **Ridge spray**: thin streams of grains blown off the lee edge of ridges of a loose material (dune
  crests, snow cornices). A ridge is ground that stands above the ground 6 studs upwind and at least
  0.8 studs above the ground 6 studs downwind.
- **Leaves** (optional): fragments from the crown FoliageSway reports. They appear only when
  `textures.leaf` is set. Without a real leaf sprite they are skipped rather than faked with the
  wrong image.

| Option | Default | Notes |
| --- | --- | --- |
| `wind` | GlobalWind | any table with `sample()`, optional `speed()`, `storm()` |
| `palette` | `"sand"` | `"sand"`, `"snow"`, `"leaves"`, `"ash"`, or a table of six Color3s |
| `textures` | engine smoke / sparkles | `{ dust, mote, grain, leaf }` rbxassetids |
| `ribbons` / `crests` | 14 / 4 | pool sizes; `crests = 0` turns ridge spray off |
| `crestMaterials` | Sand, Snow | which ground materials form ridges |
| `loose` | see module | 0..1 per `Enum.Material` |
| `tintFromTerrain` | true | wisps take the terrain material's colour |
| `isPaused` | never | return true while a pause menu is open: nothing spawns |
| `getExposure` | 0.1 under a roof, else 1 | e.g. quiet inside a town, lively in open country |
| `groundFilter` | `{ Terrain }` | raycast include list; add your floor folder in a part-built world |
| `quality` | 1 | 0..1 scales counts and rates (low-end preset) |

**Why not `ParticleRecipes.ambient_dust`.** That recipe (`particle-recipes.md`) is a static emitter at
one attachment, sized for a room or a shaft of light. WindVfx is camera-local weather. A handful of
reusable volumes follow the camera, the particles are world-space so moving the volumes never drags
them, and every rate is driven by the wind, the ground under the camera and shelter. Use
`ambient_dust` indoors and WindVfx outdoors. They share the conventions: engine-bundled textures by
default, and an ownership attribute on everything created.

**Tried and retired.** Flat "swirl streak" sprites for wind read as stickers on the lens. The build this
came from removed them. The air now reads through lit smoke, 3D ribbons and things that move.

Ownership: every instance carries `ForgeGUIWindVfx = true`, under one owned folder `ForgeGUI_WindVfx`.
`stop()` destroys only owned instances and removes the folder only when it is empty. A stranger's
instance inside it survives, and the folder stops being claimed.

## Foliage (`FoliageSway.luau`)

Tag the Model (or a single BasePart) with `ForgeGUISway`. Tags replicate, so tag in Studio or at build
time. Attributes on the tagged instance are optional:

| Attribute | Type | Meaning |
| --- | --- | --- |
| `SwayProfile` | string | `palm`, `tree` (default), `conifer`, `dead`, `shrub`, `banner` |
| `SwayScale` | number | multiplies lean and sway; 0 freezes it |
| `SwayBase` | Vector3 | world pivot; default is the bottom centre of the bounding box |
| `SwayLeaves` | boolean | report this crown to `onLeafSource` (palms default to true) |

| Profile | Lean °/strength | Sway ° | Speed Hz | Tuned height |
| --- | --- | --- | --- | --- |
| palm | 2.2 | 1.6 | 0.33 | 30 |
| tree | 1.0 | 0.8 | 0.45 | 20 |
| conifer | 0.6 | 0.5 | 0.40 | 28 |
| dead | 0.35 | 0.3 | 0.60 | 16 |
| shrub | 3.0 | 2.6 | 0.90 | 4 |
| banner | 1.2 | 1.8 | 0.70 | 16 |

A plant is rotated about its base: a steady lean downwind that grows with strength, a sway whose speed
and size follow the gusts, and a small cross-wind wobble. Its phase comes from its position, so a stand
never moves in lockstep. Taller specimens move less (gain = 1/√(height / tuned height)). Only anchored
parts move, and only on this client, so physics and the server copy are untouched. Set
`ModelStreamingMode = Atomic` on tagged models so a tree arrives whole.

Options: `range` 220 studs, `maxActive` 60 (nearest first, re-chosen every 0.5 s), `near` 110 (farther
plants update every other frame), `leafRange` 80, `tag`. Plants wholly behind the camera are skipped,
and with nothing in range the frame loop does nothing. Every moving part goes through one
`Workspace:BulkMoveTo` per frame, not one CFrame write per part.

Ownership: each moving part carries `ForgeGUIPrior_CFrame` (its rest pose) and
`ForgeGUIFoliageSway = true` while active. Handing it back writes the rest pose and removes both.
`restoreAll(root)` repairs parts that a crashed or reloaded copy left moved.

## Cloth (not shipped: approach only)

The source build waved its war banners with a separate 792-line cloth controller. It is not ported
because its shape analysis is tuned to one mesh layout: a single MeshPart holding pole, crossbar,
hanging cloth and ornaments. Making it general is its own piece of work (see the issue list). For
now, tag banners with `SwayProfile = "banner"` for a rigid sway. That is the same fallback the
original used when cloth deformation was unavailable. The approach, for whoever picks it up:

- Deform on the client with `EditableMesh`: one shared mesh per (MeshId, phase variant), with 1 phase
  variant on phones and 2 elsewhere, chosen by position so neighbours do not flap in step. A
  visual-only copy (no collision, no queries) replaces the original locally, and the original is made
  transparent, so physics and the server copy are untouched.
- Find the cloth from the rest vertices. The thinner horizontal axis above the footing is the cloth's
  thickness, and the pole stands at the footing's mean. The crossbar is a Theil-Sen line through the
  top vertex of each slice, because a flat "top 8 %" bends a tilted bar. Per-vertex weight is
  smoothstep(depth below the bar) × smoothstep(distance from the pole past a dead zone), so the free
  corner moves most.
- Motion is a travelling wave along the thin axis, plus a smaller harmonic, a billow downwind, and a
  slight outward stretch and lift. Gusts make it faster and wider. Long cloth edges are split first
  (crack-free across UV seams) so the wave bends the cloth instead of hinging large facets.
- Budget: update only variants with a banner within 110 studs (24 Hz within 50 studs, 12 Hz beyond;
  15/8 Hz on phones), one variant per frame, at most 2800 moving vertices (1600 on phones). The target
  was 0.9 ms per variant update, with the rate lowered on slow devices. Idle meshes are freed after
  45 s.
- Published games must enable "Allow Mesh / Image APIs", or `CreateEditableMeshAsync` is refused. The
  controller then falls back to rigid sway. Separately, an `EditableMesh`-built MeshPart made in Edit
  does not survive into Play or a save, so the deformation has to start on the client at runtime.

## Camera paths (`CameraPath.luau`)

Short cinematic shots (an arrival, an unlock, a reveal) through keyframes. UI motion (panels, presses,
counters, modals) is a separate module: see `ui-motion.md`. Both follow the same rule that motion has
a budget. `CameraPath.MAX_SECONDS` is 30, and most shots should be 0.7–3.5 s.

```lua
local CameraPath = require(ReplicatedStorage.CameraPath)
local handle = CameraPath.play({
	{ time = 1.0, position = hero.Position + Vector3.new(0, 24, 30), lookAt = hero.Position, fov = 62, dir = Enum.EasingDirection.In },
	{ time = 2.2, position = gate.Position + Vector3.new(40, 20, 0), lookAt = gate.Position, ease = Enum.EasingStyle.Linear },
	{ time = 3.5, cframe = function(subject) return subject * CFrame.new(0, 3, 12) end, dir = Enum.EasingDirection.Out },
}, { blendBack = 0.35, hideGuis = true, onFinished = function(completed) end })
```

| Key field | Meaning |
| --- | --- |
| `time` | seconds from the start. A first key later than 0 starts from the current camera; a key at 0 is a cut |
| `cframe` | a CFrame, or a function of the live subject's CFrame (default: the character root) |
| `position` + `lookAt` | instead of `cframe`: Vector3s or functions of the subject. The aim point is interpolated and looked at every frame |
| `fov` | defaults to the previous key's |
| `ease` / `dir` | easing of the segment arriving at this key; default Cubic InOut |
| `cut` | hold the previous pose, then jump here at `time` |

The maths behind it:

- Positions follow a **centripetal** Catmull-Rom spline (Barry-Goldman, alpha 0.5). The uniform kind
  loops and cusps when keys bunch up or double back; the centripetal kind cannot.
- Each segment is eased by its arriving key. Cubic InOut starts and settles each beat. For a sweep that
  should keep its speed through the keys, use Cubic **In** on the first segment, Linear in the middle
  and Cubic **Out** on the last. The source build moved its shots from Sine to Cubic easing in its
  motion pass; Cubic's firmer start and settle is the default here for that reason.
- Poses are evaluated every frame, never baked, so a key that is a function of the subject keeps up
  with a running player.
- Do not ease across a very long distance (the source build's example was 220 studs to a boss): it is a
  whip-pan. Cut in, drift, and cut back.

Options: `subject`, `blendBack` (0.35 s ease from the last pose into the live camera), `hideGuis`,
`priority` (default `RenderPriority.Camera + 1`, after the default camera scripts), `onFinished`.
`play()` replaces a running shot. `stop()` ends everything at once.

Ownership: the render step is bound only while a shot or blend runs. `CameraType` and `FieldOfView`
are recorded as `ForgeGUIPrior_CameraType` / `ForgeGUIPrior_FieldOfView` on the Camera (the first shot
of a chain wins), and `CameraSubject` is kept in module state. Every ScreenGui it hides gets
`ForgeGUIPrior_Enabled` and `ForgeGUICameraPath = true`. All of it is handed back when the shot ends
or on `stop()`.

## Performance

- Everything is built once and reused; per frame only CFrames move. WindVfx holds 14 trails, 4 ridge
  emitters and 3 dust emitters by default. Its raycasts are 2 every 0.3 s (ground and roof), 1 per
  ribbon every 0.25 s, and 36 every 1.5 s for the ridge scan.
- FoliageSway moves at most 60 plants in a single `BulkMoveTo`. Far plants update at half rate.
- Measured on the source build, a desert MMO with this stack plus fire, reflections, contact shadows
  and ground patches, on High: about 6 ms median frame time in an open yard with about 60 ground
  patches, and about 11 ms in a dense town. The wind modules were not timed on their own. If you need
  a number for them, profile with the MicroProfiler while toggling `stop()`/`start()`.
- `quality = 0.5` halves WindVfx counts and rates for a low-end preset. The source build's automatic
  graphics preset chose High below 18 ms median frame time, Medium below 26 ms, and Low above that.

## Verification

1. Regressions (Studio MCP `execute_luau`, Edit mode). Paste each module with its runner:
   `python references/tools/paste_module.py references/luau/Wind.luau docs/evidence/wind-regression.luau`.
   Do the same for `wind-vfx-`, `foliage-sway-` and `camera-path-regression.luau`. Each prints
   `N checks passed` or raises with the failing check. The camera regression's second half needs a
   Client context in Play; elsewhere it says it was skipped.
2. In Play, on the client: `Workspace.GlobalWind` changes over 10–20 s; there is exactly one
   `ForgeGUI_WindVfx` folder; tagged plants' parts carry `ForgeGUIFoliageSway` only near the camera.
   Capture a sunlit open area and a shaded one: ribbons and motes should show in sun and vanish in shade.
3. Hold the camera for the capture. `screen_capture` lands 3–5 s after the call, and Studio redraws only
   while its window is in front. Use the pinned-camera recipe in `lighting-lab.md`, and compare the same
   shot with `WindVfx.stop()` and after `start()`.
4. Play a camera shot, capture mid-shot, and check afterwards that `CameraType` is `Custom` again and no
   ScreenGui is left disabled.
5. Do not verify by calling `start()` from `execute_luau` while the game runs: each `execute_luau`
   context gets its own module instances. A second WindVfx copy's `start()` would sweep the game's
   owned folder, and the check would test the copy, not the game. Inspect the live instances, or drive
   the real UI, instead.
