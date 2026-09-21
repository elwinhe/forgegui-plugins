# Textures on generated surfaces

Two different things get called "texture" in a Roblox build, and the skill has to keep them apart:

- **Baked maps** that arrive inside a generated mesh as a `SurfaceAppearance.ColorMap`. You get these
  for free with the mesh and they cannot be tiled or reused.
- **Standalone textures** you generate as an image, upload, and apply to a surface yourself. These are
  what "surfaces carry generated textures" normally means, and they are the ones that need work.

A build made only of the first kind still looks textured, but nothing in it is a texturing decision.
State which kind a surface uses when it matters.

## Generating one

`generation_image` with `type: "mixed"`. Do not use `pixel_texture` — despite the name it returns
pixel art, which is not what "texture" means to a Roblox builder.

Two measured properties of the output, both of which need handling before upload:

1. **The image comes back with a black frame.** The usable tile is the inner square. Crop it or the
   frame tiles across the surface as a grid of dark lines.
2. **Nothing guarantees the result tiles.** Opposite edges are not matched. Check before you commit a
   texture to a large surface, and expect a visible seam if you do not.

`scripts/texture_prep.py` does the crop and reports the edge mismatch, so both are one command:

```sh
python3 scripts/texture_prep.py raw.png out.png --size 1024
```

It prints the cropped frame width and a **tile mismatch** figure: the mean channel difference between
opposite edges, next to the difference between ordinary neighbouring columns. A mismatch near the
neighbour figure tiles cleanly; several times higher will show a seam. `--selftest` covers both.

Two things the figure cannot tell you. A flat or near-uniform image reports 0.0 against 0.0 and
"passes" trivially — read the numbers, not just the verdict. And a texture can tile perfectly and
still look wrong at the scale you apply it. Measured on real generator output: raw returns carried
frames of 234 px and 125 px, and one texture that shipped in a build reported a mismatch of 103.6
against a neighbour difference of 20.0 — it tiles with a seam, which nobody noticed until this
check existed.

Also note a multi-image request can return something unrelated to the prompt — a `mixed` request for a
panorama once returned a coin. Look at every image in a `count > 1` return.

## Applying one

`run_code` runs at plugin security, so textures are scriptable — no manual pass in the Studio UI:

| Target | Property | Verified |
| --- | --- | --- |
| `SurfaceAppearance` | `ColorMap` / `ColorMapContent`, `NormalMap` | written and read back |
| `MaterialVariant` | `ColorMap` / `ColorMapContent` | written and read back |
| `MeshPart` | `TextureID` | written and read back |
| `Part` | `MaterialVariant` | written and read back |

Every write above returned the asset id on readback. A `LocalScript` reading the same property raises a
capability error in the same place, so do this from `run_code` or a server script, never client-side.

For a tiling surface use a `Texture` with `StudsPerTileU` / `StudsPerTileV` rather than a `Decal`, and
size the tile from the surface: at 1024 px a 12-stud tile gives about 85 px per stud, which reads sharp
at walking distance. Roblox resamples image assets down to fit 1024 on a side, so generating larger
than that buys nothing and costs an extra resample.

## Check before you call it done

Look at the surface in Play, not in Edit, at the distance a player sees it. A tiling error is invisible
in a close-up and obvious across a floor.
