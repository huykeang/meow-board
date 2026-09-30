# 🐱 Meowboard

Clipboard history for GNOME. It runs in the background, keeps the last 100 copied texts, and opens with a keyboard shortcut.

The installer writes only under your home directory. It does not use `sudo`.

## Demo

<video src="https://raw.githubusercontent.com/huykeang/meow-board/main/demo/meowboard-demo.webm" width="720" controls></video>

## Install
```bash
curl -fsSL https://raw.githubusercontent.com/huykeang/meow-board/main/install.sh | bash
```

From a local copy:

```bash
./install.sh
```

## What you need

A GNOME session that already has these installed:

- Python 3
- PyGObject and GTK 3 (`python3-gi`, `gir1.2-gtk-3.0`)
- `libX11.so.6`

They are already present on a normal GNOME desktop. An account without administrator rights cannot install them. If the check fails, ask an admin to install:

```bash
python3 python3-gi gir1.2-gtk-3.0 gir1.2-gdkpixbuf-2.0 libx11-6
```

## What the installer does

- Copies `meowboard` and `meowboard-toggle` to `~/.local/bin`
- Installs the icon, desktop entry, and user service `meowboard.service`
- Starts that service for the current user
- Sets the shortcut to Ctrl+Shift+Space when Meowboard does not already have one
- Adds `~/.local/bin` to `PATH` in `~/.profile` when it is missing

If `~/.local/share/meowboard` does not exist yet and `~/.local/share/hk-clipboard` does, history and settings are copied across. An older `hk-clipboard` user service is stopped so both apps do not watch the clipboard.

Open Meowboard with Ctrl+Shift+Space, or run `meowboard toggle`. Change the shortcut from the settings button inside the window.

## Uninstall

```bash
./uninstall.sh
```

That removes the program files and the user service. Clipboard history stays in `~/.local/share/meowboard`.

```bash
./uninstall.sh --purge
```

`--purge` deletes that history too.
