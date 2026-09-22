#!/usr/bin/env python3
"""Explicit Open Cloud fallback. Requires --receipt and --user-id OR --group-id.
Repeat identical arguments with --resume after interruption. Never delete a receipt
or change its path to retry an uncertain submission. Credentials: ROBLOX_API_KEY only.
"""
from __future__ import annotations

import argparse
import contextlib
import fcntl
import hashlib
import json
import math
import os
import pathlib
import re
import ssl
import sys
import tempfile
import time
import urllib.request

API = "https://apis.roblox.com/assets/v1"
INTROSPECT = "https://apis.roblox.com/api-keys/v1/introspect"
MAX_BYTES = 20_000_000
FORMATS = {
    ".png": (("Image",), "image/png"),
    ".glb": (("Model",), "model/gltf-binary"),
    ".mp3": (("Audio",), "audio/mpeg"),
    ".rbxm": (("Animation", "Model"), "model/x-rbxm"),
}
DESCRIPTION = "Uploaded via ForgeGUI Open Cloud fallback."


class UploadError(Exception):
    """Only fixed, credential-free messages may cross the CLI boundary."""


def require(condition, message):
    if not condition:
        raise UploadError(message)


def numeric(value):
    return type(value) in (str, int) and re.fullmatch(r"[1-9][0-9]*", str(value)) is not None


def operation(value):
    require(isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_-]{1,200}", value),
            "Invalid operation identifier; submission may be ambiguous.")
    return value


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise UploadError("API redirect refused.")


def call(url, key, data=None, content_type=None, timeout=30):
    require(url in (INTROSPECT, API + "/assets") or
            re.fullmatch(re.escape(API) + r"/operations/[A-Za-z0-9_-]{1,200}", url),
            "API destination refused.")
    headers = {"Content-Type": content_type} if content_type else {}
    if url != INTROSPECT:
        headers["x-api-key"] = key
    try:
        try:
            import certifi
            context = ssl.create_default_context(cafile=certifi.where())
        except ImportError:
            context = ssl.create_default_context()
        opener = urllib.request.build_opener(NoRedirect(), urllib.request.HTTPSHandler(context=context))
        with opener.open(urllib.request.Request(url, data=data, headers=headers), timeout=timeout) as response:
            result = json.loads(response.read(1_000_001))
        require(isinstance(result, dict), "Invalid API response.")
        return result
    except Exception:
        # Never include exception text, response bodies, headers or introspection results.
        raise UploadError("API request failed; retain receipt and resume known operations only.") from None


def authorize(key, destination):
    result = call(INTROSPECT, key, json.dumps({"apiKey": key}).encode(), "application/json")
    require(result.get("enabled") is True and result.get("expired") is False,
            "Credential is not demonstrably enabled and unexpired.")
    kind, owner = next(iter(destination.items()))
    if kind == "userId":
        require(numeric(result.get("authorizedUserId")) and str(result["authorizedUserId"]) == owner,
                "Credential user does not match destination.")
    scopes = result.get("scopes")
    require(isinstance(scopes, list), "Credential scopes unproven.")
    granted = set()
    for scope in scopes:
        if not isinstance(scope, dict) or scope.get("name") != "asset":
            continue
        ids = scope.get("userIds" if kind == "userId" else "groupIds")
        ops = scope.get("operations")
        if not isinstance(ids, list) or not isinstance(ops, list):
            continue
        # Wildcard cannot prove membership/role in a particular group.
        if owner in [str(v) for v in ids if numeric(v)] or (kind == "userId" and "*" in ids):
            granted.update(v for v in ops if isinstance(v, str))
    require({"read", "write"} <= granted, "Destination asset read/write authority unproven.")


def atomic_write(path, value):
    fd, temporary = tempfile.mkstemp(prefix=".upload-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as out:
            json.dump(value, out, indent=2, sort_keys=True)
            out.write("\n")
            out.flush()
            os.fsync(out.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


@contextlib.contextmanager
def locked(path):
    # Keep this inode: unlinking a lock allows a second writer to bypass it.
    fd = os.open(str(path) + ".lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise UploadError("Receipt is locked by another writer.") from None
        yield
    finally:
        os.close(fd)


def read_receipt(path, expected):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "Duplicate receipt field.")
            result[key] = value
        return result
    try:
        with path.open() as source:
            value = json.load(source, object_pairs_hook=unique)
        require(isinstance(value, dict) and set(value) == {"version", "inputs", "entries"}
                and type(value["version"]) is int and value["version"] == 1
                and value["inputs"] == expected, "Receipt input, destination or metadata mismatch.")
        entries = value["entries"]
        require(isinstance(entries, list) and len(entries) == len(expected["files"]), "Invalid receipt entries.")
        for entry in entries:
            require(isinstance(entry, dict), "Invalid receipt entry.")
            state = entry.get("state")
            fields = {"ready": {"state"}, "submitting": {"state"},
                      "polling": {"state", "operation"},
                      "succeeded": {"state", "operation", "assetId"}}
            require(state in fields and set(entry) == fields[state], "Invalid receipt state.")
            if "operation" in entry:
                operation(entry["operation"])
            if state == "succeeded":
                require(numeric(entry["assetId"]), "Invalid receipt asset ID.")
        return value
    except (ValueError, TypeError, KeyError):
        raise UploadError("Invalid receipt; refusing submission.") from None


def multipart(metadata, content, mime, suffix):
    require(suffix in FORMATS, "Unsupported multipart extension.")
    boundary = "----forgegui" + os.urandom(16).hex()
    body = (f'--{boundary}\r\nContent-Disposition: form-data; name="request"\r\n\r\n'
            + json.dumps(metadata) + f'\r\n--{boundary}\r\nContent-Disposition: form-data; '
            f'name="fileContent"; filename="asset{suffix}"\r\n' + f'Content-Type: {mime}\r\n\r\n').encode()
    return body + content + f"\r\n--{boundary}--\r\n".encode(), "multipart/form-data; boundary=" + boundary


def execute(args):
    destination = {"userId" if args.user_id else "groupId": args.user_id or args.group_id}
    require(numeric(next(iter(destination.values()))), "Destination must be a positive numeric ID.")
    require(math.isfinite(args.timeout) and args.timeout > 0, "Timeout must be positive and finite.")
    require(not args.name or len(args.files) == 1, "--name requires one file.")
    files, contents = [], []
    for filename in args.files:
        path = pathlib.Path(filename).resolve(strict=True)
        require(path.is_file() and 0 < path.stat().st_size <= MAX_BYTES, "File missing, empty or over 20 MB.")
        allowed, mime = FORMATS.get(path.suffix.lower(), ((), None))
        kind = args.asset_type or (allowed[0] if allowed else None)
        require(kind in allowed, "Unsupported file format/type combination.")
        name = args.name if args.name is not None else path.stem
        require(0 < len(name) <= 50, "Display name must contain 1–50 characters.")
        content = path.read_bytes()
        require(0 < len(content) <= MAX_BYTES, "File empty or over 20 MB.")
        files.append({"path": str(path), "sha256": hashlib.sha256(content).hexdigest(),
                      "size": len(content), "type": kind, "name": name, "mime": mime})
        contents.append(content)
    require(len({f["path"] for f in files}) == len(files), "Duplicate input file.")
    inputs = {"destination": destination, "description": DESCRIPTION, "files": files}
    path = pathlib.Path(args.receipt).absolute()
    require(not path.is_symlink(), "Receipt symlink refused.")
    path = path.resolve()
    require(str(path) not in {f["path"] for f in files} and
            str(path) + ".lock" not in {f["path"] for f in files}, "Receipt overlaps input.")
    if args.dry_run:
        print("Dry run: local inputs valid; authority and publication not verified.")
        return []
    key = os.environ.get("ROBLOX_API_KEY", "").strip()
    require(bool(key), "ROBLOX_API_KEY environment variable required.")
    # Refuse accidental credential use as user metadata, too.
    require(key not in json.dumps(inputs) and key not in str(path), "Credential found in metadata; refused.")
    with locked(path):
        if args.resume:
            require(path.exists(), "Resume requires an existing receipt.")
            receipt = read_receipt(path, inputs)
        else:
            require(not path.exists(), "Receipt exists; use --resume with identical inputs.")
            receipt = {"version": 1, "inputs": inputs, "entries": [{"state": "ready"} for _ in files]}
        require(all(e["state"] != "submitting" for e in receipt["entries"]),
                "Ambiguous submission: reconcile externally; do not resubmit or replace receipt.")
        authorize(key, destination)
        if not args.resume:
            atomic_write(path, receipt)
        for index, (info, content) in enumerate(zip(files, contents)):
            entry = receipt["entries"][index]
            if entry["state"] == "ready":
                metadata = {"assetType": info["type"], "displayName": info["name"],
                            "description": DESCRIPTION, "creationContext": {"creator": destination}}
                body, content_type = multipart(metadata, content, info["mime"],
                                               pathlib.Path(info["path"]).suffix.lower())
                entry["state"] = "submitting"
                atomic_write(path, receipt)  # Durable intent BEFORE the only POST attempt.
                result = call(API + "/assets", key, body, content_type)
                op = result.get("operationId")
                remote_path = result.get("path")
                if remote_path is not None:
                    require(isinstance(remote_path, str) and remote_path.startswith("operations/"),
                            "Malformed operation path; submission ambiguous.")
                    path_op = operation(remote_path[len("operations/"):])
                    require(op is None or op == path_op, "Conflicting operation IDs; submission ambiguous.")
                    op = path_op
                op = operation(op)
                require(key not in op, "Invalid operation identifier.")
                entry.update(state="polling", operation=op)
                atomic_write(path, receipt)  # No polling until operation is durable.
            if entry["state"] == "polling":
                deadline = time.monotonic() + args.timeout
                while time.monotonic() < deadline:
                    result = call(API + "/operations/" + entry["operation"], key,
                                  timeout=min(30, max(.001, deadline - time.monotonic())))
                    require(not result.get("error"), "Operation failed; retain receipt for reconciliation.")
                    if result.get("done") is True:
                        response = result.get("response")
                        asset = response.get("assetId") if isinstance(response, dict) else None
                        require(numeric(asset) and key not in str(asset), "Invalid completion; retain operation.")
                        entry.update(state="succeeded", assetId=str(asset))
                        atomic_write(path, receipt)  # Persist each success before the next file.
                        break
                    time.sleep(min(1, max(0, deadline - time.monotonic())))
                require(entry["state"] == "succeeded", "Polling timed out; resume using this receipt.")
            print("assetId=" + entry["assetId"] + " assetType=" + info["type"] + " moderation=unverified")
        return [e["assetId"] for e in receipt["entries"]]


class SafeParser(argparse.ArgumentParser):
    def error(self, message):
        # argparse otherwise echoes arbitrary argument values, potentially secrets.
        self.exit(2, "Invalid arguments; use --help for required destination and receipt flags.\n")


def main(argv=None):
    parser = SafeParser(description=__doc__)
    parser.add_argument("files", nargs="+")
    parser.add_argument("--type", dest="asset_type", choices=("Image", "Model", "Audio", "Animation"))
    parser.add_argument("--name")
    owner = parser.add_mutually_exclusive_group(required=True)
    owner.add_argument("--user-id")
    owner.add_argument("--group-id")
    parser.add_argument("--receipt", required=True)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--timeout", type=float, default=180)
    try:
        execute(parser.parse_args(argv))
        return 0
    except UploadError as error:
        print(str(error), file=sys.stderr)
        return 1
    except (Exception, KeyboardInterrupt):
        print("Upload interrupted or local I/O failed; retain receipt and inspect before resuming.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
