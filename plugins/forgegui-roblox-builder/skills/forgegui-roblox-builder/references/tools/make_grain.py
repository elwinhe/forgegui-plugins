#!/usr/bin/env python3
"""Write a tileable dark/light grain pair for the DetailGrain overlay.

    python3 references/tools/make_grain.py out_dir [--size 512] [--seed 1] [--scale 1.0]
        [--contrast 1.0] [--pits 0.004]
    python3 references/tools/make_grain.py --selftest

numpy + Pillow only. Writes <out_dir>/grain_dark.png and <out_dir>/grain_light.png: RGBA,
neutral colour (black and white), the pattern entirely in alpha. `luau/DetailGrain.luau` tiles
both over every visible face of a building at about 3 studs per tile, dark at Transparency 0.15
and light at 0.3, so the building keeps its own colours and gains crevices and crests at a scale
its one stretched 1024 px texture cannot carry.

Why generate it instead of prompting for it: the overlay must hold no colour, no shapes and no
low-frequency blotches (a blotch repeats every 3 studs and reads as a polka dot), and it must
wrap exactly. Band-limited noise built in the frequency domain has all three by construction:
it is periodic in the tile, so it tiles with no repair step.

  --scale     grain size multiplier (1 = features about 1/90 to 1/8 of the tile)
  --contrast  alpha gain; 1 puts mean alpha near 0.2 per layer
  --pits      fraction of pixels that seed small dark pits (dust, pores)
"""
from __future__ import annotations

import argparse
import os
import sys
import tempfile

import numpy as np
from PIL import Image

# (lowest, highest) spatial frequency in cycles per tile, and weight, per octave. Nothing below
# 8 cycles: anything coarser shows as a repeating blotch at a 3-stud tile.
OCTAVES = ((8, 16, 0.45), (16, 40, 0.35), (40, 90, 0.2))


def band_noise(size: int, rng: np.random.Generator, scale: float) -> np.ndarray:
    """Sum of band-passed white noise, periodic in the tile, unit variance."""
    fy, fx = np.meshgrid(np.fft.fftfreq(size) * size, np.fft.fftfreq(size) * size, indexing="ij")
    radius = np.hypot(fx, fy)
    total = np.zeros((size, size))
    for low, high, weight in OCTAVES:
        low, high = low / scale, min(high / scale, size / 2)
        mask = np.clip(np.minimum(radius - low, high - radius) / max(low * 0.25, 1), 0, 1)
        band = np.real(np.fft.ifft2(np.fft.fft2(rng.standard_normal((size, size))) * mask))
        total += band / max(band.std(), 1e-9) * weight
    return total / max(total.std(), 1e-9)


def pits(size: int, rng: np.random.Generator, fraction: float) -> np.ndarray:
    """Sparse soft dark pits, 1-3 px, wrapped at the edges."""
    field = np.zeros((size, size))
    count = int(size * size * fraction)
    ys, xs = rng.integers(0, size, count), rng.integers(0, size, count)
    field[ys, xs] = rng.uniform(0.6, 1.0, count)
    spread = field.copy()
    for dy, dx, w in ((0, 1, 0.5), (0, -1, 0.5), (1, 0, 0.5), (-1, 0, 0.5), (1, 1, 0.25), (-1, -1, 0.25)):
        spread = np.maximum(spread, np.roll(np.roll(field, dy, axis=0), dx, axis=1) * w)
    return spread


def build(size: int, seed: int, scale: float, contrast: float, pit_fraction: float) -> tuple[np.ndarray, np.ndarray]:
    """(dark alpha, light alpha) as floats in 0..1."""
    rng = np.random.default_rng(seed)
    grain = band_noise(size, rng, scale)
    gain = 0.32 * contrast
    dark = np.clip(-grain * gain, 0, 1)
    light = np.clip(grain * gain, 0, 1)
    if pit_fraction > 0:
        pit = pits(size, rng, pit_fraction)
        dark = np.maximum(dark, pit * min(1.0, 0.8 * contrast))
        light = light * (pit == 0)  # a pit is a hole: no crest light inside it
    return dark, light


def rgba(alpha: np.ndarray, value: int) -> Image.Image:
    size = alpha.shape[0]
    out = np.zeros((size, size, 4), dtype=np.uint8)
    out[..., :3] = value
    out[..., 3] = np.round(alpha * 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def write(out_dir: str, dark: np.ndarray, light: np.ndarray) -> tuple[str, str]:
    os.makedirs(out_dir, exist_ok=True)
    dark_path = os.path.join(out_dir, "grain_dark.png")
    light_path = os.path.join(out_dir, "grain_light.png")
    rgba(dark, 0).save(dark_path)
    rgba(light, 255).save(light_path)
    return dark_path, light_path


def wrap_ratio(a: np.ndarray) -> float:
    neighbour = (np.abs(np.diff(a, axis=1)).mean() + np.abs(np.diff(a, axis=0)).mean()) / 2
    wrap = max(np.abs(a[:, 0] - a[:, -1]).mean(), np.abs(a[0] - a[-1]).mean())
    return float(wrap / max(neighbour, 1e-9))


def box_mean(a: np.ndarray, cells: int) -> np.ndarray:
    size = a.shape[0] // cells
    return a[: size * cells, : size * cells].reshape(cells, size, cells, size).mean(axis=(1, 3))


def selftest() -> None:
    failures = []

    def check(ok: bool, label: str) -> None:
        print(("ok   " if ok else "FAIL ") + label)
        if not ok:
            failures.append(label)

    size = 256
    dark, light = build(size, 1, 1.0, 1.0, 0.004)
    for name, layer in (("dark", dark), ("light", light)):
        check(layer.shape == (size, size), f"{name} is {size} px square")
        check(0.08 < float(layer.mean()) < 0.35, f"{name} mean alpha {layer.mean():.3f} is a light touch")
        check(wrap_ratio(layer) < 1.6, f"{name} tiles (wrap/neighbour {wrap_ratio(layer):.2f})")
        blotch = box_mean(layer, 4).std()
        check(blotch < 0.02, f"{name} has no blotch at quarter-tile scale (std {blotch:.4f})")
    both = (dark > 0.05) & (light > 0.05)
    check(float(both.mean()) < 0.01, "dark and light rarely cover the same pixel")
    again, _ = build(size, 1, 1.0, 1.0, 0.004)
    check(bool(np.array_equal(dark, again)), "the same seed gives the same grain")
    other, _ = build(size, 2, 1.0, 1.0, 0.004)
    check(not np.array_equal(dark, other), "another seed gives another grain")
    soft, _ = build(size, 1, 1.0, 0.5, 0.0)
    check(float(soft.mean()) < float(dark.mean()), "lower contrast means less alpha")
    with tempfile.TemporaryDirectory() as tmp:
        dark_path, light_path = write(tmp, dark, light)
        for path, value in ((dark_path, 0), (light_path, 255)):
            with Image.open(path) as im:
                pixels = np.asarray(im)
                check(im.mode == "RGBA", f"{os.path.basename(path)} is RGBA")
                check(bool((pixels[..., :3] == value).all()), f"{os.path.basename(path)} carries no colour")
    if failures:
        sys.exit(f"selftest FAILED: {len(failures)} check(s)")
    print("selftest ok")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out", nargs="?")
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--scale", type=float, default=1.0)
    ap.add_argument("--contrast", type=float, default=1.0)
    ap.add_argument("--pits", type=float, default=0.004)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        selftest()
        return
    if not args.out:
        ap.error("out is required (or --selftest)")
    dark, light = build(args.size, args.seed, args.scale, args.contrast, args.pits)
    dark_path, light_path = write(args.out, dark, light)
    print(f"{dark_path} mean alpha {dark.mean():.3f}, {light_path} mean alpha {light.mean():.3f}, "
          f"{args.size}px, wrap/neighbour {wrap_ratio(dark):.2f}")


if __name__ == "__main__":
    main()
