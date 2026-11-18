#!/usr/bin/env python3
"""Draws Daniel's bandage (assets/models/daniel_bandage.png): cream cotton gauze
wound in a spiral, soaked through with blood on the palm side and a smaller stain on
the back of the hand. U runs around the wrap (0.25 = palm side, 0.75 = back of the
hand), V runs along it (0 = wrist, 1 = knuckles).

Run:  python3 tools/make_bandage_texture.py     (needs numpy and Pillow)
"""
import os

import numpy as np
from PIL import Image, ImageFilter

W, H = 512, 256
rng = np.random.default_rng(7)
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models", "daniel_bandage.png")

u = np.linspace(0, 1, W)[None, :].repeat(H, 0)
v = np.linspace(0, 1, H)[:, None].repeat(W, 1)

# Cotton gauze: fine woven threads plus mottling.
threads = 0.5 + 0.5 * np.sin(u * W * 0.9) * np.sin(v * H * 0.9)
mottle = np.array(Image.fromarray((rng.random((32, 64)) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)) / 255.0
base = np.array([0.80, 0.77, 0.70])
img = base[None, None, :] * (0.90 + 0.06 * threads + 0.08 * mottle)[..., None]

# Spiral wrapping: diagonal bands with a shaded and a lit edge.
phase = (u * 3.0 + v * 5.0) % 1.0
band = np.where(phase < 0.08, 0.80, 1.0) * (1.0 - 0.10 * np.clip((phase - 0.80) / 0.20, 0, 1))
img *= band[..., None]

# Dirt at the wrist end and grubby fingertip side.
img *= (1.0 - 0.18 * np.clip(1.0 - v / 0.18, 0, 1))[..., None]


def blob(cu, cv, ru, rv, strength, seed):
    r = np.random.default_rng(seed)
    du = np.minimum(np.abs(u - cu), 1 - np.abs(u - cu)) / ru
    dv = (v - cv) / rv
    d = np.sqrt(du ** 2 + dv ** 2)
    noise = np.array(Image.fromarray((r.random((16, 32)) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)) / 255.0
    edge = d + (noise - 0.5) * 0.7
    return np.clip(1.0 - edge, 0, 1) ** 0.6 * strength


# Blood: a big soaked patch on the palm side, a smaller one on the back, drips toward the fingers.
stain = blob(0.25, 0.55, 0.20, 0.34, 1.0, 1) + blob(0.75, 0.62, 0.10, 0.18, 0.8, 2) + blob(0.34, 0.25, 0.05, 0.12, 0.7, 3)
for cu in (0.20, 0.27, 0.33, 0.72):
    length = rng.uniform(0.15, 0.3)
    drip = np.clip(1 - np.abs(u - cu) / 0.012, 0, 1) * np.clip(1 - np.abs(v - (0.7 + length * 0.5)) / (length * 0.5 + 0.001), 0, 1)
    stain += drip * 0.9
stain = np.clip(stain, 0, 1)
fresh = np.array([0.46, 0.03, 0.04])   # dark wet red in the middle
old = np.array([0.55, 0.20, 0.12])     # brown at the dried edge
tone = np.clip(stain * 1.6 - 0.2, 0, 1)[..., None]
blood = old[None, None, :] * (1 - tone) + fresh[None, None, :] * tone
img = img * (1 - stain[..., None]) + blood * stain[..., None]

im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))
im.save(out)
print("wrote", os.path.normpath(out))
