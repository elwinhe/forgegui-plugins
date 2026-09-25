#!/usr/bin/env python3
"""Build/check the offline staging OpenAI preview; never installs or submits it."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
NAME = "forgegui-roblox-builder"
SOURCE = Path("plugins") / NAME / "skills" / NAME
DEFAULT_OUTPUT = ROOT / "dist/openai" / NAME
SCHEMA = "https://agent-plugins.org/schemas/1.0.0/"


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def safe_path(root, relative):
    rel = PurePosixPath(relative)
    if rel.is_absolute() or ".." in rel.parts or "\\" in relative:
        raise ValueError(f"unsafe package path: {relative}")
    # The root is trusted; its ancestors may include platform aliases like /var.
    # Reject symlinks only in the package-relative components we traverse.
    path = root
    for part in rel.parts:
        path = path / part
        if path.is_symlink():
            raise ValueError(f"symlink is not allowed: {relative}")
    if not path.resolve().is_relative_to(root.resolve()):
        raise ValueError(f"path escapes root: {relative}")
    return path


def channel_config(root, channel, mode):
    config = json.loads((root / "release/channels.json").read_text())
    name = channel or config["active"]
    channel = config["channels"].get(name)
    if not channel or channel.get("available") is not True or not channel.get("mcp_url"):
        raise ValueError(f"channel {name!r} unavailable; production service is not ready")
    url = urlsplit(channel["mcp_url"])
    if (url.scheme != "https" or not url.hostname or url.username or url.password
            or url.query or url.fragment or url.port not in (None, 443)):
        raise ValueError("MCP URL must be HTTPS without credentials, query or fragment")
    if name == "production" and url.hostname in config["forbidden_production_hosts"]:
        raise ValueError("production cannot target staging")
    # Availability of an endpoint alone is not evidence of OpenAI OAuth readiness.
    if mode == "submission" or name != "staging-beta":
        raise ValueError("production/submission blocked: OpenAI OAuth readiness is unverified")
    if not channel["description_prefix"].startswith("Staging beta:"):
        raise ValueError("staging preview must be labeled Staging beta")
    return name, channel


def expected_files(root=ROOT, channel=None, mode="preview"):
    name, selected = channel_config(root, channel, mode)
    source = root / SOURCE
    metadata = json.loads((root / "plugins" / NAME / ".claude-plugin/plugin.json").read_text())
    version = metadata["version"]
    if not re.fullmatch(selected["version_pattern"], version):
        raise ValueError("shared version does not match selected channel")
    description = selected["description_prefix"] + "ForgeGUI remote assets and optional Roblox Studio workflow. OAuth readiness unverified."
    interface = dict(displayName="ForgeGUI (Staging beta)", shortDescription=description,
                     longDescription=description, developerName="ForgeGUI", category="Productivity",
                     capabilities=["Read", "Write"],
                     defaultPrompt=["Find reusable ForgeGUI assets before planning paid generation."])
    identity = dict(name=NAME, version=version, description=description, author={"name": "ForgeGUI"})
    result = {
        "plugin.json": encoded({"$schema": SCHEMA + "plugin.schema.json", **identity,
                                "extensions": {"com.openai": {"interface": interface}}}),
        ".codex-plugin/plugin.json": encoded({**identity, "skills": "./skills/",
                                              "mcpServers": "./.mcp.json", "interface": interface}),
        "mcp.json": encoded({"$schema": SCHEMA + "mcp.schema.json", "mcpServers": {
            "forgegui": {"type": "streamable-http", "url": selected["mcp_url"]}}}),
        ".mcp.json": encoded({"mcpServers": {
            "forgegui": {"type": "http", "url": selected["mcp_url"]}}}),
        "README.md": (root / "release/openai/README.md").read_bytes(),
        f"skills/{NAME}/SKILL.md": (root / "release/openai/SKILL.md").read_bytes(),
    }
    inventory = json.loads((root / "release/openai/sources.json").read_text())
    if not inventory or len(inventory) != len(set(inventory)) or "SKILL.md" not in inventory:
        raise ValueError("invalid shared source inventory")
    hashes = {}
    for relative in inventory:
        parts = PurePosixPath(relative).parts
        if (any(p.startswith(".") or p in {"__pycache__", "node_modules", "hooks"} for p in parts)
                or PurePosixPath(relative).suffix not in {".md", ".py", ".sh", ".luau", ".json"}):
            raise ValueError(f"forbidden source: {relative}")
        data = safe_path(source, relative).read_bytes()
        if b"${CLAUDE" in data or b"${user_config" in data:
            raise ValueError(f"Claude interpolation in source: {relative}")
        dest = "WORKFLOW.md" if relative == "SKILL.md" else relative
        result[f"skills/{NAME}/{dest}"] = data
        hashes[relative] = hashlib.sha256(data).hexdigest()
    result["provenance.json"] = encoded({"generator": "release/openai_package.py", "channel": name,
        "oauth_readiness": "unverified", "shared_source": SOURCE.as_posix(), "sha256": hashes})
    # Installed markdown links must remain usable without the repository.
    for relative, data in result.items():
        if not relative.endswith(".md"):
            continue
        for href in re.findall(r"\]\(([^)#\s]+)(?:#[^)]*)?\)", data.decode()):
            if re.match(r"^[a-z][a-z0-9+.-]*:", href):
                continue
            target = Path(relative).parent / href
            if ".." in target.parts or target.as_posix() not in result:
                raise ValueError(f"broken or escaping package link: {relative}: {href}")
    return result


def output_path(output, root=ROOT):
    output = Path(output).absolute()
    if any(p.is_symlink() for p in (output, *output.parents)):
        raise ValueError("output cannot use symlinks")
    output = output.resolve()
    if output.name != NAME:
        raise ValueError(f"output directory must be named {NAME}")
    # Never overwrite repository sources or global plugin installs.
    if output.is_relative_to(root.resolve()) and not output.is_relative_to(root.resolve() / "dist/openai"):
        raise ValueError("in-repository output must be under dist/openai")
    return output


def check(output, expected):
    actual = set()
    if not output.is_dir():
        raise ValueError("package missing; run build first")
    for path in output.rglob("*"):
        relative = path.relative_to(output).as_posix()
        safe_path(output, relative)
        if path.is_file():
            actual.add(relative)
        elif not any(p.startswith(relative + "/") for p in expected):
            raise ValueError(f"unexpected package directory: {relative}")
    if actual != set(expected):
        raise ValueError(f"package inventory drift: missing={sorted(set(expected)-actual)}, extra={sorted(actual-set(expected))}")
    for relative, data in expected.items():
        if safe_path(output, relative).read_bytes() != data:
            raise ValueError(f"package content drift: {relative}")


def build(output, expected):
    if output.exists():
        # Refuse stale/foreign content rather than recursively deleting caller files.
        check(output, expected)
        return
    output.mkdir(parents=True)
    for relative, data in sorted(expected.items()):
        path = safe_path(output, relative)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    check(output, expected)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["build", "check"])
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--channel", default=None)
    parser.add_argument("--mode", choices=["preview", "submission"], default="preview")
    args = parser.parse_args()
    try:
        expected = expected_files(channel=args.channel, mode=args.mode)
        output = output_path(args.output)
        (build if args.command == "build" else check)(output, expected)
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(f"FAIL {error}", file=sys.stderr)
        return 1
    print(f"ok   OpenAI staging preview {args.command}: {output} ({len(expected)} files); OAuth unverified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
