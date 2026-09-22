#!/usr/bin/env python3
"""Cut a 2:1 equirectangular panorama into the six faces a Roblox Sky needs.

usage: sky_faces.py <panorama.png> <out_dir> [--size 1024 | --band 64]
       sky_faces.py --selftest
At most one option: --size is the face edge in pixels, --band the number of columns
the wrap seam's step is ramped out over (0 disables the correction).
Writes SkyboxFt/Bk/Lf/Rt/Up/Dn.png. Faces come from one continuous image, so
edges meet by construction; the panorama's own left/right wrap seam is the only
place a generated image can mismatch, and it lands behind the camera (Bk).
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# Direction for face pixel (u, v), both in [-1, 1], u right, v down.
# Roblox: +Y up, camera faces -Z at spawn, +X to the right. Measured in Studio on
# 19 Sep 2026: Roblox shows SkyboxLf on the +X side and SkyboxRt on -X.
FACES = {
    "SkyboxFt": lambda u, v: (u, -v, -np.ones_like(u)),
    "SkyboxBk": lambda u, v: (-u, -v, np.ones_like(u)),
    "SkyboxLf": lambda u, v: (np.ones_like(u), -v, u),
    "SkyboxRt": lambda u, v: (-np.ones_like(u), -v, -u),
    "SkyboxUp": lambda u, v: (u, np.ones_like(u), -v),   # forward at bottom edge
    "SkyboxDn": lambda u, v: (u, -np.ones_like(u), v),    # forward at top edge
}
# Quarter turns (counter-clockwise) applied after sampling. Studio shows the Up
# face turned 90° clockwise and the Dn face 90° counter-clockwise, so undo both.
ROTATE = {"SkyboxFt": 0, "SkyboxBk": 0, "SkyboxRt": 0, "SkyboxLf": 0, "SkyboxUp": 1, "SkyboxDn": -1}


def sample(pano, x, y, z):
    h, w, _ = pano.shape
    lon = np.arctan2(x, -z)                                  # 0 = forward (-Z), + = right
    lat = np.arcsin(y / np.sqrt(x * x + y * y + z * z))     # + = up
    px = (lon / (2 * np.pi) + 0.5) * w - 0.5
    py = (0.5 - lat / np.pi) * h - 0.5
    x0 = np.floor(px).astype(int); fx = (px - x0)[..., None]
    y0 = np.clip(np.floor(py).astype(int), 0, h - 1); fy = (py - np.floor(py))[..., None]
    y1 = np.clip(y0 + 1, 0, h - 1)
    x0w, x1w = x0 % w, (x0 + 1) % w                         # wrap horizontally
    top = pano[y0, x0w] * (1 - fx) + pano[y0, x1w] * fx
    bot = pano[y1, x0w] * (1 - fx) + pano[y1, x1w] * fx
    return top * (1 - fy) + bot * fy



def close_wrap_seam(pano, band):
    """Remove the step between the last and first column.

    A generated panorama is rarely seamless at its own wrap, and that step is the one
    discontinuity cutting faces from a single image cannot remove. The two edges look at
    different parts of the sky, so averaging them ghosts detail across the joint and dirties
    a panorama that already wrapped. Instead take the step itself -- the per-row, per-channel
    difference across the wrap -- and ramp half of it out of each side over `band` columns.
    Detail is untouched; only a smooth offset moves, and a panorama with no step is unchanged.
    """
    if band <= 0:
        return pano
    band = min(band, pano.shape[1] // 2)
    out = pano.copy()
    half_step = (pano[:, 0] - pano[:, -1]) / 2.0
    for i in range(band):
        w = 1.0 - i / band
        out[:, i] -= half_step * w
        out[:, -1 - i] += half_step * w
    return out


def wrap_gap(pano):
    """Mean per-channel difference between the first and last column."""
    return float(np.abs(pano[:, 0] - pano[:, -1]).mean())

def faces(pano, size, rotate=True):
    c = (np.arange(size) + 0.5) / size * 2 - 1
    u, v = np.meshgrid(c, c)
    return {n: np.rot90(sample(pano, *f(u, v)), ROTATE[n] if rotate else 0) for n, f in FACES.items()}


def parse_args(argv):
    """Return (src, out, kwargs-for-main) for a valid invocation, or exit with usage.

    A fourth argument is only ever --size or --band. A typo, an unknown option or a stray
    path has to be rejected: silently falling back to the defaults would run a long cut with
    settings the caller did not ask for and no sign that the option was dropped. Defaults
    stay on main, so an omitted option is absent from the returned kwargs rather than
    restated here.
    """
    if len(argv) == 2:
        return argv[0], argv[1], {}
    if len(argv) == 4 and argv[2] == "--size":
        return argv[0], argv[1], {"size": int(argv[3])}
    if len(argv) == 4 and argv[2] == "--band":
        return argv[0], argv[1], {"band": int(argv[3])}
    sys.exit(__doc__)


def main(src, out, size=1024, band=64):
    img = Image.open(src).convert("RGB")
    w, h = img.size
    if abs(w / h - 2) > 0.02:
        sys.exit(f"error: {src} is {w}x{h}; an equirectangular panorama must be 2:1")
    Path(out).mkdir(parents=True, exist_ok=True)
    pano = np.asarray(img, dtype=np.float32)
    before = wrap_gap(pano)
    pano = close_wrap_seam(pano, band)
    if band > 0:
        # Not "before -> after": the correction sets both edge columns to the same value, so
        # re-measuring the gap can only ever print 0. Report the step that was taken out.
        print(f"wrap seam: {before:.1f} levels of step ramped out over {band} columns")
    for name, arr in faces(pano, size).items():
        Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(Path(out) / f"{name}.png")
        print(Path(out) / f"{name}.png")


def selftest():
    # Panorama coloured by direction: R = forward/back, G = up/down, B = right/left.
    h, w = 256, 512
    lon = ((np.arange(w) + 0.5) / w - 0.5) * 2 * np.pi
    lat = (0.5 - (np.arange(h) + 0.5) / h) * np.pi
    lon, lat = np.meshgrid(lon, lat)
    d = np.stack([np.cos(lat) * np.sin(lon), np.sin(lat), -np.cos(lat) * np.cos(lon)], -1)
    pano = (d * 127.5 + 127.5).astype(np.float32)
    f = faces(pano, 64, rotate=False)  # geometry before Studio's per-face turns
    mid = lambda n: f[n][32, 32]
    assert mid("SkyboxFt")[2] < 20, "Ft centre should look along -Z"
    assert mid("SkyboxBk")[2] > 235, "Bk centre should look along +Z"
    assert mid("SkyboxLf")[0] > 235 and mid("SkyboxRt")[0] < 20, "Lf/Rt should be +X/-X"
    assert mid("SkyboxUp")[1] > 235 and mid("SkyboxDn")[1] < 20, "Up/Dn should be +Y/-Y"
    # Shared edges match: Ft's right column == Lf's left column (+X side).
    assert np.abs(f["SkyboxFt"][:, -1] - f["SkyboxLf"][:, 0]).max() < 12, "Ft/Lf seam"
    assert np.abs(f["SkyboxFt"][0] - f["SkyboxUp"][-1]).max() < 12, "Ft/Up seam"
    assert np.abs(f["SkyboxFt"][-1] - f["SkyboxDn"][0]).max() < 12, "Ft/Dn seam"
    assert np.abs(f["SkyboxLf"][:, -1] - f["SkyboxBk"][:, 0]).max() < 12, "Lf/Bk seam"
    # ROTATE regression pin. This locks the table against an accidental sign or index change;
    # that the turns are the ones Studio needs rests on the in-Studio captures, not on this test.
    r = faces(pano, 64, rotate=True)
    for n in ("SkyboxFt", "SkyboxBk", "SkyboxLf", "SkyboxRt"):
        assert np.array_equal(r[n], f[n]), f"{n} must not be rotated"
    # Up is pre-turned one quarter counter-clockwise, so forward (-Z, blue low) moves from the
    # bottom edge to the right edge and +X (red high) to the top edge.
    # edge midpoints sit at 45deg, so compare against the neutral 127.5 with a margin rather than 0/255
    assert r["SkyboxUp"][32, -1][2] < 60 and r["SkyboxUp"][32, 0][2] > 195, "Up rotation"
    assert r["SkyboxUp"][0, 32][0] > 195 and r["SkyboxUp"][-1, 32][0] < 60, "Up rotation direction"
    # Dn is pre-turned one quarter clockwise: forward moves from the top edge to the right edge,
    # and -X ends up on top.
    assert r["SkyboxDn"][32, -1][2] < 60 and r["SkyboxDn"][32, 0][2] > 195, "Dn rotation"
    assert r["SkyboxDn"][0, 32][0] < 60 and r["SkyboxDn"][-1, 32][0] > 195, "Dn rotation direction"
    # close_wrap_seam: leaves an already-wrapping panorama alone, and removes a real step
    # without touching detail.
    # cos is symmetric about the wrap, so its first and last column already agree.
    x = (np.arange(512) + 0.5) / 512 * 2 * np.pi
    seamless = np.repeat((np.cos(x) * 60 + 128)[None, :, None], 3, 2).astype(np.float32)
    seamless = np.repeat(seamless, 64, 0)
    assert np.abs(close_wrap_seam(seamless, 64) - seamless).max() < 1e-3, "seamless input must not change"
    # The bound that matters on real panoramas: nothing moves by more than half the step that
    # was actually measured, so a nearly-seamless sky can only be nudged by a nearly-zero amount.
    rng = np.random.default_rng(0)
    noisy = rng.uniform(0, 255, (32, 256, 3)).astype(np.float32)
    step = np.abs(noisy[:, 0] - noisy[:, -1]).max()
    assert np.abs(close_wrap_seam(noisy, 64) - noisy).max() <= step / 2 + 1e-3, "change must be bounded by half the step"
    stepped = seamless.copy()
    stepped[:, :256] += 20.0  # a 20-level step at the wrap (and one inside, which must survive)
    fixed = close_wrap_seam(stepped, 64)
    assert wrap_gap(fixed) < 1e-3, "wrap step must close"
    assert abs(float(np.abs(fixed[:, 0] - stepped[:, 0]).max()) - 10.0) < 1e-3, "each side takes half the step"
    interior = np.abs(fixed[:, 255] - stepped[:, 255]).max()
    assert interior < 1e-3, "detail outside the band must be untouched"
    # Argument parsing. The fourth argument is only ever --size or --band; anything else has
    # to exit with usage rather than reach main with the defaults.
    assert parse_args(["p.png", "out"]) == ("p.png", "out", {})
    assert parse_args(["p.png", "out", "--size", "512"]) == ("p.png", "out", {"size": 512})
    assert parse_args(["p.png", "out", "--band", "0"]) == ("p.png", "out", {"band": 0})
    for bad in ([], ["p.png"], ["p.png", "out", "--sizes", "512"], ["p.png", "out", "-size", "512"],
                ["p.png", "out", "512", "--size"], ["p.png", "out", "--size", "512", "--band", "0"]):
        try:
            parse_args(bad)
        except SystemExit as e:
            assert e.code == __doc__, f"{bad} must exit with the usage text"
        else:
            raise AssertionError(f"{bad} must be rejected, not run with defaults")
    print("selftest ok: six face directions, four shared edges, ROTATE table pinned, wrap seam ramp, argument parsing")


if __name__ == "__main__":
    a = sys.argv[1:]
    if a == ["--selftest"]:
        selftest()
    else:
        src, out, opts = parse_args(a)
        main(src, out, **opts)
