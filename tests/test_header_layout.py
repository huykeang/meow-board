import importlib.machinery
import importlib.util
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
LOADER = importlib.machinery.SourceFileLoader(
    "meowboard_header",
    str(PROJECT_ROOT / "bin" / "meowboard"),
)
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
MEOWBOARD = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(MEOWBOARD)


class HeaderLayoutTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        root = Path(self.directory.name)
        data = root / "data"
        data.mkdir()
        icon = (
            PROJECT_ROOT
            / "share"
            / "icons"
            / "hicolor"
            / "128x128"
            / "apps"
            / "meowboard.png"
        )
        self.original = {}
        for name, value in {
            "DATA_DIR": str(data),
            "HISTORY_FILE": str(data / "history.json"),
            "SETTINGS_FILE": str(data / "settings.json"),
            "SOCKET_FILE": str(root / "meowboard.sock"),
            "ICON_FILE": str(icon),
        }.items():
            self.original[name] = getattr(MEOWBOARD, name)
            setattr(MEOWBOARD, name, value)
        self.app = MEOWBOARD.ClipboardApp()

    def tearDown(self):
        self.app.destroy()
        for name, value in self.original.items():
            setattr(MEOWBOARD, name, value)
        self.directory.cleanup()

    def test_search_replaces_the_title_at_the_top_left(self):
        main = self.app.get_child()
        header = main.get_children()[0]

        for child in header.get_children():
            if isinstance(child, MEOWBOARD.Gtk.Label):
                self.assertNotIn("Meowboard", child.get_text())

        self.assertIs(self.app.search.get_parent(), header)
        self.assertIs(header.get_children()[0], self.app.search)

    def test_search_extends_to_the_settings_button(self):
        self.app.show_all()
        while MEOWBOARD.Gtk.events_pending():
            MEOWBOARD.Gtk.main_iteration()

        header = self.app.get_child().get_children()[0]
        gear = next(
            child
            for child in header.get_children()
            if child.get_tooltip_text() == "Settings"
        )
        search = self.app.search.get_allocation()
        gear_alloc = gear.get_allocation()
        gap = gear_alloc.x - (search.x + search.width)

        self.assertGreaterEqual(gap, 0)
        self.assertLessEqual(gap, 16)


if __name__ == "__main__":
    unittest.main()
