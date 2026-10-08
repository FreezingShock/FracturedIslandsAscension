#!/usr/bin/env python3
"""Draw the nameplate tag icons (9x9 pixel art, same as the Figma board tools/figma/enemy_nameplate_tagrow_v*.png).

  python tools/gen_tag_icons.py              writes assets/tag_icons/<tag id>.png (36x36, nearest-neighbour from 9x9)
  python tools/gen_tag_icons.py --lua        prints the `icon = ...` lines for NameplateConfig.tags from assets/tag_icons/ids.json

Adding a tag icon: add its 9x9 map below (key = NameplateConfig.tags id), run this, serve assets/tag_icons over http, call the
Studio MCP `upload_image`, put the returned ids in assets/tag_icons/ids.json ({"fire": "rbxassetid://..."}), then paste the
`--lua` output / set tags.<id>.icon in Modules/Config/NameplateConfig.lua.
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "tag_icons")
SCALE = 4

# '.' = transparent; letters index the palette
ICONS = {
    "fire": ({"o": "#5A1A00", "a": "#FF5A1F", "b": "#FFD23F"},
             ["....o....", "...oao...", "...oaao..", "..oaabao.", ".oaabbbao", ".oaabbbao", ".oaaabaao", "..oaaaao.", "...oooo.."]),
    "ice": ({"a": "#7FE3FF", "b": "#FFFFFF"},
            ["....a....", ".a..a..a.", "..a.a.a..", "...aaa...", "aaaabaaaa", "...aaa...", "..a.a.a..", ".a..a..a.", "....a...."]),
    "earth": ({"o": "#4A3318", "a": "#A7824F", "b": "#D9B77F"},
              [".........", "....o....", "...oao...", "..oabao..", ".oabaaao.", "oabaaoaao", "oaaaaaaao", "ooooooooo", "........."]),
    "storm": ({"o": "#4B2A7A", "a": "#E6D2FF"},
              ["....oooo.", "...oaaao.", "..oaaao..", ".oaaaaoo.", "..ooaaao.", "....oaao.", "...oaao..", "..oaoo...", "..oo....."]),
    "nature": ({"o": "#14461A", "a": "#3FBF4A", "b": "#8DF07A"},
               ["......ooo", "....ooaao", "..ooaabao", ".oaabbbao", ".oaabbaoo", "oaabaaoo.", "oabaoo...", "obo......", "o........"]),
    "power": ({"o": "#2B2F38", "b": "#E8EEF5", "a": "#C98A3D", "c": "#7A4B1F"},
              ["......ooo", ".....obbo", "....obbo.", "...obbo..", "o.obbo...", "oobbo....", ".oao.....", "oaco.....", ".oo......"]),
    "shield": ({"o": "#20242C", "a": "#8A94A6", "b": "#C9D1DE", "c": "#E8EEF5"},
               [".ooooooo.", "oabbbbbao", "oabbbbbao", "oabbcbbao", "oabbcbbao", ".oabcbao.", "..oabao..", "...oao...", "....o...."]),
    "empower": ({"a": "#FFD24A", "b": "#FFFFFF"},
                ["....a....", "....a....", "...aba...", "..aabaa..", "aabbbbbaa", "..aabaa..", "...aba...", "....a....", "....a...."]),
    "regen": ({"o": "#5A0F2A", "a": "#55FF99", "b": "#CFFFE3"},
              [".oo...oo.", "oaaoooaao", "oabaaaaao", "oabaaaaao", "oaaaaaaao", ".oaaaaao.", "..oaaao..", "...oao...", "....o...."]),
    "enrage": ({"o": "#5A0F1F", "a": "#FF4C6A", "b": "#FFB3C0"},
               ["....o....", "...oao...", "..oaaao..", ".oaaaaao.", "oooaaaooo", "...oao...", "...oao...", "...oao...", "...ooo..."]),
    "poison": ({"o": "#14461A", "a": "#6BDB4A", "b": "#D2FFB8"},
               ["....o....", "...oao...", "..oabao..", "..oaaao..", ".oaabaao.", ".oaaaaao.", ".oaaaaao.", "..oaaao..", "...ooo..."]),
    "bleed": ({"o": "#4A0A14", "a": "#E0243F", "b": "#FF9AA8"},
              ["....o....", "...oao...", "..oabao..", "..oaaao..", ".oaabaao.", ".oaaaaao.", ".oaaaaao.", "..oaaao..", "...ooo..."]),
    "slow": ({"o": "#1D2D5A", "a": "#8FB4FF", "b": "#E0ECFF"},
             [".ooooooo.", ".obbbbbo.", "..obbbo..", "...obo...", "....o....", "...oao...", "..oaaao..", ".oaaaaao.", ".ooooooo."]),
    "burn": ({"o": "#5A1A00", "a": "#FF3B1F", "b": "#FFB347"},
             ["....o....", "...oao...", "...oaao..", "..oaabao.", ".oaabbbao", ".oaabbbao", ".oaaabaao", "..oaaaao.", "...oooo.."]),
}


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def main():
    if "--lua" in sys.argv:
        ids = json.load(open(os.path.join(OUT, "ids.json"), encoding="utf-8"))
        for key in ICONS:
            print(f'{key}: icon = "{ids.get(key, "")}"')
        return
    os.makedirs(OUT, exist_ok=True)
    for key, (palette, rows) in ICONS.items():
        img = Image.new("RGBA", (9, 9), (0, 0, 0, 0))
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch != ".":
                    img.putpixel((x, y), rgb(palette[ch]) + (255,))
        img.resize((9 * SCALE, 9 * SCALE), Image.NEAREST).save(os.path.join(OUT, key + ".png"))
    print(f"wrote {len(ICONS)} icons to {OUT}")


main()
