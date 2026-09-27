import json
from pathlib import Path
import unittest

from jsonschema import Draft7Validator

ROOT = Path(__file__).resolve().parents[1]
PIN = json.loads((ROOT / "tests/backend-sound-effect-contract.json").read_text())


class SoundEffectContractTests(unittest.TestCase):
    def test_documented_request_and_categories(self):
        doc = ROOT / "plugins/forgegui-roblox-builder/skills/forgegui-roblox-builder/references/audio-publication.md"
        section = doc.read_text().split("## Sound-effect input contract", 1)[1]
        example = json.loads(section.split("```json\n", 1)[1].split("```", 1)[0])
        schema = PIN["tool"]["input_schema"]
        validator = Draft7Validator(schema)
        validator.validate(example)
        categories = ["ui", "combat", "ambient", "movement", "collectible", "notification", "default"]
        self.assertEqual(schema["properties"]["audio_category"]["enum"], categories)
        for category in categories:
            self.assertIn("`" + category + "`", section)
            validator.validate({**example, "audio_category": category})
        for category in ["weapon", "footstep", "UI", " ui ", "", None, 1]:
            self.assertFalse(validator.is_valid({**example, "audio_category": category}))
        del example["audio_category"]
        validator.validate(example)


if __name__ == "__main__":
    unittest.main()
