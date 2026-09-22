#!/usr/bin/env python3
"""Turn the reference video the user gave you into evenly spaced frames plus contact sheets.

usage: reference_frames.py <video-or-url> <outdir> [--frames 30] [--width 1280] [--sheet 3x4]
       reference_frames.py --selftest

Point it at the reference the user provided: a local file or a link they gave. It does not
search for footage and downloads nothing the user did not hand over; before pointing it at a
link, confirm the user is entitled to that footage. A URL is fetched with yt-dlp; frames are extracted with ffmpeg. Frames are written as frame_001.png ... and tiled
into sheet_00.png ... (rows x cols per --sheet). Keep the frames: the fidelity pass compares
Studio captures against these same stills. Each invocation creates a fresh capture directory
under outdir and writes manifest.json; earlier captures are never removed.
"""
import json
from datetime import datetime, timezone
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

INSTALL = {
    "ffprobe": "ffprobe not found (ships with ffmpeg). Install: brew install ffmpeg  (macOS)  |  apt install ffmpeg  (Debian/Ubuntu)",
    "ffmpeg": "ffmpeg not found. Install: brew install ffmpeg  (macOS)  |  apt install ffmpeg  (Debian/Ubuntu)",
    "yt-dlp": "yt-dlp not found (needed for URLs). Install: brew install yt-dlp  |  pipx install yt-dlp",
}


def need(tool):
    if not shutil.which(tool):
        sys.exit(INSTALL[tool])


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"{cmd[0]} failed ({r.returncode}):\n{r.stderr.strip()[-2000:]}")
    return r.stdout


def duration(video):
    need("ffprobe")
    out = run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
               "-of", "default=nw=1:nk=1", str(video)])
    try:
        return float(out.strip())
    except ValueError:
        sys.exit(f"could not read duration of {video}: {out!r}")


def fetch(url, workdir):
    need("yt-dlp")
    target = workdir / "reference.%(ext)s"
    run(["yt-dlp", "--no-playlist", "-f", "bv*[height<=720]+ba/b[height<=720]/b",
         "--merge-output-format", "mp4", "-o", str(target), url])
    files = sorted(workdir.glob("reference.*"))
    if not files:
        sys.exit("yt-dlp reported success but wrote no file")
    return files[0]


def extract(video, outdir, frames, width):
    need("ffmpeg")
    outdir.mkdir(parents=True, exist_ok=True)
    fps = frames / max(duration(video), 0.001)
    # fixed-rate sampling, no scene detection; add "select=gt(scene,..)" if a clip has long static stretches
    run(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-i", str(video),
         "-vf", f"fps={fps},scale={width}:-2", "-frames:v", str(frames),
         str(outdir / "frame_%03d.png")])
    return sorted(outdir.glob("frame_*.png"))


def sheets(paths, outdir, rows, cols):
    need("ffmpeg")
    per, out = rows * cols, []
    for n, i in enumerate(range(0, len(paths), per)):
        chunk = paths[i:i + per]
        listing = outdir / f"_sheet_{n:02d}.txt"
        listing.write_text("".join(f"file '{p.name}'\n" for p in chunk))
        dest = outdir / f"sheet_{n:02d}.png"
        run(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
             "-f", "concat", "-safe", "0", "-i", str(listing),
             "-vf", f"scale=640:-2,tile={cols}x{rows}", "-frames:v", "1", str(dest)])
        listing.unlink()
        out.append(dest)
    return out


def capture(src, outdir, frames=30, width=1280, sheet="3x4"):
    rows, cols = (int(v) for v in sheet.lower().split("x"))
    started = datetime.now(timezone.utc).isoformat()
    parent = Path(outdir)
    parent.mkdir(parents=True, exist_ok=True)
    outdir = Path(tempfile.mkdtemp(prefix="capture-", dir=parent))
    with tempfile.TemporaryDirectory() as tmp:
        video = fetch(src, Path(tmp)) if "://" in src else Path(src)
        if not video.is_file():
            sys.exit(f"no such file: {video}")
        got = extract(video, outdir, frames, width)
    if not got:
        sys.exit("ffmpeg produced no frames")
    contact_sheets = sheets(got, outdir, rows, cols)
    manifest = {
        "version": 1,
        "source": str(src) if "://" in str(src) else str(Path(src).resolve()),
        "parameters": {"frames": frames, "width": width, "sheet": sheet},
        "started_at": started,
        "completed_at": datetime.now(timezone.utc).isoformat(),
        "frames": [p.name for p in got],
        "sheets": [p.name for p in contact_sheets],
    }
    (outdir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return got, contact_sheets


def selftest():
    need("ffmpeg")
    with tempfile.TemporaryDirectory() as tmp:
        clip = Path(tmp) / "clip.mp4"
        run(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
             "-f", "lavfi", "-i", "testsrc=size=320x180:rate=10:duration=3",
             "-pix_fmt", "yuv420p", str(clip)])
        got, sh = capture(str(clip), Path(tmp) / "Champ's references", frames=12, width=320, sheet="2x3")
        assert len(got) == 12, [p.name for p in got]
        assert len(sh) == 2, [p.name for p in sh]
        assert got[0].name == "frame_001.png" and all(p.stat().st_size > 0 for p in got + sh)
        original = {p: p.read_bytes() for p in got + sh + [got[0].parent / "manifest.json"]}
        second, second_sheets = capture(str(clip), Path(tmp) / "Champ's references", frames=3, width=320, sheet="2x3")
        assert len(second) == 3 and len(second_sheets) == 1
        assert second[0].parent != got[0].parent
        assert all(p.read_bytes() == data for p, data in original.items())
        manifest = json.loads((second[0].parent / "manifest.json").read_text())
        assert manifest["source"] == str(clip.resolve())
        assert manifest["parameters"] == {"frames": 3, "width": 320, "sheet": "2x3"}
        assert manifest["frames"] == [p.name for p in second]
        assert manifest["sheets"] == [p.name for p in second_sheets]
        assert datetime.fromisoformat(manifest["completed_at"]) >= datetime.fromisoformat(manifest["started_at"])
    print("selftest OK")


def main(argv):
    if argv == ["--selftest"]:
        return selftest()
    opts, pos = {"--frames": 30, "--width": 1280, "--sheet": "3x4"}, []
    it = iter(argv)
    for a in it:
        if a in opts:
            v = next(it, None)
            if v is None:
                sys.exit(f"{a} needs a value")
            if a == "--sheet":
                opts[a] = v
            else:
                try:
                    opts[a] = int(v)
                except ValueError:
                    sys.exit(f"{a} takes a whole number, got {v!r}")
        elif a.startswith("-"):
            sys.exit(f"unknown option {a}\n{__doc__}")
        else:
            pos.append(a)
    if len(pos) != 2:
        sys.exit(__doc__)
    try:
        _rows, _cols = (int(v) for v in str(opts["--sheet"]).lower().split("x", 1))
        if _rows < 1 or _cols < 1:
            raise ValueError
    except ValueError:
        sys.exit("error: --sheet wants ROWSxCOLS with both at least 1, for example 3x4")
    if opts["--frames"] < 1:
        sys.exit(f"error: --frames must be at least 1, got {opts['--frames']}")
    if opts["--width"] < 16:
        sys.exit(f"error: --width must be at least 16, got {opts['--width']}")
    got, sh = capture(pos[0], pos[1], opts["--frames"], opts["--width"], opts["--sheet"])
    print(f"capture: {got[0].parent}\nmanifest: {got[0].parent / 'manifest.json'}")
    print(f"{len(got)} frames: {got[0]} .. {got[-1]}")
    for s in sh:
        print(f"sheet: {s}")


if __name__ == "__main__":
    main(sys.argv[1:])
