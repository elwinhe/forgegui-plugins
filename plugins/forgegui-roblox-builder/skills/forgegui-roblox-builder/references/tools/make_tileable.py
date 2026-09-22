#!/usr/bin/env python3
"""Make a generated material image tile without a visible seam.

    python3 tools/make_tileable.py raw.png out.png --mode blend
    python3 tools/make_tileable.py raw.png out.png --mode mirror

Only fully opaque inputs are supported; transparent inputs are rejected before output is written.

Two methods, because each fails on the other's material:

mirror  2x2 of the image and its reflections. Seam-exact by construction, and
        right for REGULAR patterns (corrugated sheet, formwork panels, planks)
        where the reflection is indistinguishable from the pattern.
        On ORGANIC materials it is wrong: every crack and stain meets its own
        reflection, and the eye reads the result as a kaleidoscope.

blend   the image cross-faded with a copy of itself rolled by half its size.
        The rolled copy is continuous across the outer edge (its edge is the
        original's middle); the original is kept in the centre, where the
        rolled copy carries the wrap seam. Right for organic materials
        (asphalt, dirt, plaster, rust). On regular patterns it ghosts, because
        the two copies' lines do not register.
"""
import argparse
import numpy as np
from PIL import Image, ImageOps


def opaque_rgb(im: Image.Image) -> Image.Image:
    if im.convert("RGBA").getchannel("A").getextrema() != (255, 255):
        raise ValueError("Tile preparation requires fully opaque input; transparency is not supported")
    return im.convert("RGB")


def square(im: Image.Image, size: int) -> Image.Image:
    w, h = im.size
    s = min(w, h)
    box = ((w - s) // 2, (h - s) // 2, (w - s) // 2 + s, (h - s) // 2 + s)
    return im.crop(box).resize((size, size), Image.LANCZOS)


def mirror(im: Image.Image, size: int) -> Image.Image:
    q = square(opaque_rgb(im), size // 2)
    out = Image.new("RGB", (size, size))
    out.paste(q, (0, 0))
    out.paste(ImageOps.mirror(q), (size // 2, 0))
    out.paste(ImageOps.flip(q), (0, size // 2))
    out.paste(ImageOps.flip(ImageOps.mirror(q)), (size // 2, size // 2))
    return out


def blend(im: Image.Image, size: int) -> Image.Image:
    a = np.asarray(square(opaque_rgb(im), size), dtype=np.float32)
    # Flatten large-scale lighting first: a vignette or gradient the eye cannot
    # see in one tile becomes an obvious checkerboard across forty of them.
    low = np.asarray(Image.fromarray(a.astype(np.uint8)).resize((8, 8), Image.BILINEAR)
                     .resize((size, size), Image.BICUBIC), dtype=np.float32)
    a = np.clip(a - low + low.mean(axis=(0, 1), keepdims=True), 0, 255)
    rolled = np.roll(a, (size // 2, size // 2), axis=(0, 1))
    ramp = 1 - np.abs(np.linspace(-1, 1, size))           # 1 at centre, 0 at edge
    mask = np.minimum.outer(ramp, ramp)                    # square falloff
    mask = np.clip((mask - 0.12) / 0.5, 0, 1)
    mask = (mask * mask * (3 - 2 * mask))[..., None]       # smoothstep
    return Image.fromarray(np.clip(a * mask + rolled * (1 - mask), 0, 255).astype(np.uint8))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--mode", choices=("mirror", "blend"), required=True)
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--preview", help="also write a 3x3 tiling here, to look at before uploading")
    args = ap.parse_args()

    with Image.open(args.src) as source:
        try:
            im = opaque_rgb(source)
        except ValueError as exc:
            ap.error(str(exc))
    out = mirror(im, args.size) if args.mode == "mirror" else blend(im, args.size)
    out.save(args.out)
    if args.preview:
        t = out.resize((256, 256), Image.LANCZOS)
        sheet = Image.new("RGB", (768, 768))
        for y in range(3):
            for x in range(3):
                sheet.paste(t, (x * 256, y * 256))
        sheet.save(args.preview)
    print(f"{args.out}  {args.mode}  {out.size[0]}x{out.size[1]}")


if __name__ == "__main__":
    main()
