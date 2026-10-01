#!/usr/bin/env bash
# Install 🐱 Meowboard into the current user's home directory.
# This script does not use sudo.
set -euo pipefail

REPO="huykeang/meow-board"
ASSET="meowboard.tar.gz"

if [[ "${EUID}" -eq 0 ]]; then
    echo "Run install.sh as your own user, without sudo." >&2
    exit 1
fi

ROOT=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [[ -z "${ROOT}" || ! -f "${ROOT}/bin/meowboard" ]]; then
    if [[ "${REPO}" == "OWNER/REPO" ]]; then
        echo "Set REPO at the top of install.sh to your GitHub owner/name, then use the one-line install." >&2
        exit 1
    fi

    tmp="$(mktemp -d)"
    curl -fsSL "https://github.com/${REPO}/releases/latest/download/${ASSET}" \
        | tar -xz -C "${tmp}" --strip-components=1
    bash "${tmp}/install.sh"
    status=$?
    rm -rf "${tmp}"
    exit "${status}"
fi

missing=()

if ! command -v python3 >/dev/null 2>&1; then
    missing+=("python3")
fi

if [[ ${#missing[@]} -eq 0 ]]; then
    if ! python3 - << 'PY'
import sys

try:
    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    gi.require_version("GdkX11", "3.0")
    from gi.repository import Gtk, Gdk, GdkX11, Gio, GLib, Pango
except Exception:
    sys.exit(1)
PY
    then
        missing+=("python3-gi gir1.2-gtk-3.0")
    fi
fi

if [[ ${#missing[@]} -eq 0 ]]; then
    if ! python3 - << 'PY'
import ctypes
import sys

try:
    ctypes.CDLL("libX11.so.6")
except OSError:
    sys.exit(1)
PY
    then
        missing+=("libx11-6")
    fi
fi

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Meowboard needs Python 3 with GTK 3 (PyGObject) and libX11." >&2
    echo "These come with a normal GNOME desktop and cannot be installed without an administrator." >&2
    echo >&2
    echo "Ask an admin to install:" >&2
    echo "  python3 python3-gi gir1.2-gtk-3.0 gir1.2-gdkpixbuf-2.0 libx11-6" >&2
    exit 1
fi

install -d "${HOME}/.local/bin"
install -m 755 "${ROOT}/bin/meowboard" "${HOME}/.local/bin/meowboard"
install -m 755 "${ROOT}/bin/meowboard-toggle" "${HOME}/.local/bin/meowboard-toggle"

install -d "${HOME}/.local/share/icons/hicolor/128x128/apps"
install -m 644 \
    "${ROOT}/share/icons/hicolor/128x128/apps/meowboard.png" \
    "${HOME}/.local/share/icons/hicolor/128x128/apps/meowboard.png"

install -d "${HOME}/.local/share/applications"
python3 - "${ROOT}/share/applications/meowboard.desktop.in" \
    "${HOME}/.local/share/applications/meowboard.desktop" << 'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
text = source.read_text(encoding="utf-8").replace("@HOME@", str(pathlib.Path.home()))
destination.write_text(text, encoding="utf-8")
PY

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${HOME}/.local/share/applications" || true
fi

old_data="${HOME}/.local/share/hk-clipboard"
new_data="${HOME}/.local/share/meowboard"
if [[ ! -e "${new_data}" && -d "${old_data}" ]]; then
    install -d "${new_data}"
    if [[ -f "${old_data}/history.json" ]]; then
        cp -a "${old_data}/history.json" "${new_data}/history.json"
    fi
    if [[ -f "${old_data}/settings.json" ]]; then
        cp -a "${old_data}/settings.json" "${new_data}/settings.json"
    fi
fi

install -d "${HOME}/.config/systemd/user"
install -m 644 \
    "${ROOT}/share/systemd/user/meowboard.service" \
    "${HOME}/.config/systemd/user/meowboard.service"

if command -v systemctl >/dev/null 2>&1; then
    if systemctl --user list-unit-files "hk-clipboard.service" --no-legend 2>/dev/null \
        | grep -q "hk-clipboard.service"; then
        systemctl --user disable --now "hk-clipboard.service" || true
    fi
    systemctl --user daemon-reload
    systemctl --user enable "meowboard.service"
    systemctl --user restart "meowboard.service"
fi

python3 - << 'PY' || echo "Shortcut was not set. Change it from Meowboard settings on a GNOME desktop."
import os
import pathlib
import subprocess
import ast


def gsettings(*args):
    return subprocess.check_output(["gsettings", *args], text=True).strip()


def schema_names(kind):
    return set(gsettings(kind).splitlines())


media = "org.gnome.settings-daemon.plugins.media-keys"
custom = "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding"
if media not in schema_names("list-schemas") or custom not in schema_names("list-relocatable-schemas"):
    raise SystemExit(0)

new_path = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/meowboard/"
old_path = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/hk-clipboard/"

raw = gsettings("get", media, "custom-keybindings")
if raw.startswith("@as "):
    raw = raw[4:].strip()
paths = [item for item in ast.literal_eval(raw) if item != old_path]
if new_path not in paths:
    paths.append(new_path)

rendered = "[" + ", ".join(repr(item) for item in paths) + "]"
subprocess.check_call(["gsettings", "set", media, "custom-keybindings", rendered])

binding = gsettings("get", f"{custom}:{new_path}", "binding")
if binding.startswith("@ms "):
    binding = binding[4:].strip()
if len(binding) >= 2 and binding[0] == binding[-1] and binding[0] in "'\"":
    binding = binding[1:-1]

if binding:
    raise SystemExit(0)

command = str(pathlib.Path.home() / ".local/bin/meowboard-toggle")
base = f"{custom}:{new_path}"
subprocess.check_call(["gsettings", "set", base, "name", "🐱 Meowboard"])
subprocess.check_call(["gsettings", "set", base, "command", command])
subprocess.check_call(["gsettings", "set", base, "binding", "<Primary><Shift>space"])
PY

profile="${HOME}/.profile"
if [[ ":${PATH}:" != *":${HOME}/.local/bin:"* ]]; then
    if [[ ! -f "${profile}" ]] || ! grep -q '.local/bin' "${profile}"; then
        printf '\n# Added by Meowboard\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "${profile}"
        echo "Added ~/.local/bin to PATH in ~/.profile. Open a new terminal before running meowboard."
    fi
fi

echo "🐱 Meowboard is installed."
echo "Shortcut: Ctrl+Shift+Space (change it in Meowboard settings)."
echo "Command: meowboard toggle"
