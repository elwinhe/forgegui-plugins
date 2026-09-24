#!/usr/bin/env python3
"""Derive height, normal, roughness and cavity maps from a tileable colour texture.

    python3 references/tools/pbr_maps.py tile.png maps/ [--strength 4] [--rough 0.8]
        [--detail 0.35] [--medium 0] [--sharpen 0] [--plates 0] [--cavity 0] [--size 1024]
    python3 references/tools/pbr_maps.py --selftest

numpy + Pillow only. Run it on a tile that already wraps (make_tileable.py, texture_prep.py):
every filter here wraps around the edges, so the maps tile exactly like the colour, and a seam
in the colour becomes a ridge in the normal map.

Roblox takes a ColorMap, NormalMap and RoughnessMap on a MaterialVariant or SurfaceAppearance,
but no height or displacement input, and terrain cannot displace at all. So the height map is
where relief is decided, and the normal, roughness and cavity maps carry it to the renderer:

  height     luminance high-passed against a wide blur (broad colour changes must not read as
             slopes), plus fine detail (--detail) and, with --medium, the band between about
             1/128 and 1/20 of the tile (sand ripples, plate edges, ledges), which the wide
             high-pass alone throws away. Without --medium, ripples read flat.
  normal     tangent space, OpenGL convention (+Y up, what Roblox expects), from the height
             gradient times --strength.
  roughness  --rough, raised in crevices and lowered on exposed tops.
  plates     (--plates R, pixels) for cracked earth, flagstones and brick: dark crack or mortar
             lines are found in the colour and each plate between them becomes a raised tile
             bevelled down into the crack over R pixels, so it reads as relief, not paint.
  cavity     (--cavity C, 0..1) the colour with the height baked in: crevices darkened (local
             and broad occlusion), crests lifted. Use it as the ColorMap. Since nothing
             displaces, this bake is what keeps relief visible where the normal map is lit flat
             (overcast, shadow, the terrain's far LOD).
  sharpen    (--sharpen S) an unsharp mask on the colour first, for sources upscaled to 1024.

Writes <stem>_height.png, <stem>_normal.png, <stem>_rough.png and, with --cavity,
<stem>_cavity.png. 1024 px is the right size: Roblox stores images at no more than 1024 on a
side, so larger costs a resample and buys nothing.
"""
from __future__ import annotations

import argparse
import os
import sys
import tempfile

import numpy as np
from PIL import Image

LUMA = np.array([0.299, 0.587, 0.114])


def blur(a: np.ndarray, radius: int) -> np.ndarray:
    """Box blur with wrap-around, three passes (close to Gaussian). Works on 2-D arrays."""
    radius = max(1, int(radius))
    for _ in range(3):
        for axis in (0, 1):
            acc = np.zeros_like(a)
            for d in range(-radius, radius + 1):
                acc += np.roll(a, d, axis=axis)
            a = acc / (2 * radius + 1)
    return a


def normalise(a: np.ndarray) -> np.ndarray:
    lo, hi = np.percentile(a, 1), np.percentile(a, 99)
    return np.clip((a - lo) / max(hi - lo, 1e-6), 0, 1)


def neighbours_all(mask: np.ndarray) -> np.ndarray:
    """True where the pixel and all eight wrapped neighbours are True (one erosion step)."""
    out = mask.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            out &= np.roll(np.roll(mask, dy, axis=0), dx, axis=1)
    return out


def plated(lum: np.ndarray, detail: np.ndarray, radius: float, crack_pct: float) -> np.ndarray:
    """Raised plates between dark crack lines, bevelled into the cracks over `radius` px."""
    size = lum.shape[0]
    local = lum - blur(lum, max(3, size // 64))
    cracks = local < np.percentile(local, crack_pct)
    # Close pinholes in the crack network (dilate, then erode) so a plate edge is a line.
    grown = ~neighbours_all(~cracks)
    cracks = neighbours_all(grown) | cracks
    solid = ~cracks
    # Wrapped chessboard distance to the nearest crack, counted by repeated erosion up to radius.
    steps = max(1, int(round(radius)))
    dist = np.zeros(lum.shape)
    current = solid
    for _ in range(steps):
        dist += current
        current = neighbours_all(current)
        if not current.any():
            break
    plate = np.clip(dist / steps, 0, 1)
    plate = 1 - (1 - plate) ** 2  # rounded bevel, flat top
    return normalise(plate * 0.78 + detail * 0.22)


def height_map(rgb: np.ndarray, detail: float, medium: float) -> tuple[np.ndarray, np.ndarray]:
    size = rgb.shape[0]
    lum = rgb @ LUMA
    wide = blur(lum, max(4, size // 40))
    fine = lum - blur(lum, 2)
    band = blur(lum, max(2, size // 128)) - blur(lum, max(8, size // 20))
    height = normalise((lum - wide) + fine * detail * 4 + band * medium * 2.5)
    return blur(height, 1), lum


def normal_map(height: np.ndarray, strength: float) -> np.ndarray:
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    n = np.stack([-dx * strength, dy * strength, np.ones_like(height)], axis=-1)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


def cavity_map(rgb: np.ndarray, height: np.ndarray, amount: float) -> np.ndarray:
    size = height.shape[0]
    local = height - blur(height, max(2, size // 96))
    broad = blur(height, max(4, size // 24)) - height
    occlusion = np.clip(-local * 3.2, 0, 1) * 0.7 + np.clip(broad * 2.2, 0, 1) * 0.3
    crest = np.clip(local * 3.2, 0, 1)
    shade = (1 - amount * occlusion) * (1 + amount * 0.22 * crest)
    return np.clip(rgb * shade[..., None], 0, 1)


def build(colour: Image.Image, args: argparse.Namespace) -> dict[str, np.ndarray]:
    """All maps for one colour image, as float arrays in 0..1."""
    img = colour.convert("RGB").resize((args.size, args.size), Image.LANCZOS)
    rgb = np.asarray(img).astype(np.float64) / 255
    if args.sharpen > 0:
        soft = np.stack([blur(rgb[..., c], 1) for c in range(3)], axis=-1)
        rgb = np.clip(rgb + (rgb - soft) * args.sharpen, 0, 1)
    height, lum = height_map(rgb, args.detail, args.medium)
    if args.plates > 0:
        height = plated(lum, height, args.plates, args.crack)
    maps = {
        "height": height,
        "normal": normal_map(height, args.strength) * 0.5 + 0.5,
        "rough": np.clip(args.rough + (0.5 - height) * 0.25, 0.05, 1),
    }
    if args.cavity > 0:
        maps["cavity"] = cavity_map(rgb, height, args.cavity)
    return maps


def write(maps: dict[str, np.ndarray], out_dir: str, stem: str) -> list[str]:
    os.makedirs(out_dir, exist_ok=True)
    paths = []
    for key, array in maps.items():
        mode = "RGB" if array.ndim == 3 else "L"
        path = os.path.join(out_dir, f"{stem}_{key}.png")
        Image.fromarray(np.round(array * 255).astype(np.uint8), mode).save(path)
        paths.append(path)
    return paths


def parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("colour", nargs="?")
    ap.add_argument("out", nargs="?")
    ap.add_argument("--strength", type=float, default=4.0, help="normal-map slope gain")
    ap.add_argument("--rough", type=float, default=0.8, help="base roughness 0..1")
    ap.add_argument("--detail", type=float, default=0.35, help="weight of fine detail in the height")
    ap.add_argument("--medium", type=float, default=0.0, help="weight of the medium relief band (ripples, ledges)")
    ap.add_argument("--sharpen", type=float, default=0.0, help="unsharp-mask amount on the colour")
    ap.add_argument("--plates", type=float, default=0.0, help="bevel radius in px for plates between cracks")
    ap.add_argument("--crack", type=float, default=14.0, help="percentile of local darkness treated as crack")
    ap.add_argument("--cavity", type=float, default=0.0, help="strength of the cavity bake 0..1")
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--selftest", action="store_true")
    return ap


def wrap_ratio(a: np.ndarray) -> float:
    """Wrap difference over ordinary neighbour difference; about 1 means it tiles."""
    a = a.astype(np.float64)
    neighbour = (np.abs(np.diff(a, axis=1)).mean() + np.abs(np.diff(a, axis=0)).mean()) / 2
    wrap = max(np.abs(a[:, 0] - a[:, -1]).mean(), np.abs(a[0] - a[-1]).mean())
    return float(wrap / max(neighbour, 1e-9))


def synthetic_tile(size: int) -> Image.Image:
    """A seamless sand-like tile: ripples along x plus periodic speckle, sand coloured."""
    rng = np.random.default_rng(7)
    y, x = np.mgrid[0:size, 0:size] / size
    ripple = np.sin(2 * np.pi * (6 * x + np.sin(2 * np.pi * y) * 0.3))
    fy, fx = np.meshgrid(np.fft.fftfreq(size), np.fft.fftfreq(size), indexing="ij")
    speck = np.real(np.fft.ifft2(np.fft.fft2(rng.standard_normal((size, size))) * (np.hypot(fx, fy) < 0.12)))
    lum = normalise(ripple * 0.6 + speck / speck.std() * 0.4)
    rgb = np.stack([0.55 + lum * 0.35, 0.45 + lum * 0.3, 0.3 + lum * 0.22], axis=-1)
    return Image.fromarray(np.round(rgb * 255).astype(np.uint8), "RGB")


def selftest() -> None:
    failures = []

    def check(ok: bool, label: str) -> None:
        print(("ok   " if ok else "FAIL ") + label)
        if not ok:
            failures.append(label)

    size = 128
    colour = synthetic_tile(size)
    maps = build(colour, parser().parse_args(["--size", str(size), "--medium", "1", "--cavity", "0.6", "--sharpen", "0.5"]))
    check(set(maps) == {"height", "normal", "rough", "cavity"}, "cavity adds a fourth map")
    for key, array in maps.items():
        check(array.shape[:2] == (size, size), f"{key} is {size} px square")
        check(float(array.min()) >= 0 and float(array.max()) <= 1, f"{key} stays in 0..1")
        check(wrap_ratio(array) < 2.0, f"{key} tiles (wrap/neighbour {wrap_ratio(array):.2f})")
    normal = maps["normal"] * 2 - 1
    check(bool((normal[..., 2] > 0).all()), "every normal points out of the surface (+Z)")
    check(abs(float(np.linalg.norm(normal, axis=-1).mean()) - 1) < 0.02, "normals are unit length")
    # OpenGL convention: where height rises toward +x the normal leans toward -x.
    ramp = np.tile(np.sin(np.linspace(0, 2 * np.pi, size, endpoint=False)), (size, 1))
    n = normal_map(ramp, 4.0)
    check(float(n[:, size // 8, 0].mean()) < 0 < float(n[:, 5 * size // 8, 0].mean()), "normal X leans away from uphill")
    rough, height = maps["rough"], maps["height"]
    check(float(rough[height < 0.2].mean()) > float(rough[height > 0.8].mean()), "crevices are rougher than tops")
    check(float(maps["cavity"].mean()) < float(np.asarray(colour).mean() / 255), "the cavity bake darkens overall")
    flat = build(colour, parser().parse_args(["--size", str(size)]))
    check(float(np.abs(maps["height"] - flat["height"]).mean()) > 0.01, "--medium changes the height")
    grid = np.full((size, size, 3), (170, 140, 100), dtype=np.uint8)
    grid[::32, :] = 40
    grid[:, ::32] = 40
    plates = build(Image.fromarray(grid), parser().parse_args(["--size", str(size), "--plates", "6"]))["height"]
    check(float(plates[16::32, 16::32].mean()) > float(plates[::32, 16::32].mean()) + 0.3,
          "--plates raises tiles above their cracks")
    with tempfile.TemporaryDirectory() as tmp:
        paths = write(maps, tmp, "sand")
        check(len(paths) == 4 and all(os.path.getsize(p) > 0 for p in paths), "four PNGs are written")
        with Image.open(os.path.join(tmp, "sand_normal.png")) as im:
            check(im.mode == "RGB", "the normal map is RGB")
        with Image.open(os.path.join(tmp, "sand_rough.png")) as im:
            check(im.mode == "L", "the roughness map is greyscale")
    if failures:
        sys.exit(f"selftest FAILED: {len(failures)} check(s)")
    print("selftest ok")


def main() -> None:
    args = parser().parse_args()
    if args.selftest:
        selftest()
        return
    if not args.colour or not args.out:
        parser().error("colour and out are required (or --selftest)")
    with Image.open(args.colour) as source:
        maps = build(source, args)
    stem = os.path.splitext(os.path.basename(args.colour))[0]
    write(maps, args.out, stem)
    print(f"{stem}: {'/'.join(maps)} {args.size}px, strength {args.strength}, "
          f"height wrap/neighbour {wrap_ratio(maps['height']):.2f}")


if __name__ == "__main__":
    main()
