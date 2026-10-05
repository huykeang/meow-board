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


class DeleteKeyTests(unittest.TestCase):
    def test_delete_key_removes_selected_item(self):
        calls = []
        app = SimpleNamespace(
            search=SimpleNamespace(is_focus=lambda: False),
            delete_selected=lambda: calls.append("deleted"),
        )
        event = SimpleNamespace(
            keyval=MEOWBOARD.Gdk.KEY_Delete,
            state=0,
        )

        handled = MEOWBOARD.ClipboardApp.on_key_press(
            app,
            None,
            event,
        )

        self.assertTrue(handled)
        self.assertEqual(calls, ["deleted"])

    def test_delete_key_removes_item_while_search_has_focus(self):
        calls = []
        app = SimpleNamespace(
            search=SimpleNamespace(is_focus=lambda: True),
            delete_selected=lambda: calls.append("deleted"),
        )
        event = SimpleNamespace(
            keyval=MEOWBOARD.Gdk.KEY_Delete,
            state=0,
        )

        handled = MEOWBOARD.ClipboardApp.on_key_press(
            app,
            None,
            event,
        )

        self.assertTrue(handled)
        self.assertEqual(calls, ["deleted"])


class DeleteSelectionTests(unittest.TestCase):
    def _app_deleting_index(self, history, index):
        selected = []
        rows_after = []

        class Row:
            def __init__(self, row_index):
                self._index = row_index

            def get_index(self):
                return self._index

            def get_allocation(self):
                return SimpleNamespace(y=0, height=20)

        class ListBox:
            def get_selected_row(self):
                return Row(index)

            def get_children(self):
                return rows_after

            def select_row(self, row):
                selected.append(row)

        app = SimpleNamespace(
            history=list(history),
            filtered_history=list(history),
            listbox=ListBox(),
            save_history=lambda: None,
            history_scroll=SimpleNamespace(
                get_vadjustment=lambda: SimpleNamespace(
                    get_value=lambda: 0,
                    get_page_size=lambda: 100,
                    set_value=lambda value: None,
                )
            ),
        )

        def update_list():
            app.filtered_history = list(app.history)
            rows_after[:] = [
                Row(row_index)
                for row_index in range(len(app.history))
            ]

        app.update_list = update_list
        app.get_selected_item = (
            lambda: MEOWBOARD.ClipboardApp.get_selected_item(app)
        )
        app.select_list_index = (
            lambda index: MEOWBOARD.ClipboardApp.select_list_index(
                app,
                index,
            )
        )
        app.reveal_row = (
            lambda row: MEOWBOARD.ClipboardApp.reveal_row(app, row)
        )
        app._selected = selected
        return app

    def test_deleting_last_item_selects_the_previous_clipboard(self):
        app = self._app_deleting_index(
            ["clipboard1", "clipboard2", "clipboard3", "clipboard4"],
            3,
        )

        MEOWBOARD.ClipboardApp.delete_selected(app)

        self.assertEqual(
            app.history,
            ["clipboard1", "clipboard2", "clipboard3"],
        )
        self.assertEqual(app._selected[-1].get_index(), 2)

    def test_deleting_middle_item_keeps_the_same_list_index(self):
        app = self._app_deleting_index(
            ["clipboard1", "clipboard2", "clipboard3", "clipboard4"],
            1,
        )

        MEOWBOARD.ClipboardApp.delete_selected(app)

        self.assertEqual(
            app.history,
            ["clipboard1", "clipboard3", "clipboard4"],
        )
        self.assertEqual(app._selected[-1].get_index(), 1)

    def test_deleting_the_only_item_leaves_the_list_empty(self):
        app = self._app_deleting_index(["clipboard1"], 0)

        MEOWBOARD.ClipboardApp.delete_selected(app)

        self.assertEqual(app.history, [])
        self.assertEqual(app._selected, [])

    def test_deleting_keeps_the_selected_row_in_view(self):
        row_height = 36
        selected_index = 12
        page_size = 180
        history = [
            f"clipboard{index}"
            for index in range(30)
        ]
        laid_out = {"ready": False}
        rows_after = []

        class Adjustment:
            def __init__(self):
                self.value = selected_index * row_height

            def get_value(self):
                return self.value

            def get_page_size(self):
                return page_size

            def set_value(self, value):
                self.value = value

        class Row:
            def __init__(self, row_index):
                self._index = row_index
                self._handlers = []

            def get_index(self):
                return self._index

            def get_allocation(self):
                if not laid_out["ready"]:
                    return SimpleNamespace(y=0, height=1)

                return SimpleNamespace(
                    y=self._index * row_height,
                    height=row_height,
                )

            def connect(self, signal, callback):
                handler_id = len(self._handlers)
                self._handlers.append((signal, callback))
                return handler_id

            def disconnect(self, handler_id):
                self._handlers[handler_id] = None

            def allocate(self):
                allocation = self.get_allocation()
                for handler in list(self._handlers):
                    if handler is None:
                        continue
                    signal, callback = handler
                    if signal == "size-allocate":
                        callback(self, allocation)

        adjustment = Adjustment()

        class ListBox:
            def get_selected_row(self):
                return Row(selected_index)

            def get_children(self):
                return rows_after

            def select_row(self, row):
                pass

        app = SimpleNamespace(
            history=list(history),
            filtered_history=list(history),
            listbox=ListBox(),
            save_history=lambda: None,
            history_scroll=SimpleNamespace(
                get_vadjustment=lambda: adjustment
            ),
        )

        def update_list():
            app.filtered_history = list(app.history)
            adjustment.set_value(0)
            laid_out["ready"] = False
            rows_after[:] = [
                Row(row_index)
                for row_index in range(len(app.history))
            ]

        app.update_list = update_list
        app.get_selected_item = (
            lambda: MEOWBOARD.ClipboardApp.get_selected_item(app)
        )
        app.select_list_index = (
            lambda index: MEOWBOARD.ClipboardApp.select_list_index(
                app,
                index,
            )
        )
        app.reveal_row = (
            lambda row: MEOWBOARD.ClipboardApp.reveal_row(app, row)
        )

        MEOWBOARD.ClipboardApp.delete_selected(app)

        laid_out["ready"] = True
        for row in rows_after:
            row.allocate()

        selected_top = selected_index * row_height
        selected_bottom = selected_top + row_height
        visible_top = adjustment.get_value()
        visible_bottom = visible_top + page_size

        self.assertLess(selected_top, visible_bottom)
        self.assertGreater(selected_bottom, visible_top)


class ListActivationTests(unittest.TestCase):
    def test_list_requires_second_click_to_activate_selected_row(self):
        activation_modes = []
        listbox = SimpleNamespace(
            set_activate_on_single_click=activation_modes.append
        )

        MEOWBOARD.ClipboardApp.configure_listbox_activation(listbox)

        self.assertEqual(activation_modes, [False])


if __name__ == "__main__":
    unittest.main()
