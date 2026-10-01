"""Emit a fresh targeted Edit probe; construct only capability-supported requests.

No manifest is accepted as probe input. The caller supplies Studio selection via
its discovered MCP tool schema, and must re-probe before each new batch.
"""
import copy
import json
from pathlib import Path
import re
import uuid

UUID4 = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}", re.I)
DECIMAL = re.compile(r"[1-9][0-9]{0,19}")


def probe_source():
    # uuid4 obtains randomness from the OS, not Python random or agent memory.
    candidate = str(uuid.uuid4())
    source = (Path(__file__).resolve().parents[1] / "luau/LocalPlaceIdentity.luau").read_text()
    return "local identity = (function()\n" + source + "\nend)()\nreturn identity.probe(game, " + json.dumps(candidate) + ")\n"


def observed_context(probe):
    if probe.get("edit_mode") is not True:
        raise ValueError("A fresh selected Edit-mode probe is required")
    local = probe.get("local_place_id")
    if not isinstance(local, str) or not UUID4.fullmatch(local):
        raise ValueError("Invalid local_place_id")
    result = {"local_place_id": local.lower()}
    for field in ("place_id", "universe_id"):
        value = probe.get(field)
        if value is None or value == "0":
            continue
        if not isinstance(value, str) or not DECIMAL.fullmatch(value):
            raise ValueError("Observed Roblox IDs must be exact positive decimal strings")
        result[field] = value
    name = probe.get("name")
    if not isinstance(name, str) or not name.strip():
        raise ValueError("Missing observed place label")
    result["name"] = name.strip()[:120]
    return result


def run_arguments(probe, live_schema, request_id, name):
    context = observed_context(probe)
    properties = live_schema.get("properties", {})
    if "local_place_id" not in properties:
        raise ValueError("Backend does not advertise local_place_id; local history unavailable. Use an explicitly disclosed supported legacy flow only.")
    result = {"request_id": request_id, "name": name, "local_place_id": context["local_place_id"]}
    for source, target in (("place_id", "intended_place_id"), ("universe_id", "intended_universe_id"), ("name", "external_project_label")):
        if source in context:
            if target not in properties:
                raise ValueError("Backend does not advertise " + target)
            result[target] = context[source]
    return result


def mirror_manifest(manifest, probe, selection_metadata=None):
    """Mirror only a fresh observation; preserve all old receipts and extensions."""
    context = observed_context(probe)
    result = copy.deepcopy(manifest)
    if result.get("local_place_id") != context["local_place_id"] and result.get("run"):
        result.setdefault("runs", []).append(result["run"])
        result["run"] = None
    result["local_place_id"] = context["local_place_id"]
    place_context = result.get("place_context") or {}
    place_context.update(copy.deepcopy(selection_metadata or {}))
    for field in ("local_place_id", "place_id", "universe_id", "name"):
        place_context.pop(field, None)
    place_context.update(context)
    result["place_context"] = place_context
    return result


if __name__ == "__main__":
    # Execute this output once in the selected Edit model; do not cache it as
    # a reusable project identity or run it in multiple independent places.
    print(probe_source(), end="")
