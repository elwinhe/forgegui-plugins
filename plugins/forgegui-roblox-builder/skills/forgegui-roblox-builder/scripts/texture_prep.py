#!/usr/bin/env python3
"""Crop a generated texture's border and measure whether it tiles.

usage: texture_prep.py <in.png> <out.png> [--size 1024]
       texture_prep.py --selftest

numpy + Pillow only.

Some `generation_image` types return the tile inside a dark border, and nothing from any type is
guaranteed to tile. Both problems are invisible in a close-up and obvious across a floor, so crop
the border and report the mismatch before the texture reaches a surface.

Alpha is preserved end to end. A texture whose artwork lives entirely in its alpha channel is
destroyed by a step that flattens to RGB, and the flattened result reads as uniform -- which then
passes a naive tiling check. Measurement here uses alpha as a channel so such a texture is judged
on the art that is actually in it.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# Real borders measured on generator output are exactly 0.0 mean, and genuine content starts
# around 66. A near-zero threshold therefore finds every real border without eating dark art;
# a higher value silently crops content, which cost a false positive on a real texture.
DARK = 1.0
# A wrap difference this many times the ordinary neighbour difference reads as a seam. Judged by
# eye against a handful of textures, not calibrated -- print both numbers and trust those.
SEAM_RATIO = 3.0


def crop_border(a):
    """Drop uniformly dark rows and columns from each edge. Returns (array, (top, bottom, left, right))."""
    lum = a[..., :3].mean(axis=2) if a.shape[2] >= 3 else a[..., 0]
    top, bottom = 0, a.shape[0]
    while top < bottom and lum[top].mean() < DARK:
        top += 1
    while bottom > top and lum[bottom - 1].mean() < DARK:
        bottom -= 1
    left, right = 0, a.shape[1]
    while left < right and lum[:, left].mean() < DARK:
        left += 1
    while right > left and lum[:, right - 1].mean() < DARK:
        right -= 1
    if bottom - top < 8 or right - left < 8:
        return a, (0, 0, 0, 0)
    return a[top:bottom, left:right], (top, a.shape[0] - bottom, left, a.shape[1] - right)


def tile_mismatch(a):
    """(wrap mismatch, ordinary neighbour difference). Comparable numbers mean it tiles.

    Both are means over every channel present, so alpha-only artwork is measured rather than
    ignored. The neighbour figure averages every adjacent pair in the image, not one edge pair.
    """
    if a.shape[0] < 2 or a.shape[1] < 2:
        return 0.0, 0.0
    wrap = max(float(np.abs(a[:, 0] - a[:, -1]).mean()), float(np.abs(a[0] - a[-1]).mean()))
    neighbour = float((np.abs(np.diff(a, axis=1)).mean() + np.abs(np.diff(a, axis=0)).mean()) / 2)
    return wrap, neighbour


def main(src, out, size=1024):
    if not Path(src).is_file():
        sys.exit(f"error: no such file: {src}")
    try:
        im = Image.open(src)
    except Exception as exc:
        sys.exit(f"error: cannot read {src}: {exc}")
    mode = "RGBA" if "A" in im.getbands() else "RGB"
    a = np.asarray(im.convert(mode), np.float32)

    a, (t, b, l, r) = crop_border(a)
    wrap, neighbour = tile_mismatch(a)

    h, w = a.shape[:2]
    if h != w:
        print(f"note: cropped region is {w}x{h}, not square; resizing to {size}x{size} will "
              f"distort it. Crop to a square first if the tile must keep its proportions.")
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), mode).resize((size, size), Image.LANCZOS).save(out)

    verdict = "tiles cleanly" if neighbour > 0 and wrap <= neighbour * SEAM_RATIO else (
        "flat or near-uniform, nothing to judge" if neighbour == 0 else "WILL SHOW A SEAM")
    border = f"{t},{b},{l},{r}" if any((t, b, l, r)) else "none"
    print(f"{out} {size}x{size} {mode}  border(t,b,l,r)={border}  "
          f"wrap {wrap:.1f} vs neighbour {neighbour:.1f}  -> {verdict}")


def selftest():
    n = 200
    x = (np.arange(n) + 0.5) / n * 2 * np.pi
    tile = np.repeat((np.cos(x) * 50 + 140)[None, :, None], 3, 2).astype(np.float32)
    tile = np.repeat(tile, n, 0)

    bordered = np.zeros((n + 40, n + 60, 3), np.float32)
    bordered[20:-20, 30:-30] = tile
    out, sides = crop_border(bordered)
    assert sides == (20, 20, 30, 30), f"border should be 20/20/30/30, got {sides}"
    assert out.shape[:2] == (n, n), f"crop should be {n}x{n}, got {out.shape[:2]}"

    wrap, nb = tile_mismatch(out)
    assert wrap <= nb * SEAM_RATIO, f"a seamless tile must not be flagged ({wrap:.1f} vs {nb:.1f})"

    broken = out.copy()
    broken[:, n // 2:] += 40.0
    wb, nbb = tile_mismatch(broken)
    assert wb > nbb * SEAM_RATIO, f"a stepped tile must be flagged ({wb:.1f} vs {nbb:.1f})"

    same, sides2 = crop_border(tile)
    assert sides2 == (0, 0, 0, 0) and same.shape == tile.shape, "an unbordered image must pass through"

    # Artwork living only in alpha must still be measured, not read as uniform.
    alpha_only = np.full((n, n, 4), 255.0, np.float32)
    alpha_only[..., 3] = np.repeat((np.cos(x) * 120 + 128)[None, :], n, 0)
    w_a, nb_a = tile_mismatch(alpha_only)
    assert nb_a > 0, "alpha-only artwork must register a non-zero neighbour difference"
    alpha_broken = alpha_only.copy()
    alpha_broken[:, n // 2:, 3] = 0.0
    w_b, nb_b = tile_mismatch(alpha_broken)
    assert w_b > nb_b * SEAM_RATIO, "a seam in the alpha channel must be flagged"

    # Degenerate sizes must not raise.
    assert tile_mismatch(np.zeros((1, 1, 3), np.float32)) == (0.0, 0.0), "1x1 must not raise"
    assert tile_mismatch(np.zeros((1, 50, 3), np.float32)) == (0.0, 0.0), "1-row must not raise"

    print("selftest ok: border cropped per side, seamless passes, stepped flagged, "
          "unbordered untouched, alpha measured, degenerate sizes safe")


if __name__ == "__main__":
    a = sys.argv[1:]
    if a == ["--selftest"]:
        selftest()
    elif len(a) >= 2 and not a[0].startswith("--"):
        size = 1024
        if "--size" in a:
            i = a.index("--size")
            if i + 1 >= len(a):
                sys.exit("error: --size takes a number, e.g. --size 512")
            try:
                size = int(a[i + 1])
            except ValueError:
                sys.exit(f"error: --size takes a whole number, got {a[i + 1]!r}")
        main(a[0], a[1], size)
    else:
        sys.exit(__doc__)
