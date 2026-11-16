#!/usr/bin/env python3
"""Makes the boot splash image of the lunar Plymouth theme from the default
wallpaper (branding/20-wordmark-lockup.png).

Plymouth's two-step theme can't scale a full-screen picture to the screen,
it draws images 1:1 on a plain background. So the splash is the middle of
the wallpaper (moon, "Lunar", the glow and rings around them), faded at its
edges into the wallpaper's own background colour, and the theme fills the
screen with that colour (BackgroundStartColor/EndColor in lunar.plymouth).
That looks like the wallpaper on every screen size.

    python3 make-splash.py [wallpaper.png]     writes watermark.png here

Prints the background colour; lunar.plymouth must use the same.
Needs python-pillow.
"""
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

here = os.path.dirname(os.path.abspath(__file__))
src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "../../branding/20-wordmark-lockup.png")

# Part of the wallpaper around the lockup (fractions of its size). The
# lockup's centre is left of the wallpaper's centre.
CENTER_X, CENTER_Y = 0.462, 0.50
CROP_W, CROP_H = 0.92, 0.86
# Width of the result: on a 1920 px wide screen the lockup is then about
# 600 px wide, a bit smaller than on the desktop.
OUT_W = 1180
# Where the fade into the background starts (fraction of the half size)
FADE_FROM = 0.62

wall = Image.open(src).convert("RGB")
W, H = wall.size

# Background colour: the wallpaper's colour along the edge of the crop,
# without the stars (median of a blurred ring around the crop)
cw, ch = int(W * CROP_W), int(H * CROP_H)
left, top = int(W * CENTER_X - cw / 2), int(H * CENTER_Y - ch / 2)
crop = wall.crop((left, top, left + cw, top + ch))
small = crop.resize((cw // 16, ch // 16), Image.BOX).filter(ImageFilter.MedianFilter(7))
sw, sh = small.size
ring = [small.getpixel((x, y)) for x in range(sw) for y in range(sh)
        if min(x, y, sw - 1 - x, sh - 1 - y) < 3]
bg = tuple(sorted(p[i] for p in ring)[len(ring) // 2] for i in range(3))

# Scale down, then fade the edges into the background: an elliptical mask,
# opaque in the middle and transparent at the border
out_h = round(OUT_W * ch / cw)
img = crop.resize((OUT_W, out_h), Image.LANCZOS)

mask = Image.new("L", (OUT_W, out_h), 0)
steps = 64
draw = ImageDraw.Draw(mask)
for i in range(steps):
    # from the border (i = 0, transparent) to FADE_FROM (opaque)
    f = 1 - (1 - FADE_FROM) * i / steps
    a = round(255 * (i / steps) ** 1.6)
    dx, dy = OUT_W * (1 - f) / 2, out_h * (1 - f) / 2
    draw.ellipse((dx, dy, OUT_W - dx, out_h - dy), fill=a)
dx, dy = OUT_W * (1 - FADE_FROM) / 2, out_h * (1 - FADE_FROM) / 2
draw.ellipse((dx, dy, OUT_W - dx, out_h - dy), fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(OUT_W / 60))

# Blend towards the background colour where the mask is low, so that even
# a renderer that ignores alpha shows no hard edge
flat = Image.new("RGB", img.size, bg)
img = Image.composite(img, flat, mask)
img.putalpha(mask)
img = img.convert("RGBA")

# Sanity: the corners must be (almost) the background colour
for corner in [(0, 0), (OUT_W - 1, 0), (0, out_h - 1), (OUT_W - 1, out_h - 1)]:
    r, g, b, a = img.getpixel(corner)
    assert a < 8, f"corner {corner} not transparent (alpha {a})"

out = os.path.join(here, "watermark.png")
img.save(out, optimize=True)
print(f"{out}: {OUT_W}x{out_h}, background 0x{bg[0]:02x}{bg[1]:02x}{bg[2]:02x}")
