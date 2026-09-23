#!/usr/bin/env python3
"""Keep the published package's endpoint, version and label on one declared channel.

  python3 release/release_channel.py check
  python3 release/release_channel.py set <channel> --version <semver>

`check` also audits what an installation copies: no caches, no links or paths
that escape the plugin directory. `set` refuses unavailable channels.
"""
import argparse
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / "release/channels.json").read_text())
PLUGIN = ROOT / CONFIG["plugin_dir"]
PLUGIN_JSON = PLUGIN / ".claude-plugin/plugin.json"
MCP_JSON = PLUGIN / ".mcp.json"
MARKETPLACE_JSON = ROOT / ".claude-plugin/marketplace.json"
BASE_DESCRIPTION = "Build Roblox experiences with ForgeGUI assets and the official Roblox Studio MCP."
CACHE_PARTS = {"__pycache__", ".pytest_cache", ".test-deps", "node_modules", ".DS_Store"}
LINK = re.compile(r"\]\(([^)#\s]+)(?:#[^)]*)?\)")


def load(path):
    return json.loads(path.read_text())


def entry(marketplace):
    matches = [p for p in marketplace["plugins"] if p["name"] == CONFIG["marketplace_entry"]]
    if len(matches) != 1:
        raise SystemExit(f"marketplace must list exactly one '{CONFIG['marketplace_entry']}' entry")
    return matches[0]


def package_problems():
    problems = []
    root = PLUGIN.resolve()
    for path in PLUGIN.rglob("*"):
        rel = path.relative_to(PLUGIN)
        if CACHE_PARTS.intersection(rel.parts) or path.suffix in {".pyc", ".pyo"}:
            problems.append(f"cache or build artifact in package: {rel}")
        if path.is_file() and path.suffix in {".md", ".json", ".sh", ".py", ".luau"}:
            text = path.read_text(errors="replace")
            if "/home/" in text or "/Users/" in text:
                problems.append(f"machine-specific absolute path in {rel}")
            if path.suffix == ".md":
                for href in LINK.findall(text):
                    if re.match(r"^[a-z][a-z0-9+.-]*:", href):
                        continue
                    target = (path.parent / href).resolve()
                    if not str(target).startswith(str(root)):
                        problems.append(f"{rel}: link escapes the installed package: {href}")
                    elif not target.exists():
                        problems.append(f"{rel}: broken link: {href}")
    return problems


def channel_problems():
    problems = []
    name = CONFIG["active"]
    channel = CONFIG["channels"].get(name)
    if channel is None:
        return [f"active channel '{name}' is not declared"]
    if not channel["available"]:
        problems.append(f"active channel '{name}' is unavailable: {channel.get('blocked_reason', '')}")
    plugin = load(PLUGIN_JSON)
    market = entry(load(MARKETPLACE_JSON))
    url = load(MCP_JSON)["mcpServers"][CONFIG["mcp_server"]]["url"]
    if url != channel["mcp_url"]:
        problems.append(f".mcp.json url {url} does not match channel '{name}' ({channel['mcp_url']})")
    if name == "production" and urlparse(url).hostname in CONFIG["forbidden_production_hosts"]:
        problems.append(f"production channel points at a staging host: {url}")
    if plugin["version"] != market.get("version"):
        problems.append(f"plugin.json version {plugin['version']} != marketplace version {market.get('version')}")
    if not re.match(channel["version_pattern"], plugin["version"]):
        problems.append(f"version {plugin['version']} does not match channel '{name}' pattern {channel['version_pattern']}")
    expected = channel["description_prefix"] + BASE_DESCRIPTION
    for label, desc in (("plugin.json", plugin.get("description")), ("marketplace", market.get("description"))):
        if desc != expected:
            problems.append(f"{label} description must be exactly: {expected!r} (got {desc!r})")
    return problems


def check():
    problems = channel_problems() + package_problems()
    for problem in problems:
        print(f"FAIL {problem}")
    if problems:
        return 1
    print(f"ok   channel '{CONFIG['active']}' and installed-package audit")
    return 0


def set_channel(name, version):
    channel = CONFIG["channels"].get(name)
    if channel is None:
        raise SystemExit(f"unknown channel '{name}'")
    if not channel["available"] or not channel["mcp_url"]:
        raise SystemExit(f"channel '{name}' is unavailable: {channel.get('blocked_reason', 'no endpoint recorded')}")
    if not re.match(channel["version_pattern"], version):
        raise SystemExit(f"version {version} does not match {channel['version_pattern']}")
    description = channel["description_prefix"] + BASE_DESCRIPTION
    mcp = load(MCP_JSON)
    mcp["mcpServers"][CONFIG["mcp_server"]]["url"] = channel["mcp_url"]
    plugin = load(PLUGIN_JSON)
    plugin.update(version=version, description=description)
    market = load(MARKETPLACE_JSON)
    entry(market).update(version=version, description=description)
    CONFIG["active"] = name
    for path, data in ((MCP_JSON, mcp), (PLUGIN_JSON, plugin), (MARKETPLACE_JSON, market), (ROOT / "release/channels.json", CONFIG)):
        path.write_text(json.dumps(data, indent=2) + "\n")
    return check()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("check")
    setter = sub.add_parser("set")
    setter.add_argument("channel")
    setter.add_argument("--version", required=True)
    args = parser.parse_args()
    sys.exit(check() if args.command == "check" else set_channel(args.channel, args.version))


if __name__ == "__main__":
    main()
