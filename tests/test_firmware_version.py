import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class FirmwareVersionTests(unittest.TestCase):
    def test_menu_version_matches_release_version(self):
        version = (ROOT / "VERSION").read_text().strip()
        header = (ROOT / "firmware" / "version.h").read_text()
        match = re.search(r'^#define GENTHANG_VERSION "([^"]+)"$', header, re.MULTILINE)

        self.assertIsNotNone(match)
        self.assertEqual(version, match.group(1))


if __name__ == "__main__":
    unittest.main()
