import json
import subprocess
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
UPDATE_STATS = PROJECT_ROOT / "scripts" / "update_stats.py"


class UpdateStatsTests(unittest.TestCase):
    def test_sums_release_asset_downloads_into_stats(self):
        releases = [
            {
                "tag_name": "v2",
                "assets": [
                    {"name": "meowboard.tar.gz", "download_count": 2},
                ],
            },
            {
                "tag_name": "v1",
                "assets": [
                    {"name": "meowboard.tar.gz", "download_count": 5},
                    {"name": "notes.txt"},
                ],
            },
        ]
        stats = self._run(releases, updated_at="2026-10-01T02:00:00Z")

        self.assertEqual(
            stats,
            {"installs": 7, "updated_at": "2026-10-01T02:00:00Z"},
        )

    def test_leaves_stats_file_unchanged_when_download_total_matches(self):
        releases = [
            {
                "assets": [
                    {"name": "meowboard.tar.gz", "download_count": 7},
                ],
            }
        ]
        original = (
            '{\n  "installs": 7,\n  "updated_at": "2026-01-01T00:00:00Z"\n}\n'
        )
        with tempfile.TemporaryDirectory() as directory:
            releases_file = Path(directory) / "releases.json"
            stats_file = Path(directory) / "stats.json"
            releases_file.write_text(json.dumps(releases), encoding="utf-8")
            stats_file.write_text(original, encoding="utf-8")

            subprocess.run(
                [
                    "python3",
                    str(UPDATE_STATS),
                    str(releases_file),
                    str(stats_file),
                    "--updated-at",
                    "2026-10-01T02:00:00Z",
                ],
                check=True,
            )

            self.assertEqual(stats_file.read_text(encoding="utf-8"), original)

    def test_sums_download_counts_across_paginated_release_pages(self):
        pages = (
            '[{"assets": [{"name": "meowboard.tar.gz", "download_count": 2}]}]\n'
            '[{"assets": [{"name": "meowboard.tar.gz", "download_count": 3}]}]\n'
        )
        with tempfile.TemporaryDirectory() as directory:
            releases_file = Path(directory) / "releases.json"
            stats_file = Path(directory) / "stats.json"
            releases_file.write_text(pages, encoding="utf-8")
            stats_file.write_text(
                '{"installs": 0, "updated_at": null}\n',
                encoding="utf-8",
            )

            subprocess.run(
                [
                    "python3",
                    str(UPDATE_STATS),
                    str(releases_file),
                    str(stats_file),
                    "--updated-at",
                    "2026-10-01T02:00:00Z",
                ],
                check=True,
            )

            self.assertEqual(
                json.loads(stats_file.read_text(encoding="utf-8")),
                {"installs": 5, "updated_at": "2026-10-01T02:00:00Z"},
            )

    def _run(self, releases, updated_at):
        with tempfile.TemporaryDirectory() as directory:
            releases_file = Path(directory) / "releases.json"
            stats_file = Path(directory) / "stats.json"
            releases_file.write_text(json.dumps(releases), encoding="utf-8")
            stats_file.write_text(
                '{"installs": 0, "updated_at": null}\n',
                encoding="utf-8",
            )
            subprocess.run(
                [
                    "python3",
                    str(UPDATE_STATS),
                    str(releases_file),
                    str(stats_file),
                    "--updated-at",
                    updated_at,
                ],
                check=True,
            )
            return json.loads(stats_file.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
