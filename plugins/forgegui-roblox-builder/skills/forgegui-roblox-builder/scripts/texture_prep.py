#!/usr/bin/env python3
"""Crop a generated texture's frame and measure whether it tiles.

usage: texture_prep.py <in.png> <out.png> [--size 1024]
       texture_prep.py --selftest

`generation_image` with type `mixed` returns a painted tile inside a dark frame, and nothing
guarantees its opposite edges match. Both problems are invisible in a close-up and obvious across a
floor, so crop the frame and report the mismatch before the texture reaches a surface.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# A frame is detected as uniformly dark rows and columns, which is what the generator emits.
# If a future model returns a light frame, compare against the image median instead of a constant.
DARK = 28.0


def crop_frame(a):
    """Drop uniformly dark rows and columns from each edge. Returns (array, pixels removed)."""
    def keep(line):
        return line.mean() > DARK
    top, bottom = 0, a.shape[0]
    while top < bottom and not keep(a[top]):
        top += 1
    while bottom > top and not keep(a[bottom - 1]):
        bottom -= 1
    left, right = 0, a.shape[1]
    while left < right and not keep(a[:, left]):
        left += 1
    while right > left and not keep(a[:, right - 1]):
        right -= 1
    if bottom - top < 8 or right - left < 8:
        return a, 0
    return a[top:bottom, left:right], max(top, a.shape[0] - bottom, left, a.shape[1] - right)


def tile_mismatch(a):
    """(edge mismatch, ordinary neighbour difference). Comparable numbers mean it tiles."""
    horiz = np.abs(a[:, 0] - a[:, -1]).mean()
    vert = np.abs(a[0] - a[-1]).mean()
    neighbour = (np.abs(a[:, 1] - a[:, 0]).mean() + np.abs(a[1] - a[0]).mean()) / 2
    return max(horiz, vert), neighbour


def main(src, out, size=1024):
    a = np.asarray(Image.open(src).convert("RGB"), np.float32)
    a, framed = crop_frame(a)
    mismatch, neighbour = tile_mismatch(a)
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).resize((size, size), Image.LANCZOS)
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    im.save(out)
    verdict = "tiles cleanly" if mismatch <= neighbour * 3 else "WILL SHOW A SEAM"
    print(f"{out} {size}x{size}  frame cropped {framed}px  "
          f"tile mismatch {mismatch:.1f} vs neighbour {neighbour:.1f}  -> {verdict}")


def selftest():
    n = 200
    x = (np.arange(n) + 0.5) / n * 2 * np.pi
    tile = np.repeat((np.cos(x) * 50 + 140)[None, :, None], 3, 2).astype(np.float32)
    tile = np.repeat(tile, n, 0)
    framed = np.zeros((n + 40, n + 40, 3), np.float32)
    framed[20:-20, 20:-20] = tile

    out, px = crop_frame(framed)
    assert px == 20, f"frame width should be 20, got {px}"
    assert out.shape[:2] == (n, n), f"crop should be {n}x{n}, got {out.shape[:2]}"

    m, nb = tile_mismatch(out)
    assert m <= nb * 3, f"a seamless tile must not be flagged ({m:.1f} vs {nb:.1f})"

    broken = out.copy()
    broken[:, n // 2:] += 40.0
    mb, nbb = tile_mismatch(broken)
    assert mb > nbb * 3, f"a stepped tile must be flagged ({mb:.1f} vs {nbb:.1f})"

    same, px2 = crop_frame(tile)
    assert px2 == 0 and same.shape == tile.shape, "an unframed image must pass through untouched"
    print("selftest ok: frame cropped, seamless tile passes, stepped tile flagged, unframed untouched")


if __name__ == "__main__":
    a = sys.argv[1:]
    if a == ["--selftest"]:
        selftest()
    elif len(a) >= 2:
        main(a[0], a[1], int(a[a.index("--size") + 1]) if "--size" in a else 1024)
    else:
        sys.exit(__doc__)
