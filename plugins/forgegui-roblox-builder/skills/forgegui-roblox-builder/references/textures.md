# Textures on generated surfaces

Two different things get called "texture", and a build has to keep them apart:

- **Baked maps** that arrive inside a generated mesh as a `SurfaceAppearance.ColorMap`. You get
  these free with the mesh; they cannot be tiled or reused.
- **Standalone textures** you generate as an image, upload, and apply to a surface yourself.

A build made only of the first kind still looks textured while containing no texturing decision.
Say which kind a surface uses when it matters.

## 1. Generate

Use `generation_image` type `thumbnail` for materials (see the generator-behaviour notes in
SKILL.md §5 for the measured comparison against `mixed`). Ask for a flat, straight-on, top-down
view, even lighting, no shadow or vignette, uniform density across the frame, no border and no
object.

Two properties of the output to handle before it reaches a surface:

1. **Some types return the tile inside a dark border.** Crop it, or the border tiles across the
   surface as a grid of dark lines.
2. **Nothing is guaranteed to tile**, whatever the prompt says. Check the wrap before committing a
   texture to a large surface.

## 2. Prepare

```sh
python3 scripts/texture_prep.py raw.png tile.png --size 1024
```

Crops the border and prints the **wrap difference** next to the ordinary neighbouring-pixel
difference, so the figure is interpretable rather than a bare number. A wrap near the neighbour
figure tiles; several times higher shows a seam. It preserves alpha, warns when a non-square crop
would be distorted by the resize, and `--selftest` covers all of it.

Read the two numbers, not just the verdict. A flat or near-uniform image has nothing to judge and
says so. Measured on real generator output: raw returns carried borders of roughly 90-100 px per
side (`tex-chevron-raw.png`, `tex-stand-seats-raw.png`), and three textures already shipped in a
finished build report a wrap several times their neighbour figure -- they tile with a seam that
nobody had noticed, because a tiling error is invisible in a close-up.

**Colour mode matters here.** A generated texture may arrive RGBA with its artwork entirely in the
alpha channel. Any step that flattens to RGB destroys it, and the flattened result reads as uniform
and then passes a naive tiling check. Check the mode before processing.

If a texture does not tile, repair it before upload rather than living with the seam.

## 3. Upload

Upload the prepared PNG as `assetType: "Image"` (SKILL.md §4). Everything below takes the returned
asset id. Roblox resamples image assets down to fit 1024 on a side -- measured when a HUD plate
stored at 1774 px forced its `ImageRect` to be scaled by 1024/1774 -- so generating larger buys
nothing and costs a resample.

## 4. Apply

`run_code` runs at plugin security, so textures are scriptable and need no manual pass in the Studio
UI. The properties that accept a write and return the id on readback are listed in SKILL.md §4 under
the textures and materials route: `SurfaceAppearance` (`ColorMap` / `NormalMap` and their `Content`
forms), `MaterialVariant`, `MeshPart.TextureID` and `Part.MaterialVariant`.

Two practical notes that route does not cover:

- **`ColorMap` or `ColorMapContent`?** Both accepted a write and read the id back. Which one the
  current engine prefers was not established here; write the plain form, read it back, and fall back
  to the `Content` form if the readback is empty.
- Do this from `run_code` or a server script. A client-side read of the same property was **reported**
  to raise a capability error by a separate pass and was not reproduced here -- the instruction stands
  on the security model rather than on that report.

For a tiling surface use a `Texture` with `StudsPerTileU` / `StudsPerTileV` rather than a `Decal`,
and size the tile from the surface: at 1024 px a 12-stud tile gives about 85 px per stud.

## Check before you call it done

- the property you wrote reads back the id you set
- `StudsPerTileU` / `StudsPerTileV` are the values you intended
- the surface is viewed **in Play, across its full extent**, not in a close-up in Edit
