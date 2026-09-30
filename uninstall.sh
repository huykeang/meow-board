#!/usr/bin/env bash
# Remove the 🐱 Meowboard files installed under the current user's home.
# History is kept unless --purge is passed. This script does not use sudo.
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
    echo "Run uninstall.sh as your own user, without sudo." >&2
    exit 1
fi

purge=0
if [[ "${1:-}" == "--purge" ]]; then
    purge=1
elif [[ -n "${1:-}" ]]; then
    echo "Usage: uninstall.sh [--purge]" >&2
    exit 1
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl --user disable --now "meowboard.service" || true
    rm -f "${HOME}/.config/systemd/user/meowboard.service"
    systemctl --user daemon-reload || true
else
    rm -f "${HOME}/.config/systemd/user/meowboard.service"
fi

rm -f \
    "${HOME}/.local/bin/meowboard" \
    "${HOME}/.local/bin/meowboard-toggle" \
    "${HOME}/.local/share/applications/meowboard.desktop" \
    "${HOME}/.local/share/icons/hicolor/128x128/apps/meowboard.png"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${HOME}/.local/share/applications" || true
fi

python3 - << 'PY' || true
import ast
import subprocess


def gsettings(*args):
    return subprocess.check_output(["gsettings", *args], text=True).strip()


media = "org.gnome.settings-daemon.plugins.media-keys"
custom = "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding"
schemas = set(gsettings("list-schemas").splitlines())
relocatable = set(gsettings("list-relocatable-schemas").splitlines())
if media not in schemas or custom not in relocatable:
    raise SystemExit(0)

new_path = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/meowboard/"
raw = gsettings("get", media, "custom-keybindings")
if raw.startswith("@as "):
    raw = raw[4:].strip()
paths = [item for item in ast.literal_eval(raw) if item != new_path]
rendered = "[" + ", ".join(repr(item) for item in paths) + "]"
subprocess.check_call(["gsettings", "set", media, "custom-keybindings", rendered])

base = f"{custom}:{new_path}"
for key in ("binding", "command", "name"):
    subprocess.call(["gsettings", "reset", base, key])
PY

if [[ "${purge}" -eq 1 ]]; then
    rm -rf "${HOME}/.local/share/meowboard"
    echo "🐱 Meowboard was removed, including history."
else
    echo "🐱 Meowboard was removed. History is still in ~/.local/share/meowboard."
fi
