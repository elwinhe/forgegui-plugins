import copy
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import unittest
from jsonschema import Draft7Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "plugins/forgegui-roblox-builder/skills/forgegui-roblox-builder"
spec = importlib.util.spec_from_file_location("local_place_identity", SKILL / "references/tools/local_place_identity.py")
helper = importlib.util.module_from_spec(spec)
# Importing a shipped helper must not contaminate the release package.
previous_bytecode = sys.dont_write_bytecode
sys.dont_write_bytecode = True
try:
    spec.loader.exec_module(helper)
finally:
    sys.dont_write_bytecode = previous_bytecode
PIN = json.loads((ROOT / "tests/backend-place-context-contract.json").read_text())
SCHEMA = next(t["input_schema"] for t in PIN["tools"] if t["name"] == "run_create")
LOCAL = "12345678-1234-4234-8234-123456789abc"

class LocalPlaceIdentityTests(unittest.TestCase):
    def probe(self, **kwargs):
        return {"local_place_id": LOCAL, "edit_mode": True, "name": "Local place", **kwargs}

    def test_emitted_probe_uses_fresh_os_uuid_and_shipped_source(self):
        sources = [helper.probe_source() for _ in range(2)]
        candidates = [re.search(r'identity.probe\(game, "([^"]+)"\)', s).group(1) for s in sources]
        self.assertNotEqual(*candidates)
        for value in candidates:
            self.assertTrue(helper.UUID4.fullmatch(value))
        for source in sources:
            self.assertIn((SKILL / "references/luau/LocalPlaceIdentity.luau").read_text(), source)

    def test_generated_requests_validate_against_backend_pin(self):
        validator = Draft7Validator(SCHEMA, format_checker=FormatChecker())
        for probe in [self.probe(), self.probe(local_place_id=LOCAL.upper()), self.probe(place_id="0", universe_id="0"),
                      self.probe(place_id="18446744073709551615", universe_id="9007199254740993")]:
            args = helper.run_arguments(probe, SCHEMA, "request-a", "Build")
            validator.validate(args)
            self.assertEqual(args["local_place_id"], LOCAL)
            if probe.get("place_id") == "18446744073709551615":
                self.assertEqual(args["intended_place_id"], probe["place_id"])
            else:
                self.assertNotIn("intended_place_id", args)
                self.assertNotIn("intended_universe_id", args)

    def test_old_server_is_explicitly_unsupported(self):
        old = copy.deepcopy(SCHEMA)
        del old["properties"]["local_place_id"]
        with self.assertRaisesRegex(ValueError, "does not advertise local_place_id"):
            helper.run_arguments(self.probe(), old, "r", "Build")
        for bad in ["bad", None, 0, "00000000-0000-0000-0000-000000000000"]:
            with self.assertRaises(ValueError):
                helper.run_arguments(self.probe(local_place_id=bad), SCHEMA, "r", "Build")
        with self.assertRaises(ValueError):
            helper.run_arguments(self.probe(edit_mode=False), SCHEMA, "r", "Build")
        for bad in [0, 123, "01", "1e5", "-1"]:
            with self.assertRaises(ValueError):
                helper.run_arguments(self.probe(place_id=bad), SCHEMA, "r", "Build")

    def test_stale_manifest_is_only_a_mirror_and_old_receipts_survive(self):
        original = {"version": 2, "local_place_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                    "run": {"run_id": "old"}, "assets": [{"job_id": "old-job"}], "extension": {"x": 1}}
        result = helper.mirror_manifest(original, self.probe())
        self.assertEqual(result["local_place_id"], LOCAL)
        self.assertEqual(result["runs"], [original["run"]])
        self.assertIsNone(result["run"])
        self.assertEqual(result["assets"], original["assets"])
        self.assertEqual(result["extension"], original["extension"])
        self.assertEqual(original["run"], {"run_id": "old"})
        self.assertNotIn(original["local_place_id"], helper.probe_source())

    def test_manifest_merges_selection_and_preserves_nested_extensions(self):
        original = {"local_place_id": LOCAL, "run": {"run_id": "active"},
                    "runs": [{"run_id": "archived"}], "place_context": {
                        "studio_id": "old-studio", "checked_at": "old-time",
                        "extension": {"enabled": True}, "place_id": "123",
                        "universe_id": "456", "name": "Old place"}}
        selection = {"studio_id": "new-studio", "checked_at": "new-time",
                     "caller_extension": {"value": 1}, "local_place_id": "stale",
                     "place_id": "999", "universe_id": "888", "name": "Stale"}
        before = copy.deepcopy(original)
        selection_before = copy.deepcopy(selection)
        result = helper.mirror_manifest(original, self.probe(place_id="789"), selection)
        self.assertEqual(result["place_context"], {
            "studio_id": "new-studio", "checked_at": "new-time",
            "extension": {"enabled": True}, "caller_extension": {"value": 1},
            "local_place_id": LOCAL, "place_id": "789", "name": "Local place"})
        self.assertEqual(result["run"], original["run"])
        self.assertEqual(result["runs"], original["runs"])
        result["place_context"]["extension"]["enabled"] = False
        result["place_context"]["caller_extension"]["value"] = 2
        self.assertEqual(original, before)
        self.assertEqual(selection, selection_before)

    def test_manifest_removes_stale_ids_and_keeps_additive_ledger(self):
        old_run = {"run_id": "old"}
        original = {"local_place_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                    "run": old_run, "runs": [{"run_id": "earlier"}],
                    "assets": [{"job_id": "old-job"}], "place_context": {
                        "place_id": "123", "universe_id": "456", "extension": 1}}
        for probe in (self.probe(), self.probe(place_id="0", universe_id="0")):
            result = helper.mirror_manifest(original, probe)
            self.assertEqual(result["place_context"], {
                "local_place_id": LOCAL, "name": "Local place", "extension": 1})
            self.assertEqual(result["runs"], [{"run_id": "earlier"}, old_run])
            self.assertIsNone(result["run"])
            self.assertEqual(result["assets"], original["assets"])
        self.assertEqual(original["runs"], [{"run_id": "earlier"}])

    def test_manifest_accepts_null_or_missing_context(self):
        for original in ({}, {"place_context": None}):
            result = helper.mirror_manifest(original, self.probe(), {"studio_id": "selected"})
            self.assertEqual(result["place_context"], {
                "local_place_id": LOCAL, "name": "Local place", "studio_id": "selected"})

    def test_shipped_luau_lifecycle(self):
        subprocess.run(["lune", "run", "tests/local-place-identity.luau"], cwd=ROOT, check=True,
                       capture_output=True, text=True)

if __name__ == "__main__":
    unittest.main()
