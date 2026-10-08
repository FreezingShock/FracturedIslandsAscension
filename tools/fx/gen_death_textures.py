#!/usr/bin/env python3
"""Textures for the death burst (DeathConfig.textures; Modules/Config/DeathConfig.lua).

  python tools/fx/gen_death_textures.py     writes assets/death_fx/death_triangles.png and death_glow.png

death_triangles.png  256x256, a 2x2 flipbook sheet of four crisp white triangles (equilateral, right, obtuse, thin) with a soft
                     white halo, so one ParticleEmitter (FlipbookLayout Grid2x2, mode Random) shows differing shapes. White so
                     the emitter's ColorSequence tints them (white-cyan -> aqua -> green).
death_glow.png       128x128 soft radial glow disc.
Upload both (serve assets/death_fx over http, Studio MCP `upload_image`) and paste the ids into DeathConfig.textures.
"""
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "death_fx")
CELL = 128
SS = 4  # supersampling for crisp edges

TRIANGLES = [
    [(0.50, 0.12), (0.88, 0.78), (0.12, 0.78)],  # equilateral-ish
    [(0.18, 0.18), (0.86, 0.80), (0.18, 0.80)],  # right triangle
    [(0.10, 0.62), (0.90, 0.40), (0.52, 0.86)],  # obtuse, tilted
    [(0.50, 0.04), (0.60, 0.96), (0.40, 0.96)],  # thin shard
]


def triangle_cell(points):
    size = CELL * SS
    core = Image.new("L", (size, size), 0)
    ImageDraw.Draw(core).polygon([(x * size, y * size) for x, y in points], fill=255)
    core = core.resize((CELL, CELL), Image.LANCZOS)
    halo = core.filter(ImageFilter.GaussianBlur(7)).point(lambda v: int(v * 0.55))
    # the core stays solid, the halo fills around it
    merged = Image.new("L", (CELL, CELL), 0)
    merged.paste(halo, (0, 0))
    merged.paste(core, (0, 0), core)
    img = Image.new("RGBA", (CELL, CELL), (255, 255, 255, 0))
    img.putalpha(merged)
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    sheet = Image.new("RGBA", (CELL * 2, CELL * 2), (255, 255, 255, 0))
    for i, points in enumerate(TRIANGLES):
        sheet.paste(triangle_cell(points), ((i % 2) * CELL, (i // 2) * CELL))
    sheet.save(os.path.join(OUT, "death_triangles.png"))

    glow = Image.new("RGBA", (CELL, CELL), (255, 255, 255, 0))
    alpha = Image.new("L", (CELL, CELL), 0)
    for y in range(CELL):
        for x in range(CELL):
            d = ((x - CELL / 2) ** 2 + (y - CELL / 2) ** 2) ** 0.5 / (CELL / 2)
            alpha.putpixel((x, y), int(max(0.0, 1 - d) ** 2.2 * 255))
    glow.putalpha(alpha)
    glow.save(os.path.join(OUT, "death_glow.png"))
    print("wrote", OUT)


main()
