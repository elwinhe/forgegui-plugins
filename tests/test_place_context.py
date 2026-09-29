"""Offline input-contract checks, not a simulation of Claude or live history."""
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import unittest

from jsonschema import Draft7Validator, FormatChecker


ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "plugins/forgegui-roblox-builder/skills/forgegui-roblox-builder"
PIN = json.loads((ROOT / "tests/backend-place-context-contract.json").read_text())
TOOLS = {tool["name"]: tool for tool in PIN["tools"]}
CASES = json.loads((ROOT / "tests/place-context-requests.json").read_text())["cases"]
EXAMPLE = json.loads(re.search(
    r"```json\n(.*?)\n```", (SKILL / "references/place-context.md").read_text(), re.S
).group(1))


def validator(name):
    return Draft7Validator(TOOLS[name]["input_schema"], format_checker=FormatChecker())


class PlaceContextContractTests(unittest.TestCase):
    def test_installed_run_create_example(self):
        self.assertEqual(EXAMPLE["tool"], "run_create")
        validator(EXAMPLE["tool"]).validate(EXAMPLE["arguments"])
        for field in ["intended_place_id", "intended_universe_id"]:
            self.assertIsInstance(EXAMPLE["arguments"][field], str)

    def test_all_supported_operation_examples(self):
        supported = {name for name, tool in TOOLS.items()
                     if "run_id" in tool["input_schema"].get("properties", {})
                     and not name.startswith("run_")}
        self.assertEqual(supported, {c["tool"] for c in CASES if "run_id" in c["arguments"]})
        for case in CASES:
            with self.subTest(tool=case["tool"]):
                validator(case["tool"]).validate(case["arguments"])
                self.assertFalse(validator(case["tool"]).is_valid(
                    {**case["arguments"], "conversation_id": "invented"}))

    def test_large_decimal_strings_roundtrip_without_precision_loss(self):
        for value in ["9007199254740993", "18446744073709551615", "99999999999999999999"]:
            request = {**EXAMPLE["arguments"], "intended_place_id": value,
                       "intended_universe_id": value}
            restored = json.loads(json.dumps(request))
            validator("run_create").validate(restored)
            self.assertEqual(restored["intended_place_id"], value)
            self.assertEqual(restored["intended_universe_id"], value)

    def test_zero_missing_and_malformed_ids(self):
        for field in ["intended_place_id", "intended_universe_id"]:
            for value in ["0", 0, 123, 9007199254740993, "01", "-1", "1e16", "1.5", "", None,
                          "1" * 21]:
                with self.subTest(field=field, value=value):
                    self.assertFalse(validator("run_create").is_valid(
                        {**EXAMPLE["arguments"], field: value}))
        # Omission supports legacy unbound work; it does not establish a mapping.
        validator("run_create").validate({"request_id": "unbound-session", "name": "Local asset"})

    def test_no_invented_run_create_fields_or_overlong_labels(self):
        for field in ["studio_id", "owner_id", "conversation_id", "place_id", "run_id", "api_key"]:
            self.assertFalse(validator("run_create").is_valid(
                {**EXAMPLE["arguments"], field: "invented"}))
        for label in ["", "x" * 121]:
            self.assertFalse(validator("run_create").is_valid(
                {**EXAMPLE["arguments"], "external_project_label": label}))

    def test_old_schema_rejects_context_instead_of_guessing_support(self):
        schema = copy.deepcopy(TOOLS["run_create"]["input_schema"])
        for field in ["intended_place_id", "intended_universe_id", "external_project_label"]:
            del schema["properties"][field]
        self.assertFalse(Draft7Validator(schema).is_valid(EXAMPLE["arguments"]))
        Draft7Validator(schema).validate({"request_id": "legacy-session", "name": "Local asset"})

    def test_status_and_retry_use_original_identifier_only(self):
        for case in CASES:
            if case["tool"] not in ["generation_status", "generation_retry", "publication_status"]:
                continue
            for field in ["run_id", "intended_place_id", "request_id"]:
                with self.subTest(tool=case["tool"], field=field):
                    self.assertFalse(validator(case["tool"]).is_valid(
                        {**case["arguments"], field: "00000000-0000-4000-8000-000000000002"}))

    def test_reference_is_reachable_and_in_shared_package_inventory(self):
        # Packaging reachability only; matching text cannot prove model behavior.
        self.assertIn(
            "(references/place-context.md)", (SKILL / "SKILL.md").read_text())
        inventory = json.loads((ROOT / "release/openai/sources.json").read_text())
        self.assertIn("references/place-context.md", inventory)

    @unittest.skipUnless(os.environ.get("FORGEGUI_BACKEND_CONTRACT"), "optional exact backend export comparison")
    def test_pin_matches_backend_export(self):
        raw = Path(os.environ["FORGEGUI_BACKEND_CONTRACT"]).read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(), PIN["export_sha256"])
        backend = json.loads(raw)
        self.assertEqual(backend["schema_version"], PIN["schema_version"])
        actual = {tool["name"]: tool for tool in backend["tools"]}
        for name, tool in TOOLS.items():
            self.assertEqual(tool, actual[name])


if __name__ == "__main__":
    unittest.main()
