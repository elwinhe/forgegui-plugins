# Surface realism: ground and buildings that do not read flat

Use this after the world is built and lit, when the camera near the ground shows flat paint
(terrain, paving, cracked earth) or generated buildings go blocky up close, and whenever a
scatter pass places props among buildings. It covers five pieces, which work together:

| Piece | File | Fixes |
| --- | --- | --- |
| PBR maps from a colour tile | `tools/pbr_maps.py` | flat materials: height, normal, roughness and a cavity-baked colour map |
| Material kit | `luau/MaterialKit.luau` | stock Roblox materials; applies the maps as MaterialVariants, reversibly |
| Ground scatter | `luau/GroundScatter.luau` | close-up terrain that reads as a print: real 3D patches near the camera |
| Detail grain | `luau/DetailGrain.luau`, `tools/make_grain.py` | one stretched texture on a generated building |
| Keep-out | `luau/KeepOut.luau`, `WorldCheck` `clutter` | crates, rocks and trees inside buildings or walkways |

## What was measured

These come from a desert build finished on 2026-09-22/23. The numbers are from that build, on
High, with the full lighting and effects stack.

- **Terrain cannot displace a texture.** Close-up ground reads flat whatever the normal map. No
  terrain or MaterialVariant setting changes this: MaterialVariant has ColorMap, NormalMap,
  RoughnessMap and MetalnessMap, and no height input.
- **What fixed flat ground.** The build used all three together:
  1. Real 3D ground patches (GroundScatter) near the camera on the materials that need relief
     (cracked earth, gravel). This is the only piece that adds real geometry. Everything else only
     changes shading.
  2. Macro relief in the terrain heightmap itself (below), so open ground has lumps and ripples at
     the 1-60 stud scale instead of a plane.
  3. Materials whose colour map has the relief baked in (`--cavity`) plus a height-derived normal
     map, so the relief still shows where the normal map is lit flat (shadow, overcast, far LOD).
- **Footprint rule.** A grid-snapped 12-stud patch must be laid only where its whole footprint
  (centre and the four corners of its own box, where it will actually stand) is the same terrain
  material. The roads were about 14 studs wide.
  Without the rule, most road patches straddled the edge and read as loose tiles strewn over the
  sand. With it, narrow strips get none, and that looks right.
- **Tiling test on a generated building (A/B/C, side by side, same light):** A was the bare mesh
  with one 1024 px texture, which went blocky up close. B was fine grain: two neutral tiled
  overlays, dark at Transparency 0.15 and light at 0.3, 3 studs per tile. C was a tiled mudbrick
  colour map blended over the mesh, 10 studs per tile at 0.55. **B beat both.** C washed out the
  building's own baked detail. B shipped on every building.
- **Cost:** about 60 ground patches in view in an open area gave a **6 ms median frame**. A dense
  town with grain on every building gave about **11 ms median**. Neither piece was measured on its
  own. The build's auto graphics preset stepped down at 18 ms (High) and 26 ms (Medium).

## 1. PBR maps (`references/tools/pbr_maps.py`)

Start from a colour tile that already wraps (`scripts/texture_prep.py` to crop and measure,
`references/tools/make_tileable.py` to repair). All filters wrap, so the maps tile like the colour.

```sh
python3 references/tools/pbr_maps.py sand.png maps/ --medium 1 --cavity 0.6
python3 references/tools/pbr_maps.py earth.png maps/ --plates 6 --cavity 0.7 --strength 5
python3 references/tools/pbr_maps.py --selftest
```

| Flag | Default | Use |
| --- | --- | --- |
| `--size` | 1024 | Roblox stores images at no more than 1024 px on a side, so larger buys nothing |
| `--strength` | 4 | normal-map slope gain. 3-6 for ground, lower for plaster |
| `--rough` | 0.8 | base roughness. Crevices come out rougher, tops smoother |
| `--detail` | 0.35 | fine grain in the height |
| `--medium` | 0 | the 1/128-1/20-of-tile band: sand ripples, plate edges, ledges. **Without it, ripples read flat**, because the wide high-pass throws that band away |
| `--plates R` | 0 | cracked earth, flagstones, brick: plates between dark crack lines are raised and bevelled over R px |
| `--crack` | 14 | percentile of local darkness treated as crack, for `--plates` |
| `--cavity C` | 0 | writes `_cavity.png`, the colour with crevices darkened and crests lifted. **Use it as the ColorMap** |
| `--sharpen S` | 0 | unsharp mask on the colour first, for sources that were upscaled |

It writes `<stem>_height.png` (kept for you, since Roblox has no height input), `_normal.png`
(OpenGL, +Y up, which is what Roblox reads), `_rough.png` and `_cavity.png`. Upload the
cavity, normal and roughness maps as Image assets (SKILL.md §4).

## 2. Material kit (`references/luau/MaterialKit.luau`)

```lua
local report = MaterialKit.apply({
	{ name = "Kit_Ground", base = Enum.Material.Ground, colorMap = cavityId, normalMap = normalId,
	  roughnessMap = roughId, studsPerTile = 16, terrainColor = Color3.fromRGB(255, 244, 230),
	  pattern = Enum.MaterialPattern.Organic },
	{ name = "Kit_Masonry", base = Enum.Material.Sandstone, colorMap = blocksId, studsPerTile = 12, override = false },
})
-- report.created / updated / skipped / failed; MaterialKit.clear() restores the place.
```

| Field | Default | Meaning |
| --- | --- | --- |
| `override` | true | `SetBaseMaterialOverride`: every part and voxel of `base` uses it, including terrain written later |
| `terrainColor` | none | `Terrain:SetMaterialColor`. It multiplies the colour map, so keep it near white (225-255 per channel) |
| `studsPerTile` | 12 | shipped values: ground 12-18, rock faces 26-40, walls 12, wood and cloth 6 |
| `pattern` | Regular | Organic varies the tiling on natural ground |

With `override = false` the variant applies only where a part sets `MaterialVariant = name`. Use
it for a second look on the same base material, for example dressed masonry walls next to
cliff-strata rock. The module owns what it creates (`ForgeGUIMaterialKit`) and records the prior
override and terrain colour on MaterialService and Terrain, so `clear()` hands them back.

## 3. Macro relief in the terrain heightmap

A heightmap made only of large forms (dunes, mesas) plus flattened play areas still reads as a
plane at eye level. Add relief below the large-form scale, in studs, before you flatten the areas
that must stay level:

```
breakup = fbm(x, z, scale 38, 3 octaves) * 1.1 + fbm(x, z, scale 14, 2 octaves) * 0.35
u       = (x cos a + z sin a + fbm(x, z, 60, 2) * 9) / 14        -- ripples 14 studs apart, warped
ripple  = sin(2 pi u) * 0.5 + sin(4 pi u + 1.3) * 0.12
patch   = smoothstep((fbm(x, z, 110, 2) + 0.2) / 0.6)              -- ripple fields, not a carpet
h      += breakup + ripple * 0.55 * patch * sandiness
```

Lumps and hollows 20-60 studs across reach up to about a stud everywhere. Ripples run across the
prevailing wind (angle `a`), only on loose material (`sandiness` is 0 on rock). Areas that must be
level should still keep a trodden unevenness of about 0.7 stud over 16 studs, so they never become
perfect planes. Terrain voxels are 4 studs, and anything finer than about 2 studs is lost: that
scale belongs to the normal map and the ground scatter.

## 4. Ground scatter (`references/luau/GroundScatter.luau`)

```lua
-- LocalScript
GroundScatter.start({
	kinds = { [Enum.Material.Ground] = { template = ReplicatedStorage.Assets.MudPlates, tint = Color3.fromRGB(214, 196, 178) } },
})
```

The template is a generated model (ForgeGUI `generation_model_3d`): a low, wide patch about
12 studs square and under half a stud tall, with no ground plane. Ask for "low and wide, about
12 feet across and 4 inches tall, single object, no ground plane".

| Setting | Default | Meaning |
| --- | --- | --- |
| `cell` | 10.5 | world-snapped cell size, a little under the patch width so neighbours overlap |
| `radius` / `leaveRadius` | 64 / radius + 8 | laid within, returned to the pool beyond |
| `protrude` | 0.45 | studs of the patch's top standing above the terrain; the rest is sunk into it |
| `minUp` | 0.86 | ground steeper than this normal.Y (cliffs, banks) gets none |
| `footprint` | 0.5 x each template side | full half-extents of the transformed bounding-box corner test: 6 x 6 for a 12-stud patch, 6 x 3 for a 12 x 6 one. A number overrides both axes; smaller values intentionally permit edge overhang. Centre/corner sampling does not detect material holes between probes |
| `cellsPerFrame` | 12 | cells checked per frame, five rays each |
| `jitter` | 0.3 | per-cell offset as a fraction of the cell |
| `castTop` / `castDepth` | castDepth / 2 above the focus / 800 | where the downward rays start and how far they reach. Leave `castTop` unset unless the ground sits in a fixed height band |
| `tint` | none | `SurfaceAppearance.Color`. Generated maps come out warmer and brighter than graded terrain |
| `manual` | false | no Heartbeat. Call `GroundScatter.step(focus)` yourself |

Jitter and yaw come from a hash of the cell coordinates, so a patch returns to the same place and
never swims. A cell whose rays meet no terrain (on a client, terrain that has not streamed in
yet) is tried again about once a second while it stays in reach, up to five times, then left
empty; `stats().retrying` counts those cells. Patches are anchored and have no collision, query or touch. `stop()` destroys only
what it made (`ForgeGUIGroundScatter`). Cells are keyed by Vector3. Vector2 is userdata and does
not work as a table key: a lookup with a new Vector2 misses, and cells would be laid twice after a
re-plan. The regression checks this.

## 5. Detail grain on buildings (`references/luau/DetailGrain.luau`)

```sh
python3 references/tools/make_grain.py grain/          # grain_dark.png + grain_light.png, 512 px
python3 references/tools/make_grain.py --selftest
```

```lua
DetailGrain.apply(workspace.World.Buildings, { layers = DetailGrain.grain(darkId, lightId) })
DetailGrain.apply(plainShed, { layers = DetailGrain.blend(brickId, 10, 0.55) })  -- C, for low-detail meshes
DetailGrain.clear(workspace.World.Buildings)
```

The grain PNGs are neutral (black and white) with the pattern in alpha. They are band-limited
noise built in the frequency domain, so they tile exactly and have no blotch that would repeat
every 3 studs. `--scale` changes the grain size, `--contrast` the alpha and `--pits` the dust pits.
`apply` covers the five visible faces of every MeshPart (`classes` widens it), 10 Textures per
part, and replaces its own layers rather than stacking. Judge any change the way the original was
judged: A, B and C side by side in one capture.

## 6. Keep-out (`references/luau/KeepOut.luau`) and the overlap check

```lua
local zone = KeepOut.new({ trunkShare = { palm = 0.12, acacia = 0.12, deadtree = 0.15 } })
zone.collect(workspace.World, function(m) return m:GetAttribute("Kind") == "Building" end)
zone.registerPassage(gatehouse, "X", 14, 5)        -- keep a gate's walkway clear, 14 studs out each side
model:PivotTo(spot)
if zone.blockedModel(model) then model:Destroy() else model.Parent = props end
```

Rules: a prop's box is shrunk to 0.7 first, so leaning on a wall is fine and standing inside it is
not. Trees are tested by the trunk (X and Z at the trunk share, from `trunkShare` or a
`KeepOutTrunk` attribute), so a crown may overhang a roof. The trunk probe is centred on the
model's bounds, which a leaning trunk or one-sided crown pulls off the trunk: give such a tree an
Attachment named `KeepOutTrunk` at the foot of its trunk and the probe is centred there. Boxes are oriented, so rotated walls
are tested exactly. When one section of a world is rebuilt, `reset()` and `collect()` again, so
the zone still sees the buildings the other sections made.

After the fact, `WorldCheck.run({ clutter = props, keepOut = zone })` reports `clutter_overlap`
(error) for any prop whose shrunk box overlaps a collidable part or, when given the zone, stands
in one of its footprints or passages. A passage is a virtual box with nothing collidable in it, so
without `keepOut` a prop blocking a gate walkway is not reported. It uses the same 0.7 shrink and
`KeepOutTrunk` attribute and attachment. Terrain never counts, because props are sunk into it on
purpose. Mark an intended overlap `AllowOverlap = true`.

## What failed (do not repeat)

- Relying on the normal map for terrain relief. However strong, the ground still read flat.
- A height map made from a wide high-pass alone. Ripples and ledges came out flat until the
  medium band (`--medium`) was added.
- A tiled material blended over generated buildings (C). It washed out the baked detail.
- Grid-snapped patches without the footprint test. They straddled road edges as loose tiles.
- Keying laid cells by `Vector2`. Luau compares `Vector2` table keys by identity (measured:
  `{[Vector2.new(1, 2)] = true}[Vector2.new(1, 2)]` is nil), so every re-plan laid the same
  cells again and stacked patches. `Vector3` keys compare by value; GroundScatter uses them.
- Starting the scatter in the same frame the terrain is written. Measured: terrain from
  `FillBlock` is not raycastable until the next physics step, so every cell was recorded as
  empty and stayed empty until it left the radius. A ray that meets no terrain is now retried a
  few times, but generate the terrain first, wait a frame (or until a probe ray hits it), then
  `start`.

## Verify

1. Run `docs/evidence/surface-realism-regression.luau` (paste the four modules ahead of it with
   `paste_module.py`, as its header shows) in Edit in a test place. It prints `PASS ...`.
2. In Play, capture the ground from standing height on each material you scattered, on a road
   edge, and on a slope. Every patch must sit inside its material, none on a narrow strip, none
   floating.
3. Capture a building from 3 studs and from 40 studs. The grain must show as surface detail with
   no visible 3-stud repeat, and the building's colours must be unchanged.
4. Read the frame time where the most patches are in view (`GroundScatter.stats().patches`) and
   in the densest built area. Compare with the 6 ms and 11 ms figures above.
5. Run `WorldCheck` with `clutter` set to the scattered props and `keepOut` set to the zone.
   There must be no `clutter_overlap` or `clutter_unchecked`.
