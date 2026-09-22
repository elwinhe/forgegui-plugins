import copy
import hashlib
import json
import os
from pathlib import Path
import unittest

from jsonschema import Draft7Validator, FormatChecker


ROOT = Path(__file__).resolve().parents[1]
PIN = json.loads((ROOT / "tests/backend-preparation-contract.json").read_text())
TOOLS = {tool["name"]: tool for tool in PIN["tools"]}
CASES = json.loads((ROOT / "tests/preparation-requests.json").read_text())["cases"]


def validator(tool):
    return Draft7Validator(TOOLS[tool]["input_schema"], format_checker=FormatChecker())


class PreparationContractTests(unittest.TestCase):
    def test_examples_match_exported_input_contract(self):
        for case in CASES:
            with self.subTest(case=case["name"]):
                validator(case["tool"]).validate(case["arguments"])

    def test_rejects_wrong_discriminator_and_invented_metadata(self):
        request = copy.deepcopy(next(c["arguments"] for c in CASES if c["name"] == "prepare-model"))
        for field, value in [("kind", "mesh"), ("installation_intent", {"size": 5})]:
            changed = copy.deepcopy(request)
            changed["asset"][field] = value
            self.assertFalse(validator("asset_prepare").is_valid(changed))
        changed = {**request, **request["asset"]}
        del changed["asset"]
        self.assertFalse(validator("asset_prepare").is_valid(changed))

    def test_rejects_unsupported_publication_destinations_and_types(self):
        request = next(c["arguments"] for c in CASES if c["name"] == "publish-model")
        for field, value in [("asset_type", "Animation"), ("artifact_ref", "https://example.com/model.glb"), ("destination", {"platform": "roblox", "creator": "user_oauth"})]:
            changed = copy.deepcopy(request)
            changed[field] = value
            self.assertFalse(validator("artifact_publish").is_valid(changed))

    def test_publishing_example_uses_prepared_identity(self):
        source = next(c["arguments"]["asset"]["source_ref"] for c in CASES if c["name"] == "prepare-model")
        prepared_job = next(c["arguments"]["job_id"] for c in CASES if c["name"] == "poll-preparation")
        publish = next(c["arguments"] for c in CASES if c["name"] == "publish-model")
        self.assertNotEqual(source, publish["artifact_ref"])
        self.assertEqual(publish["artifact_ref"], f"mcp-artifact:{prepared_job}:0")

    def test_standalone_audio_publication_preserves_destination_boundaries(self):
        audio = next(c["arguments"] for c in CASES if c["name"] == "publish-audio")
        self.assertTrue(validator("artifact_publish").is_valid(audio))
        self.assertFalse(validator("artifact_publish").is_valid({**audio, "api_key": "forbidden"}))
        self.assertFalse(validator("artifact_publish").is_valid({**audio, "destination": {
            "platform": "roblox", "creator": "configured_shared_group", "group_id": "123"
        }}))

    def test_audio_generation_supports_direct_and_integrated_publish(self):
        for name in ["generate-sfx", "generate-music"]:
            for mode in [None, "direct", "publish"]:
                case = next(c for c in CASES if c["name"] == name + ("-" + mode if mode else ""))
                with self.subTest(tool=case["tool"], mode=mode):
                    validator(case["tool"]).validate(case["arguments"])
            case = next(c for c in CASES if c["name"] == name)
            for delivery in [{"mode": "publish"}, {"mode": "publish", "platform": "other"}, {"mode": "direct", "platform": "roblox"}]:
                self.assertFalse(validator(case["tool"]).is_valid({**case["arguments"], "delivery": delivery}))
            old_schema = copy.deepcopy(TOOLS[case["tool"]]["input_schema"])
            del old_schema["properties"]["delivery"]
            published = next(c for c in CASES if c["name"] == name + "-publish")
            self.assertFalse(Draft7Validator(old_schema).is_valid(published["arguments"]))

    def test_older_backend_does_not_accept_audio_example(self):
        schema = copy.deepcopy(TOOLS["artifact_publish"]["input_schema"])
        schema["properties"]["asset_type"]["enum"].remove("Audio")
        audio = next(c["arguments"] for c in CASES if c["name"] == "publish-audio")
        self.assertFalse(Draft7Validator(schema).is_valid(audio))

    def test_audio_guidance_example_matches_contract(self):
        path = ROOT / "plugins/forgegui-roblox-builder/skills/forgegui-roblox-builder/references/audio-publication.md"
        example = json.loads(path.read_text().split("```json\n", 1)[1].split("```", 1)[0])
        validator("artifact_publish").validate(example)
        self.assertEqual(example["asset_type"], "Audio")

    def test_scope_mapping(self):
        for name in ["generation_music", "generation_sound_effect"]:
            self.assertEqual(TOOLS[name]["conditional_scopes"]["delivery.mode=publish"], ["publication:write"])
        for name, scope in {
            "asset_prepare": "generation:write",
            "artifact_publish": "publication:write",
            "publication_status": "publication:read",
            "run_append": "runs:write",
            "run_get": "runs:read",
        }.items():
            self.assertEqual(TOOLS[name]["scope"], scope)

    def test_package_and_ledger_versions(self):
        package = json.loads((ROOT / "plugins/forgegui-roblox-builder/.claude-plugin/plugin.json").read_text())
        marketplace = json.loads((ROOT / ".claude-plugin/marketplace.json").read_text())
        self.assertEqual(package["version"], marketplace["plugins"][0]["version"])
        self.assertEqual(package["version"], "1.7.0")
        ledger = json.loads((ROOT / "plugins/forgegui-roblox-builder/skills/forgegui-roblox-builder/references/forgegui-project.example.json").read_text())
        self.assertEqual(ledger["version"], 2)
        self.assertEqual(ledger["assets"], [])
        self.assertIsNone(ledger["run"])

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
