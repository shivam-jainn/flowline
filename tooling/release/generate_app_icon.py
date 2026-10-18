#!/usr/bin/env python3
"""Flowline AppIcon — Brand Guidelines §05.

  macOS squircle, 22.4% corner radius (OS-applied — masters stay square).
  mark centered at 56% of canvas, stroke 2.25, round caps.
  light: canvas #F7F7F5 + hairline #E5E5E2, mark ink #1D1D1F.
  dark:  ink #1D1D1F, mark white.
  1024 master, no pre-applied mask.
"""
import os
import subprocess
from PIL import Image, ImageDraw

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS_DIR = os.path.join(REPO_ROOT, "platform", "macos", "Assets")
ICONSET_DIR = os.path.join(ASSETS_DIR, "AppIcon.iconset")

CANVAS = (247, 247, 245)
INK = (29, 29, 31)
EDGE = (229, 229, 226)
SIZE = 1024


def draw_mark(d, size, color, width):
    def pt(x, y):
        return ((x - 12) * size / 24.0, (y - 12) * size / 24.0)
    # center at canvas middle: offset by SIZE/2
    cx = cy = SIZE / 2
    pts = [pt(4, 18), pt(9, 18), pt(9, 13), pt(15, 13), pt(15, 8), pt(20, 8)]
    pts = [(cx + x, cy + y) for x, y in pts]
    d.line(pts, fill=color, width=width, joint="curve")


def render(bg, mark, edge=False):
    im = Image.new("RGBA", (SIZE, SIZE), bg + (255,))
    d = ImageDraw.Draw(im)
    if edge:
        d.rectangle([1, 1, SIZE - 2, SIZE - 2], outline=EDGE + (255,), width=2)
    mark_px = int(SIZE * 0.56)
    stroke_px = max(1, int(round(2.25 * mark_px / 24.0)))
    draw_mark(d, mark_px, mark + (255,), stroke_px)
    return im


def main():
    os.makedirs(ASSETS_DIR, exist_ok=True)
    os.makedirs(ICONSET_DIR, exist_ok=True)
    light = render(CANVAS, INK, edge=True)
    light_path = os.path.join(ASSETS_DIR, "AppIcon-1024.png")
    # Flatten to RGBA square master (no corner mask — OS applies the squircle).
    light.save(light_path, "PNG", optimize=True)
    dark = render(INK, (255, 255, 255))
    dark.save(os.path.join(ASSETS_DIR, "AppIcon-dark-1024.png"), "PNG", optimize=True)

    # iconset: macOS expects 10 files (16..512 + @2x).
    specs = [(16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
             (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
             (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
             (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
             (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")]
    for px, name in specs:
        im = light.resize((px, px), Image.LANCZOS)
        im.save(os.path.join(ICONSET_DIR, name), "PNG", optimize=True)

    icns = os.path.join(ASSETS_DIR, "AppIcon.icns")
    try:
        subprocess.run(["iconutil", "-c", "icns", ICONSET_DIR, "-o", icns],
                       check=True, capture_output=True, text=True)
        print(f"✅ AppIcon.icns rebuilt from Flowline mark")
    except Exception as e:
        print(f"⚠️ iconutil skipped ({e}); iconset PNGs updated, run iconutil on macOS to rebuild .icns")
    print(f"✅ Flowline AppIcon light master at {light_path} (+ dark variant)")


if __name__ == "__main__":
    main()
