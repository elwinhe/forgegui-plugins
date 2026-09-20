#!/usr/bin/env python3
"""Per-mesh quality report for GLB files (no deps beyond numpy).
Reports, per mesh: triangles, vertices, boundary edges (edges used by exactly one triangle: > 0 means the surface is
open / has holes), non-manifold edges (used by > 2 triangles), duplicate triangles, degenerate triangles (zero area or
repeated vertex index). Vertices are merged by exact position before the edge analysis so seams split only for UV /
normal reasons are not reported as boundary.

usage: glb_quality.py [--md] file.glb ...      (--md prints a Markdown table)
       glb_quality.py --selftest                (closed tetrahedron -> 0 boundary edges; open one -> 3)
"""
import json, struct, sys
import numpy as np

COMP = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def _read_glb(path):
    b = open(path, "rb").read()
    n = struct.unpack_from("<I", b, 12)[0]
    g = json.loads(b[20:20 + n])
    off = 20 + n
    bins = []
    while off < len(b):
        ln, typ = struct.unpack_from("<II", b, off)
        chunk = b[off + 8:off + 8 + ln]
        if typ == 0x004E4942:
            bins.append(chunk)
        off += 8 + ln
    return g, (bins[0] if bins else b"")


def _accessor(g, blob, idx):
    a = g["accessors"][idx]
    bv = g["bufferViews"][a["bufferView"]]
    dt = np.dtype("<" + COMP[a["componentType"]])
    nc = NCOMP[a["type"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", dt.itemsize * nc)
    out = np.empty((a["count"], nc), dtype=dt)
    for i in range(nc):
        out[:, i] = np.frombuffer(blob, dtype=dt, count=a["count"], offset=start + i * dt.itemsize) if stride == dt.itemsize * nc \
            else np.ndarray((a["count"],), dt, blob, start + i * dt.itemsize, (stride,))
    return out


def analyse(vertices, faces):
    """vertices: (n,3) float, faces: (m,3) int. Returns a dict of counts."""
    faces = np.asarray(faces, dtype=np.int64)
    # merge coincident vertices so UV/normal seams do not count as boundary
    _, remap = np.unique(np.round(np.asarray(vertices, dtype=np.float64), 6), axis=0, return_inverse=True)
    f = remap.reshape(-1)[faces]
    degenerate_idx = (f[:, 0] == f[:, 1]) | (f[:, 1] == f[:, 2]) | (f[:, 0] == f[:, 2])
    v = np.asarray(vertices, dtype=np.float64)[faces]
    area2 = np.linalg.norm(np.cross(v[:, 1] - v[:, 0], v[:, 2] - v[:, 0]), axis=1)
    degenerate = int(np.count_nonzero(degenerate_idx | (area2 < 1e-12)))
    keyed = np.sort(f, axis=1)
    _, counts = np.unique(keyed, axis=0, return_counts=True)
    duplicates = int(np.sum(counts - 1))
    good = f[~degenerate_idx]
    edges = np.concatenate([good[:, [0, 1]], good[:, [1, 2]], good[:, [2, 0]]])
    edges = np.sort(edges, axis=1)
    _, ecount = np.unique(edges, axis=0, return_counts=True)
    return {
        "tris": int(len(faces)),
        "verts": int(len(vertices)),
        "unique_verts": int(remap.max() + 1) if len(remap) else 0,
        "boundary_edges": int(np.count_nonzero(ecount == 1)),
        "nonmanifold_edges": int(np.count_nonzero(ecount > 2)),
        "duplicate_tris": duplicates,
        "degenerate_tris": degenerate,
    }


def report(path):
    g, blob = _read_glb(path)
    rows = []
    for m in g.get("meshes", []):
        for pi, p in enumerate(m["primitives"]):
            if p.get("mode", 4) != 4:
                continue
            pos = _accessor(g, blob, p["attributes"]["POSITION"]).astype(np.float64)
            if "indices" in p:
                idx = _accessor(g, blob, p["indices"]).reshape(-1).astype(np.int64)
            else:
                idx = np.arange(len(pos))
            faces = idx[: len(idx) - len(idx) % 3].reshape(-1, 3)
            r = analyse(pos, faces)
            r["mesh"] = f"{m.get('name', '?')}[{pi}]"
            rows.append(r)
    return rows


COLS = ["mesh", "tris", "verts", "unique_verts", "boundary_edges", "nonmanifold_edges", "duplicate_tris", "degenerate_tris"]


def selftest():
    closed_v = np.array([[0, 0, 0], [1, 0, 0], [0, 1, 0], [0, 0, 1]], float)
    closed_f = np.array([[0, 1, 2], [0, 3, 1], [0, 2, 3], [1, 3, 2]])
    open_f = closed_f[:3]  # drop one face: three edges become boundary
    c = analyse(closed_v, closed_f)
    o = analyse(closed_v, open_f)
    assert c["boundary_edges"] == 0 and c["nonmanifold_edges"] == 0 and c["duplicate_tris"] == 0 and c["degenerate_tris"] == 0, c
    assert o["boundary_edges"] == 3 and o["tris"] == 3, o
    d = analyse(closed_v, np.vstack([closed_f, [[0, 1, 2], [0, 0, 1]]]))
    assert d["duplicate_tris"] == 1 and d["degenerate_tris"] == 1, d
    # split seam (same position, different index) must not count as boundary
    seam_v = np.vstack([closed_v, closed_v[[1, 2]]])
    seam_f = np.array([[0, 1, 2], [0, 3, 4], [0, 2, 3], [1, 3, 5]])  # 4,5 duplicate positions of 1,2
    s = analyse(seam_v, seam_f)
    assert s["boundary_edges"] == 0, s
    # a wheel-shaped mesh: a hole through the middle, but a closed surface.
    # A ring of 12 segments, each a square tube of 4 sides -> nothing is ever missing a neighbour.
    seg, side = 12, 4
    ring_v, ring_f = [], []
    for i in range(seg):
        a = 2 * np.pi * i / seg
        cx, cz = np.cos(a), np.sin(a)
        for j in range(side):
            b = 2 * np.pi * j / side
            r = 1.0 + 0.3 * np.cos(b)
            ring_v.append([r * cx, 0.3 * np.sin(b), r * cz])
    for i in range(seg):
        for j in range(side):
            a0 = i * side + j
            a1 = i * side + (j + 1) % side
            b0 = ((i + 1) % seg) * side + j
            b1 = ((i + 1) % seg) * side + (j + 1) % side
            ring_f += [[a0, b0, b1], [a0, b1, a1]]
    r = analyse(np.array(ring_v, float), np.array(ring_f))
    assert r["boundary_edges"] == 0, r  # the hub hole is not an open surface
    # a tube open at both ends: legitimately open, and the count says so
    tube_f = [f for f in ring_f if 0 not in f]
    tb = analyse(np.array(ring_v, float), np.array(tube_f))
    assert tb["boundary_edges"] > 0, tb
    print("selftest PASS: closed tetra boundary=0, open tetra boundary=3, dup=1 degen=1, seam merge ok, "
          "ring-with-hub-hole boundary=0, open tube boundary>0")


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args or args == ["--selftest"]:
        selftest()
        sys.exit(0)
    md = "--md" in args
    files = [a for a in args if a != "--md"]
    if md:
        print("| file | " + " | ".join(COLS) + " |")
        print("|" + "---|" * (len(COLS) + 1))
    for fpath in files:
        try:
            for r in report(fpath):
                if md:
                    print("| " + fpath + " | " + " | ".join(str(r[c]) for c in COLS) + " |")
                else:
                    print(fpath, " ".join(f"{c}={r[c]}" for c in COLS))
        except Exception as e:  # keep going across the folder, but say why
            print(f"| {fpath} | ERROR {e} |" if md else f"{fpath} ERROR {e}")
