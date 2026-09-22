#!/usr/bin/env python3
"""Dominant palette of an image or a folder of frames, and one-way nearest-color distance.

usage: palette.py <image-or-dir> [--k 6]                 -> k hex colours with rough proportions
       palette.py <image-or-dir> --vs <ref-image-or-dir>  -> also prints one-way nearest-color distance
       palette.py --selftest

k-means in CIE Lab (CIE76 ΔE). Proportions are the share of sampled pixels per cluster.
One-way nearest-color distance = mean over build palette centres of the distance to
the nearest reference colour. It ignores color proportions and missing reference colors;
it cannot establish palette adherence. No match/pass/fail thresholds. numpy + Pillow only.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

EXTS = {".png", ".jpg", ".jpeg", ".webp", ".bmp"}
THUMB = 160          # per-image sample size; enough for a palette, keeps k-means fast
ITERS = 30           # plain k-means, 30 iters converges on thumbnails


def _lab(rgb):
    rgb = rgb / 255.0
    rgb = np.where(rgb > 0.04045, ((rgb + 0.055) / 1.055) ** 2.4, rgb / 12.92)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = rgb @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def _rgb(lab):
    L, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    fy = (L + 16) / 116
    f = np.stack([a / 500 + fy, fy, fy - b / 200], -1)
    xyz = np.where(f ** 3 > 0.008856, f ** 3, (f - 16 / 116) / 7.787) * np.array([0.95047, 1.0, 1.08883])
    m = np.array([[3.2406, -1.5372, -0.4986], [-0.9689, 1.8758, 0.0415], [0.0557, -0.2040, 1.0570]])
    c = xyz @ m.T
    c = np.where(c > 0.0031308, 1.055 * np.clip(c, 0, None) ** (1 / 2.4) - 0.055, 12.92 * c)
    return np.clip(c * 255, 0, 255)


def images(path):
    p = Path(path)
    if p.is_dir():
        found = sorted(f for f in p.iterdir() if f.is_file() and f.suffix.lower() in EXTS and not f.name.startswith("sheet_"))
        if not found:
            sys.exit(f"no images in {p}")
        return found
    if not p.is_file():
        sys.exit(f"no such file or directory: {p}")
    return [p]


def pixels(path):
    """Opaque pixels of every image under path, as one (n, 3) float array."""
    chunks = []
    for f in images(path):
        img = Image.open(f).convert("RGBA")
        img.thumbnail((THUMB, THUMB))
        a = np.asarray(img, dtype=np.float32)
        chunks.append(a[a[..., 3] > 128][:, :3])
    px = np.concatenate(chunks)
    if len(px) == 0:
        sys.exit(f"no opaque pixels in {path}")
    return px


def palette(path, k=6, seed=0):
    """Returns (centres in Lab, proportion per centre), sorted by proportion descending."""
    lab = _lab(pixels(path))
    k = min(k, len(lab))
    rng = np.random.default_rng(seed)
    c = lab[rng.choice(len(lab), k, replace=False)]
    for _ in range(ITERS):
        lbl = ((lab[:, None] - c[None]) ** 2).sum(-1).argmin(1)
        c = np.stack([lab[lbl == i].mean(0) if (lbl == i).any() else c[i] for i in range(k)])
    share = np.bincount(lbl, minlength=k) / len(lab)
    active = np.flatnonzero(share > 0)
    order = active[np.argsort(-share[active])]
    return c[order], share[order]


def delta_e(pal, ref):
    return float(np.sqrt(((pal[:, None] - ref[None]) ** 2).sum(-1)).min(1).mean())


def hexes(lab):
    return ["#%02x%02x%02x" % tuple(int(round(v)) for v in c) for c in _rgb(lab)]


def selftest():
    import tempfile
    from PIL import ImageDraw

    def swatch(name, left, right, d):
        im = Image.new("RGB", (60, 60), left)
        ImageDraw.Draw(im).rectangle([30, 0, 60, 60], fill=right)
        im.save(Path(d) / name)

    with tempfile.TemporaryDirectory() as d:
        swatch("a.png", (255, 0, 0), (0, 0, 255), d)
        swatch("b.png", (250, 5, 5), (5, 5, 250), d)
        sub = Path(d) / "g"
        sub.mkdir()
        swatch("g/1.png", (0, 255, 0), (255, 255, 0), d)
        swatch("g/2.png", (0, 255, 0), (255, 255, 0), d)
        pa, sa = palette(Path(d) / "a.png", k=2)
        pb, _ = palette(Path(d) / "b.png", k=2)
        pg, sg = palette(sub, k=2)
        Image.new("RGB", (60, 60), "red").save(sub / "sheet_00.png")
        Image.new("RGB", (60, 60), "red").save(sub / "sheet_01.JPG")
        (sub / "not-an-image.png").mkdir()
        assert [p.name for p in images(sub)] == ["1.png", "2.png"]
        filtered, filtered_share = palette(sub, k=2)
        assert np.array_equal(filtered, pg) and np.array_equal(filtered_share, sg)
        for ext in EXTS:
            fixture = Path(d) / f"extension-{ext[1:]}"
            fixture.mkdir()
            Image.new("RGB", (10, 10), "blue").save(fixture / f"frame{ext}")
            assert len(images(fixture)) == 1
        assert set(hexes(pa)) == {"#ff0000", "#0000ff"}, hexes(pa)
        assert abs(sa[0] - 0.5) < 0.05 and abs(sg[0] - 0.5) < 0.05, (sa, sg)
        assert delta_e(pa, pb) < delta_e(pa, pg), (delta_e(pa, pb), delta_e(pa, pg))
        assert delta_e(pa, pa) < 1e-6
        Image.new("RGB", (100, 100), "red").save(Path(d) / "red.png")
        reference = Image.new("RGB", (100, 100), "blue")
        ImageDraw.Draw(reference).rectangle([0, 0, 9, 99], fill="red")
        reference.save(Path(d) / "mostly-blue.png")
        build, build_share = palette(Path(d) / "red.png")
        ref, ref_share = palette(Path(d) / "mostly-blue.png")
        assert len(build) == len(build_share) == 1
        assert len(ref) == len(ref_share) == 2
        assert np.all(ref_share > 0) and np.isclose(ref_share.sum(), 1)
        assert abs(build_share[0] - 1) < 1e-6
        try:
            main([str(Path(d) / "red.png"), str(Path(d) / "mostly-blue.png")])
        except SystemExit as exc:
            assert "expected one image or directory" in str(exc)
        else:
            raise AssertionError("second positional source accepted")
        assert hexes(ref)[0] == "#0000ff" and abs(ref_share[0] - 0.9) < 1e-6
        assert delta_e(build, ref) < 1e-6
        import contextlib
        import io
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            main([str(Path(d) / "red.png"), "--vs", str(Path(d) / "mostly-blue.png")])
        text = output.getvalue()
        assert "Build palette:" in text and "Reference palette:" in text
        assert "90.0%" in text and "100.0%" in text
        assert "one-way nearest-color distance" in text
        assert "ignores color proportions and missing reference colors" in text
    print("selftest OK")


def main(argv):
    if argv == ["--selftest"]:
        return selftest()
    k, ref, src = 6, None, None
    it = iter(argv)
    for x in it:
        if x == "--k":
            v = next(it, "")
            try:
                k = int(v)
            except ValueError:
                sys.exit(f"--k takes a whole number, got {v!r}")
        elif x == "--vs":
            ref = next(it, None)
        elif x.startswith("-"):
            sys.exit(f"unknown option {x}\n{__doc__}")
        else:
            if src is not None:
                sys.exit("expected one image or directory; use --vs for a reference")
            src = x
    if not src or k < 1 or (ref is None and "--vs" in argv):
        sys.exit(__doc__)
    pal, share = palette(src, k)
    print(f"Build palette: {src}")
    for h, s in zip(hexes(pal), share):
        print(f"{h}  {s:5.1%}")
    if ref:
        rp, ref_share = palette(ref, k)
        print(f"Reference palette: {ref}")
        for h, s in zip(hexes(rp), ref_share):
            print(f"{h}  {s:5.1%}")
        print(f"one-way nearest-color distance (CIE76 ΔE): {delta_e(pal, rp):.2f}")
        print("Diagnostic only: ignores color proportions and missing reference colors; cannot establish palette adherence.")


if __name__ == "__main__":
    main(sys.argv[1:])
