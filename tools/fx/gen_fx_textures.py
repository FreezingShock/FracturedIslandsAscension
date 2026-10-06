#!/usr/bin/env python3
"""Generate the white-on-transparent particle textures used by EnemyConfig (hit / crit / death effects).

  python tools/fx/gen_fx_textures.py            writes assets/fx/*.png

White RGB + alpha only: ParticleEmitter.Color tints them. Upload with the Studio MCP (upload_image), then paste the
ids into EnemyConfig.textures. Needs numpy + pillow. Re-run after tweaking; the output is deterministic (fixed seed).

  fx_streak.png      vertical tapered spark streak (bright core, long soft tail)      256x256
  fx_shard.png       sharp angular sliver                                              256x256
  fx_flare.png       8-point starburst flash (NOT a round blob)                        256x256
  fx_ring.png        crisp thin shockwave ring with a soft outer glow                   512x512
  fx_slash.png       curved crescent slash arc                                         512x256
  fx_dot.png         small soft-edged dot for lingering motes                           64x64
  fx_smoke_4x4.png   4x4 flipbook: a puff that billows and dissolves (16 frames)       1024x1024
  fx_burst_4x4.png   4x4 flipbook: radial impact burst with rays that expands + fades  1024x1024
"""

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

OUT = Path(__file__).resolve().parent.parent.parent / "assets" / "fx"
RNG = np.random.default_rng(7)


def save(alpha: np.ndarray, name: str) -> None:
    a = np.clip(alpha, 0, 1)
    rgba = np.empty(a.shape + (4,), dtype=np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (a * 255).astype(np.uint8)
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba, "RGBA").save(OUT / name)
    print("wrote", OUT / name)


def grid(w: int, h: int):
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    return (x + 0.5) / w * 2 - 1, (y + 0.5) / h * 2 - 1  # -1..1


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def fbm(size: int, octaves: int = 5, seed_shift: int = 0) -> np.ndarray:
    """Tileless fractal noise 0..1 from blurred random fields."""
    total = np.zeros((size, size), np.float32)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        cells = 4 * 2**o
        field = RNG.random((cells, cells)).astype(np.float32)
        img = Image.fromarray((field * 255).astype(np.uint8)).resize((size, size), Image.BICUBIC)
        total += np.asarray(img, np.float32) / 255 * amp
        norm += amp
        amp *= 0.5
    return total / norm


def streak() -> None:
    x, y = grid(256, 256)
    # vertical: thin in x, long in y, brightest at the head (top), thinning to a point at the tail
    length = (y + 1) / 2  # 0 at top .. 1 at bottom
    width = 0.06 + 0.22 * (1 - length) ** 0.6  # wide at the head
    core = np.exp(-((x / np.maximum(width * 0.35, 1e-3)) ** 2))
    glow = np.exp(-((x / np.maximum(width, 1e-3)) ** 2)) * 0.55
    taper = smoothstep(1.0, 0.0, length) ** 1.4
    head = smoothstep(0.0, 0.07, length)
    save((core + glow) * taper * head, "fx_streak.png")


def shard() -> None:
    x, y = grid(256, 256)
    # a long thin kite: pointed at both ends, widest 30% from the top
    t = (y + 1) / 2
    half = np.where(t < 0.3, t / 0.3, (1 - t) / 0.7) * 0.2
    inside = np.abs(x) < half
    edge = smoothstep(0, 0.03, half - np.abs(x))
    shade = 0.75 + 0.25 * np.where(x > 0, 1, 0.55)  # one side brighter = faceted look
    save(np.where(inside & (t > 0.02) & (t < 0.98), edge * shade, 0), "fx_shard.png")


def flare() -> None:
    x, y = grid(256, 256)
    r = np.sqrt(x * x + y * y) + 1e-4
    theta = np.arctan2(y, x)
    core = np.exp(-(r / 0.09) ** 2) * 1.2
    # long horizontal/vertical spikes + shorter diagonals
    spike_h = np.exp(-(y / 0.035) ** 2) * np.exp(-(np.abs(x) / 0.75) ** 1.4)
    spike_v = np.exp(-(x / 0.035) ** 2) * np.exp(-(np.abs(y) / 0.75) ** 1.4)
    d1 = np.exp(-(((x - y) / 1.414) / 0.03) ** 2) * np.exp(-(r / 0.45) ** 1.6)
    d2 = np.exp(-(((x + y) / 1.414) / 0.03) ** 2) * np.exp(-(r / 0.45) ** 1.6)
    halo = np.exp(-(r / 0.22) ** 2) * 0.35
    save(core + spike_h + spike_v + 0.6 * (d1 + d2) + halo, "fx_flare.png")


def ring() -> None:
    x, y = grid(512, 512)
    r = np.sqrt(x * x + y * y)
    ring_r, w = 0.78, 0.028
    crisp = np.exp(-(((r - ring_r) / w) ** 2))
    outer = np.exp(-(np.maximum(r - ring_r, 0) / 0.09) ** 2) * 0.35 * (r > ring_r)
    inner = np.exp(-(np.maximum(ring_r - r, 0) / 0.08) ** 2) * 0.18 * (r < ring_r)  # a faint inner edge only: no filled bubble
    breakup = 0.8 + 0.2 * np.cos(np.arctan2(y, x) * 9)  # a little variation round the circumference
    save((crisp + outer + inner) * breakup * smoothstep(1.0, 0.92, r), "fx_ring.png")


def slash() -> None:
    x, y = grid(512, 256)
    xx, yy = x * 2.0, y  # aspect: the sheet is 2:1
    # a crescent = disc A minus an offset disc B: thick in the middle, pointed tips
    da = np.sqrt(xx**2 + (yy - 0.55) ** 2)
    db = np.sqrt(xx**2 + (yy - 0.95) ** 2)
    ra, rb = 1.45, 1.40
    inside_a = smoothstep(0.0, 0.05, ra - da)
    outside_b = smoothstep(0.0, 0.05, db - rb)
    shape = inside_a * outside_b
    thickness = np.clip(shape, 0, 1)
    # hot, bright inner edge (next to B) fading to the outer edge
    heat = np.clip((db - rb) / 0.25, 0, 1)
    alpha = thickness * (0.45 + 0.75 * np.exp(-heat * 2.2))
    save(alpha * smoothstep(1.0, 0.9, np.abs(x)), "fx_slash.png")


def dot() -> None:
    x, y = grid(64, 64)
    r = np.sqrt(x * x + y * y)
    save(np.exp(-(r / 0.45) ** 2) * smoothstep(1.0, 0.8, r), "fx_dot.png")


def smoke_flipbook() -> None:
    frames, cell = 16, 256
    base = fbm(cell, 6)
    sheet = np.zeros((1024, 1024), np.float32)
    x, y = grid(cell, cell)
    r = np.sqrt(x * x + y * y)
    for i in range(frames):
        t = i / (frames - 1)
        radius = 0.35 + 0.5 * t**0.6
        shape = smoothstep(radius, radius * 0.45, r)
        # the density thins out as it ages: a rising threshold eats the noise
        density = np.clip((base - 0.25 - 0.55 * t) * 3.2, 0, 1)
        alpha = shape * (0.35 + 0.65 * density) * (1 - t) ** 1.3 * 1.4
        sheet[(i // 4) * cell:(i // 4 + 1) * cell, (i % 4) * cell:(i % 4 + 1) * cell] = alpha
    save(sheet, "fx_smoke_4x4.png")


def burst_flipbook() -> None:
    frames, cell = 16, 256
    x, y = grid(cell, cell)
    r = np.sqrt(x * x + y * y) + 1e-4
    theta = np.arctan2(y, x)
    # a star of tapered rays: ray k points at angle phi_k, reaches length L_k, and is `width` radians wide at the base
    rays = 11
    phi = (np.arange(rays) + RNG.uniform(-0.3, 0.3, rays)) / rays * 2 * math.pi
    reach = RNG.uniform(0.55, 1.0, rays)
    width = 0.34
    spike = np.zeros_like(theta)
    for k in range(rays):
        d = np.abs((theta - phi[k] + math.pi) % (2 * math.pi) - math.pi)
        spike = np.maximum(spike, reach[k] * np.clip(1 - d / width, 0, 1) ** 1.3)
    noise = fbm(cell, 4)
    sheet = np.zeros((1024, 1024), np.float32)
    for i in range(frames):
        t = i / (frames - 1)
        grow = 1 - (1 - t) ** 2.4
        edge = (0.12 + 0.84 * grow) * (0.22 + 0.78 * spike)  # per-angle reach of the star
        body = smoothstep(edge, edge * 0.2, r)  # filled star, soft toward the tips
        rim = np.exp(-(((r - edge * 0.92) / 0.05) ** 2)) * 0.8  # bright crisp outline
        core = np.exp(-(r / (0.20 * (1 - t) + 0.03)) ** 2) * 1.4
        alpha = (body * (0.55 + 0.45 * noise) + rim * 0.5 + core) * (1 - t) ** 1.25
        sheet[(i // 4) * cell:(i // 4 + 1) * cell, (i % 4) * cell:(i % 4 + 1) * cell] = alpha * smoothstep(1.0, 0.85, r)
    save(sheet, "fx_burst_4x4.png")


if __name__ == "__main__":
    streak()
    shard()
    flare()
    ring()
    slash()
    dot()
    smoke_flipbook()
    burst_flipbook()
