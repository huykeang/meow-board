import importlib.machinery
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace


PROJECT_ROOT = Path(__file__).resolve().parents[1]
LOADER = importlib.machinery.SourceFileLoader(
    "meowboard_app",
    str(PROJECT_ROOT / "bin" / "meowboard"),
)
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
MEOWBOARD = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(MEOWBOARD)


class HistoryLimitTests(unittest.TestCase):
    def test_default_history_limit_is_100(self):
        self.assertEqual(MEOWBOARD.DEFAULT_SETTINGS["history_limit"], 100)

    def test_loaded_history_limit_is_clamped_to_supported_range(self):
        with tempfile.TemporaryDirectory() as directory:
            settings_file = Path(directory) / "settings.json"
            original_settings_file = MEOWBOARD.SETTINGS_FILE
            MEOWBOARD.SETTINGS_FILE = str(settings_file)
            try:
                settings_file.write_text(
                    json.dumps({"history_limit": 0}),
                    encoding="utf-8",
                )
                settings = MEOWBOARD.ClipboardApp.load_settings(
                    SimpleNamespace()
                )
                self.assertEqual(settings["history_limit"], 1)

                settings_file.write_text(
                    json.dumps({"history_limit": 1001}),
                    encoding="utf-8",
                )
                settings = MEOWBOARD.ClipboardApp.load_settings(
                    SimpleNamespace()
                )
                self.assertEqual(settings["history_limit"], 1000)
            finally:
                MEOWBOARD.SETTINGS_FILE = original_settings_file

    def test_new_clipboard_items_respect_configured_limit(self):
        app = SimpleNamespace(
            settings={"history_limit": 2},
            history=["second", "third"],
            save_history=lambda: None,
            update_list=lambda: None,
        )

        MEOWBOARD.ClipboardApp.add_clipboard(app, "first")

        self.assertEqual(app.history, ["first", "second"])


if __name__ == "__main__":
    unittest.main()
