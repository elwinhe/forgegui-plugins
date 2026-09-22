"""Offline caller-guidance regressions, NOT a backend contract or agent execution test."""
import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "plugins/forgegui-roblox-builder/skills/forgegui-roblox-builder"
REF = SKILL / "references"
GUIDE = (REF / "publishing-connections.md").read_text()
PROPOSAL = json.loads((ROOT / "tests/publishing-connections.json").read_text())
CASES = {case["name"]: case for case in PROPOSAL["cases"]}


def action_table():
    """Read the normative behavior from the shipped guide, not a duplicate policy."""
    table = GUIDE.split("| Condition | Allowed next action | Forbidden actions |", 1)[1]
    rows = {}
    for line in table.splitlines()[2:]:
        if not line.startswith("|"):
            break
        condition, allowed, forbidden = [cell.strip() for cell in line.split("|")[1:-1]]
        rows[condition] = (allowed, set(forbidden.split(", ")))
    return rows


def safe_selector(value, integrated=False):
    """PRD selector boundary only; deliberately not an exported backend schema."""
    prefix = {"mode": "publish", "platform": "roblox"} if integrated else {"platform": "roblox"}
    if any(value.get(key) != expected for key, expected in prefix.items()):
        return False
    extra = set(value) - set(prefix)
    if extra == {"connection_id"}:
        return isinstance(value["connection_id"], str) and bool(value["connection_id"].strip())
    return extra == set() if integrated else (
        extra == {"creator"} and value["creator"] == "configured_shared_group"
    )


class PublishingConnectionsGuidanceTests(unittest.TestCase):
    def test_success_and_failure_actions_in_shipped_guidance(self):
        scenarios = [
            ("direct", "generate_direct", {"require_connection", "publish"}),
            ("selected_active_usable_scoped", "submit_selected", {"select_first", "change_creator"}),
            ("selection_missing", "ask_destination", {"paid_work", "select_first"}),
            ("discovery_unavailable", "report_unavailable", {"paid_work", "advertise_connection", "shared_fallback"}),
            ("connection_ineligible", "report_unavailable", {"paid_work", "shared_fallback", "change_creator"}),
            ("type_or_route_unavailable", "report_unavailable", {"paid_work", "shared_fallback"}),
            ("scope_missing", "report_scope", {"paid_work", "broaden_scopes"}),
            ("credential_requested", "settings_only", {"chat_key", "mcp_key", "command_key", "ledger_key"}),
            ("legacy_explicit_usable", "submit_legacy", {"infer_consent"}),
            ("integrated_pending", "poll_original", {"standalone_publish", "local_upload", "regenerate"}),
            ("pending_moderation", "poll_original", {"insert", "regenerate"}),
            ("partial_audio", "inspect_members", {"republish_ready", "regenerate_batch", "discard_receipts"}),
            ("ready_creator_matches", "verify_access_and_studio", {"claim_verified_without_checks"}),
            ("creator_mismatch", "reconcile_original", {"insert", "change_creator", "shared_fallback"}),
            ("failed", "report_preserve_artifact", {"regenerate", "shared_fallback"}),
            ("ambiguous", "reconcile_original", {"resend", "new_request_id", "shared_fallback", "local_upload", "change_creator"}),
            ("unknown_state", "reconcile_original", {"resend", "insert"}),
            ("revoked_after_acceptance", "read_original_or_reconcile", {"resend", "change_creator", "shared_fallback"}),
        ]
        table = action_table()
        self.assertEqual(set(table), {row[0] for row in scenarios})
        for condition, expected_action, forbidden in scenarios:
            with self.subTest(condition=condition):
                action, actual_forbidden = table[condition]
                self.assertEqual(action, expected_action)
                self.assertTrue(forbidden <= actual_forbidden)
                self.assertNotIn(action, actual_forbidden)

    def test_preflight_and_ambiguous_conditions_are_defined(self):
        for condition in ("needs_validation", "expired", "revoked", "disabled", "foreign",
                          "outcome_unknown", "needs_reconciliation", "lost response", "timeout"):
            self.assertIn(condition, GUIDE)
        for rule in ("publication_connections_list` (`publication:read`)",
                     "generation:write` plus `publication:write", "strictly less than 420",
                     "Never republish integrated outputs", "Never add new defaults",
                     "most restrictive action", "No raw keys", "OAuth is unavailable",
                     "Preserve intentional holes/openings", "not_performed"):
            self.assertIn(rule, GUIDE)

    def test_real_entry_paths_link_to_connection_preflight(self):
        for path in [ROOT / "README.md", ROOT / "SETUP.md", SKILL / "SKILL.md",
                     *(REF / name for name in ["3d-assets.md", "audio-publication.md",
                                               "preparation-installation.md", "asset-upload.md",
                                               "project-manifest.md"])]:
            with self.subTest(path=path):
                self.assertRegex(path.read_text(), r"\]\([^)]*publishing-connections\.md\)")

    def test_connection_examples_match_pinned_backend(self):
        from jsonschema import Draft7Validator, FormatChecker
        self.assertEqual(PROPOSAL["status"], "input_contract_validated_hosted_not_verified")
        pinned = json.loads((ROOT / "tests/backend-preparation-contract.json").read_text())
        self.assertEqual(pinned["schema_version"], "1.9.0")
        tools = {tool["name"]: tool for tool in pinned["tools"]}
        for case in CASES.values():
            Draft7Validator(tools[case["tool"]]["input_schema"], format_checker=FormatChecker()).validate(case["arguments"])
        self.assertEqual(tools["publication_connections_list"]["scope"], "publication:read")
        for name in ["generation_model_3d", "generation_music", "generation_sound_effect"]:
            self.assertEqual(tools[name]["conditional_scopes"]["delivery.mode=publish"], ["publication:write"])
        request = CASES["publish-model-connection"]["arguments"]
        schema = Draft7Validator(tools["artifact_publish"]["input_schema"], format_checker=FormatChecker())
        for extra in [{"creator": "configured_shared_group"}, {"group_id": "123"}, {"api_key": "forbidden"}]:
            self.assertFalse(schema.is_valid({**request, "destination": {**request["destination"], **extra}}))

    def test_discovery_and_all_three_generators(self):
        self.assertEqual(CASES["discover-connections"]["tool"], "publication_connections_list")
        self.assertEqual(CASES["discover-connections"]["arguments"], {})
        connections = PROPOSAL["discovery_example"]["connections"]
        selected = connections[0]
        self.assertEqual({c["creator"]["type"] for c in connections}, {"user", "group"})
        for kind, tool in [("model", "generation_model_3d"), ("music", "generation_music"),
                           ("sfx", "generation_sound_effect")]:
            case = CASES[kind + "-connection"]
            self.assertEqual(case["tool"], tool)
            self.assertTrue(safe_selector(case["arguments"]["delivery"], integrated=True))
            self.assertEqual(case["arguments"]["delivery"]["connection_id"], selected["connection_id"])
            direct = CASES["direct-" + kind]["arguments"]["delivery"]
            self.assertEqual(direct, {"mode": "direct"})
        self.assertLess(CASES["music-connection"]["arguments"]["music_length_seconds"], 420)

    def test_standalone_selector_union_and_forbidden_credentials(self):
        for kind in ("model", "image", "audio"):
            args = CASES["publish-" + kind + "-connection"]["arguments"]
            self.assertEqual(args["asset_type"].lower(), kind)
            self.assertTrue(safe_selector(args["destination"]))
        selector = CASES["publish-model-connection"]["arguments"]["destination"]
        for field, value in [("creator", "configured_shared_group"), ("creator", {"type": "user", "id": "1"}),
                             ("api_key", "forbidden-placeholder"), ("credential_slot", "primary"),
                             ("user_id", "1"), ("group_id", "2"), ("token", "forbidden-placeholder")]:
            with self.subTest(field=field, value=value):
                self.assertFalse(safe_selector({**selector, field: value}))
        for bad in [{"platform": "roblox"}, {**selector, "connection_id": ""},
                    {**selector, "connection_id": None}, {**selector, "platform": "other"}]:
            self.assertFalse(safe_selector(bad))
        self.assertTrue(safe_selector(CASES["legacy-audio"]["arguments"]["destination"]))
        self.assertTrue(safe_selector(CASES["legacy-model"]["arguments"]["delivery"], integrated=True))

    def test_no_secret_fields_in_positive_fixtures(self):
        forbidden = {"api_key", "token", "headers", "credential_slot", "credential_id",
                     "credential_version", "secret", "secret_path", "signed_url", "account_id"}
        def inspect(value):
            if isinstance(value, dict):
                self.assertFalse(forbidden & value.keys())
                for child in value.values():
                    inspect(child)
            elif isinstance(value, list):
                for child in value:
                    inspect(child)
        inspect(PROPOSAL)

    def test_ledger_example_preserves_partial_receipts_without_inventing_decisions(self):
        ledger = PROPOSAL["ledger_example"]
        asset = ledger["assets"][0]
        self.assertEqual(ledger["version"], 2)
        self.assertEqual(ledger["decisions"], [])
        self.assertEqual(asset["publishing_destination"]["creator"], {"type": "group", "id": "12345"})
        outputs = asset["delivery"]["outputs"]
        self.assertEqual([o["index"] for o in outputs], [0, 1])
        self.assertEqual(outputs[0]["asset_id"], "9007199254740993")
        self.assertEqual(outputs[0]["status"], "ready")
        self.assertIsNone(outputs[1]["publication_id"])
        self.assertIsNone(outputs[1]["asset_id"])
        self.assertEqual(outputs[1]["status"], "needs_reconciliation")
        self.assertNotIn("roblox_asset_id", asset)
        self.assertEqual(asset["installation_observed"]["checks"][0]["outcome"], "not_performed")
        starter = json.loads((REF / "forgegui-project.example.json").read_text())
        self.assertEqual(starter["decisions"], [])
        self.assertEqual(starter["assets"], [])
        self.assertNotIn("publishing_destination", starter)
        manifest = (REF / "project-manifest.md").read_text()
        for rule in ["preserving every existing field and asset identifier", "only if no run field exists",
                     "unknown extension fields, decisions and every receipt", "Missing selection stays absent",
                     "Existing\nv2 ledgers stay at version 2", "never writes a selected decision"]:
            self.assertIn(rule, manifest)

    def test_local_markdown_links_resolve(self):
        paths = [ROOT / "README.md", ROOT / "SETUP.md", SKILL / "SKILL.md",
                 *(REF / name for name in ["publishing-connections.md", "3d-assets.md", "audio-publication.md",
                                           "preparation-installation.md", "asset-upload.md", "project-manifest.md"])]
        for path in paths:
            for target in re.findall(r"\]\(([^)]+)\)", path.read_text()):
                if "://" in target or target.startswith("#"):
                    continue
                with self.subTest(path=path, target=target):
                    self.assertTrue((path.parent / target.split("#")[0]).exists())


if __name__ == "__main__":
    unittest.main()
