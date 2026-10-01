#!/usr/bin/env python3
"""Cache GitHub release download totals in stats.json."""

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path


def load_releases(text):
    decoder = json.JSONDecoder()
    index = 0
    releases = []
    length = len(text)
    while index < length:
        while index < length and text[index].isspace():
            index += 1
        if index >= length:
            break
        value, index = decoder.raw_decode(text, index)
        if isinstance(value, list):
            releases.extend(value)
        elif isinstance(value, dict):
            releases.append(value)
        else:
            raise SystemExit("releases file must contain release objects")
    return releases


def install_count(releases):
    total = 0
    for release in releases:
        if not isinstance(release, dict):
            raise SystemExit("releases file must contain release objects")
        for asset in release.get("assets") or []:
            if not isinstance(asset, dict):
                continue
            total += int(asset.get("download_count") or 0)
    return total


def current_installs(path):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(data, dict) or "installs" not in data:
        return None
    return data["installs"]


def render(installs, updated_at):
    payload = {"installs": installs, "updated_at": updated_at}
    return json.dumps(payload, indent=2) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("releases")
    parser.add_argument("stats")
    parser.add_argument("--updated-at")
    args = parser.parse_args()

    total = install_count(load_releases(Path(args.releases).read_text(encoding="utf-8")))
    stats_path = Path(args.stats)
    if current_installs(stats_path) == total:
        return

    updated_at = args.updated_at
    if not updated_at:
        updated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    stats_path.write_text(render(total, updated_at), encoding="utf-8")


if __name__ == "__main__":
    main()
