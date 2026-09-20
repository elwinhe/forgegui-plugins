#!/usr/bin/env python3
"""Upload a file to Roblox via Open Cloud and return its asset id.

    python3 tools/oc_upload.py art/models/vesper.glb --type Model --name "AR-17 VESPER"
    python3 tools/oc_upload.py art/pieces/*.png --type Image --json ids.json

The Studio MCP has no model uploader -- `upload_image` is images-only and
`insert_asset` needs an id that already exists -- so a generated GLB reaches
Studio through Open Cloud or not at all. This is that route, verified end to end
on 2026-09-20:

    POST /assets/v1/assets   multipart: request JSON + fileContent  -> operationId
    GET  /assets/v1/operations/{operationId}                        -> assetId

Needs ROBLOX_API_KEY in the environment or in .env beside this repo, from a
Creator Dashboard key with the Assets system and `asset:read` + `asset:write`.

The key is read from the environment and never logged, never echoed and never
written into the ledger. Only the returned numeric asset id is.
"""
from __future__ import annotations

import argparse
import json
import mimetypes
import os
import pathlib
import sys
import time
import ssl
import urllib.error
import urllib.request

# python.org builds ship without a CA bundle wired into ssl, so urllib fails
# CERTIFICATE_VERIFY_FAILED on a host curl reaches fine. Use certifi's bundle
# when it is present and the system default otherwise. Verification stays ON:
# this call carries an API key, so an unverified channel is not an option.
try:
    import certifi

    SSL_CONTEXT: ssl.SSLContext | None = ssl.create_default_context(cafile=certifi.where())
except ImportError:
    SSL_CONTEXT = ssl.create_default_context()

API = "https://apis.roblox.com/assets/v1"
# Open Cloud's own limits; a bigger file is rejected server-side.
MAX_BYTES = 20 * 1024 * 1024
TYPE_BY_SUFFIX = {
    ".png": ("Image", "image/png"),
    ".jpg": ("Image", "image/jpeg"),
    ".jpeg": ("Image", "image/jpeg"),
    ".glb": ("Model", "model/gltf-binary"),
    ".fbx": ("Model", "model/fbx"),
    ".mp3": ("Audio", "audio/mpeg"),
    ".ogg": ("Audio", "audio/ogg"),
}


def load_key(repo: pathlib.Path) -> str:
    key = os.environ.get("ROBLOX_API_KEY", "").strip()
    if key:
        return key
    env = repo / ".env"
    if env.is_file():
        for line in env.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("ROBLOX_API_KEY="):
                return line.split("=", 1)[1].strip()
    raise SystemExit("no ROBLOX_API_KEY in environment or .env")


def multipart(fields: dict[str, str], path: pathlib.Path, content_type: str) -> tuple[bytes, str]:
    boundary = "----ironfront" + os.urandom(12).hex()
    out = bytearray()
    for name, value in fields.items():
        out += f"--{boundary}\r\n".encode()
        out += f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode()
        out += value.encode() + b"\r\n"
    out += f"--{boundary}\r\n".encode()
    out += f'Content-Disposition: form-data; name="fileContent"; filename="{path.name}"\r\n'.encode()
    out += f"Content-Type: {content_type}\r\n\r\n".encode()
    out += path.read_bytes() + b"\r\n"
    out += f"--{boundary}--\r\n".encode()
    return bytes(out), boundary


def call(url: str, key: str, data: bytes | None = None, content_type: str | None = None) -> dict:
    request = urllib.request.Request(url, data=data)
    request.add_header("x-api-key", key)
    if content_type:
        request.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(request, timeout=180, context=SSL_CONTEXT) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", "replace")[:400]
        # 401/403 mean the key or its scopes, not the file. Say which.
        hint = ""
        if error.code == 401:
            hint = "  (key invalid or expired)"
        elif error.code == 403:
            hint = "  (key lacks asset:write -- add the scope in the Creator Dashboard)"
        raise SystemExit(f"HTTP {error.code}{hint}\n{body}")


def upload(path: pathlib.Path, key: str, asset_type: str, mime: str, name: str, user_id: str, timeout: float) -> str:
    size = path.stat().st_size
    if size > MAX_BYTES:
        raise SystemExit(f"{path.name}: {size} bytes exceeds Open Cloud's {MAX_BYTES} limit")
    request_json = json.dumps(
        {
            "assetType": asset_type,
            "displayName": name,
            "description": "Generated for IRONFRONT via ForgeGUI.",
            "creationContext": {"creator": {"userId": user_id}},
        }
    )
    body, boundary = multipart({"request": request_json}, path, mime)
    started = call(f"{API}/assets", key, body, f"multipart/form-data; boundary={boundary}")
    operation = started.get("operationId") or started.get("path", "").split("/")[-1]
    if not operation:
        raise SystemExit(f"{path.name}: no operationId in {started}")

    deadline = time.time() + timeout
    delay = 1.0
    while time.time() < deadline:
        result = call(f"{API}/operations/{operation}", key)
        if result.get("done"):
            if result.get("error"):
                raise SystemExit(f"{path.name}: {json.dumps(result['error'])}")
            asset_id = (result.get("response") or {}).get("assetId")
            if not asset_id:
                raise SystemExit(f"{path.name}: done but no assetId: {json.dumps(result)[:300]}")
            return str(asset_id)
        time.sleep(delay)
        delay = min(delay * 1.5, 8.0)  # capped backoff, not a tight poll
    raise SystemExit(f"{path.name}: operation {operation} still running after {timeout}s -- retain this id, do not re-upload")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("files", nargs="+")
    parser.add_argument("--type", dest="asset_type", help="Model | Image | Audio (inferred from the suffix otherwise)")
    parser.add_argument("--name", help="display name; defaults to the file stem")
    parser.add_argument("--user-id", default="97147563")
    parser.add_argument("--timeout", type=float, default=180.0)
    parser.add_argument("--json", help="write a {file: assetId} map here")
    args = parser.parse_args()

    repo = pathlib.Path(__file__).resolve().parent.parent
    key = load_key(repo)

    ids: dict[str, str] = {}
    for name in args.files:
        path = pathlib.Path(name)
        suffix = path.suffix.lower()
        inferred, mime = TYPE_BY_SUFFIX.get(suffix, (None, None))
        asset_type = args.asset_type or inferred
        if not asset_type:
            print(f"skip {path.name}: unknown type for {suffix}", file=sys.stderr)
            continue
        mime = mime or mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        display = args.name if (args.name and len(args.files) == 1) else path.stem
        asset_id = upload(path, key, asset_type, mime, display, args.user_id, args.timeout)
        ids[str(path)] = asset_id
        print(f"{path.name:<34} {asset_type:<6} rbxassetid://{asset_id}")

    if args.json:
        pathlib.Path(args.json).write_text(json.dumps(ids, indent=2) + "\n", encoding="utf-8")
        print(f"\nwrote {args.json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
