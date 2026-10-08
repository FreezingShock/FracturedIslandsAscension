#!/usr/bin/env python3
"""Download the Statistics icons so their pixels can colour a dropped item's edge (tools/gen_item_sprites.py reads them).

Reads every `key = "X"` ... `icon = "rbxassetid://N"` pair from src/Shared/Modules/Stats/StatisticsConfig.lua, writes
assets/stat_icons/ids.json (key -> rbxassetid://N) and downloads each icon through the public thumbnail API
(https://thumbnails.roblox.com/v1/assets, 150x150) into assets/stat_icons/<key>.png.

Icons the API reports as Pending / Unavailable (not rendered yet, or not public) are skipped and listed: they get a plain
single-colour edge in the game until you run this again. Safe to re-run; existing PNGs are kept unless --force.
Usage: python tools/fetch_stat_icons.py [--force]
"""
import json
import os
import re
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, "src", "Shared", "Modules", "Stats", "StatisticsConfig.lua")
OUT = os.path.join(ROOT, "assets", "stat_icons")
API = "https://thumbnails.roblox.com/v1/assets?returnPolicy=PlaceHolder&size=150x150&format=Png&isCircular=false&assetIds="


def read_icons() -> dict:
    ids = {}
    key = None
    for line in open(CONFIG, encoding="utf-8"):
        found = re.search(r'\bkey = "(\w+)"', line)
        if found:
            key = found.group(1)
        icon = re.search(r'\bicon = "rbxassetid://(\d+)"', line)
        if icon and key and key not in ids:
            ids[key] = "rbxassetid://" + icon.group(1)
    return ids


def get(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "fia-tools"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def main():
    force = "--force" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    ids = read_icons()
    with open(os.path.join(OUT, "ids.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(ids, f, indent=1, sort_keys=True)
        f.write("\n")
    todo = {k: v for k, v in ids.items() if force or not os.path.exists(os.path.join(OUT, k + ".png"))}
    by_asset = {}
    for key, content in todo.items():
        by_asset.setdefault(content.split("//")[1], []).append(key)
    got, missing = 0, []
    assets = list(by_asset)
    for i in range(0, len(assets), 50):
        batch = assets[i : i + 50]
        reply = json.loads(get(API + ",".join(batch)))
        for item in reply.get("data", []):
            keys = by_asset.get(str(item["targetId"]), [])
            url = item.get("imageUrl")
            if item.get("state") != "Completed" or not url or "Unavailable" in url:
                missing += keys
                continue
            data = get(url)
            for key in keys:
                with open(os.path.join(OUT, key + ".png"), "wb") as f:
                    f.write(data)
                got += 1
    print(f"{len(ids)} stat icons; downloaded {got}; not available yet: {', '.join(sorted(missing)) or 'none'}")


if __name__ == "__main__":
    main()
