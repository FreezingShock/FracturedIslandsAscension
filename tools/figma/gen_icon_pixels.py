#!/usr/bin/env python3
"""Pixel dumps of the game icons for the Figma master file (tools/figma/README.md).

Writes tools/figma/icon_pixels.json: { "items": [...], "stats": [...], "tags": [...] } with one entry per icon:
    [key, n, [palette hex...], [row strings...]]   n = art pixels per side (16 for items / stats, 9 for tag icons); '.' = transparent,
    any other character is an index into the palette (0-9a-zA-Z). Run tools/fetch_stat_icons.py first for the stat icons.
The Figma side (use_figma) turns every horizontal run of one colour into a rectangle, so the icons stay editable pixel art.
"""
import glob
import json
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CHARS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"


def dump(path: str, n: int):
    im = Image.open(path).convert("RGBA")
    w = im.size[0]
    px = im.load()
    pal, rows = [], []
    for y in range(n):
        row = ""
        for x in range(n):
            r, g, b, a = px[min(w - 1, int((x + 0.5) * w / n)), min(w - 1, int((y + 0.5) * w / n))]
            if a < 128:
                row += "."
                continue
            hexv = "%02x%02x%02x" % (r, g, b)
            if hexv not in pal:
                pal.append(hexv)
            row += CHARS[pal.index(hexv)]
        rows.append(row)
    return pal, rows


def main():
    out = {"items": [], "stats": [], "tags": []}
    for key, folder, n in (("items", "assets/icons", 16), ("stats", "assets/stat_icons", 16), ("tags", "assets/tag_icons", 9)):
        for f in sorted(glob.glob(os.path.join(ROOT, folder, "*.png"))):
            name = os.path.basename(f)[:-4]
            pal, rows = dump(f, n)
            out[key].append([name, n, pal, rows])
    with open(os.path.join(ROOT, "tools", "figma", "icon_pixels.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, separators=(",", ":"))
    print({k: len(v) for k, v in out.items()})


if __name__ == "__main__":
    main()
