import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "sync_notices.py"


class SyncNoticesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        scripts = self.root / "scripts"
        scripts.mkdir()
        self.script = scripts / SCRIPT.name
        shutil.copyfile(SCRIPT, self.script)
        (self.root / "LICENSE").write_text("Example project license.\n")
        (self.root / "CREDITS.md").write_text("Example project credit.\n")
        self.assets = self.root / "movie_box_app" / "assets" / "notices"

    def run_script(self, *args):
        return subprocess.run(
            [sys.executable, str(self.script), *args],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_check_rejects_missing_assets_without_writing(self):
        self.assertEqual(self.run_script("--check").returncode, 1)
        self.assertFalse(self.assets.exists())

    def test_sync_copies_canonical_bytes_and_check_passes(self):
        self.assertEqual(self.run_script().returncode, 0)
        for name in ("LICENSE", "CREDITS.md"):
            self.assertEqual((self.assets / name).read_bytes(), (self.root / name).read_bytes())
        self.assertEqual(self.run_script("--check").returncode, 0)

    def test_check_preserves_stale_file_until_explicit_sync(self):
        self.assertEqual(self.run_script().returncode, 0)
        notice = self.assets / "LICENSE"
        notice.write_text("Outdated notice.\n")
        self.assertEqual(self.run_script("--check").returncode, 1)
        self.assertEqual(notice.read_text(), "Outdated notice.\n")
        self.assertEqual(self.run_script().returncode, 0)
        self.assertEqual(self.run_script("--check").returncode, 0)


if __name__ == "__main__":
    unittest.main()
