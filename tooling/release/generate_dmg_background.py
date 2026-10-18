#!/usr/bin/env python3
"""Flowline DMG background — Brand Guidelines §06.

Spec (brand/index.html):
  540 x 400 pt, @2x 1080 x 800 PNG
  ground: FLAT warm canvas #F7F7F5 — no photograph, no gradient.
  ornament: the logomark itself only — 70cqw watermark at 5% ink,
    bleeding off the lower-left corner.
  layout: flex column — brandline / drag row / instruction (never collide).
  drag: app left (ink squircle, 25cqw, one soft shadow), dashed arrow
    (1.75pt, 50% ink — invitation, not alarm), Applications right.
  instruction: "Drag Flowline to Applications" (ink at 55%).
  ink #1D1D1F text on canvas #F7F7F5. No glass, no glow, no blue wash.

Finder slots (create_dmg.sh): app at (150,210), Applications at (390,210),
icon size 120 in a 540x400 window. The drawn app squircle and folder sit
at the same centers so the real Finder icons land exactly on the art.
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS_DIR = os.path.join(REPO_ROOT, "platform", "macos", "Assets", "dmg")

INK = (29, 29, 31)
CANVAS = (247, 247, 245)

W2, H2 = 1080, 800  # @2x pixels (540x400 pt)
CQW = W2 / 100.0  # container-query unit: 1% of banner width


def load_font(size, bold=False):
    cands = [
        "/System/Library/Fonts/SFNSDisplay-Semibold.otf" if bold else "/System/Library/Fonts/SFNSDisplay.otf",
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/System/Library/Fonts/Helvetica.ttc",
    ]
    for p in cands:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                continue
    return ImageFont.load_default()


def draw_mark(draw, cx, cy, s, color, width):
    """Logomark M4 18h5v-5h6V8h5 mapped from 24-grid to size s, centered at cx,cy."""
    def pt(x, y):
        return (cx + (x - 12) * s / 24.0, cy + (y - 12) * s / 24.0)
    pts = [pt(4, 18), pt(9, 18), pt(9, 13), pt(15, 13), pt(15, 8), pt(20, 8)]
    draw.line(pts, fill=color, width=width, joint="curve")


def draw_folder(draw, cx, cy, s, fill, outline, width):
    """Brand folder-solid: 12% fill + ink outline, 24-grid to size s."""
    u = s / 24.0

    def pt(x, y):
        return (cx + (x - 12) * u, cy + (y - 12) * u)

    # Tab (filled): (5.5,5) -> (9.1,5) -> (11.2,7.6) -> (5.5,7.6).
    draw.polygon([pt(5.5, 5), pt(9.1, 5), pt(11.2, 7.6), pt(5.5, 7.6)], fill=fill)
    # Body (filled rounded rect): x 3.5..20.5, y 7.6..20.5, corner r2 units.
    draw.rounded_rectangle(
        [pt(3.5, 7.6)[0], pt(3.5, 7.6)[1], pt(20.5, 20.5)[0], pt(20.5, 20.5)[1]],
        radius=int(2 * u), fill=fill)
    # Outline: tab peak + slant + body, round joins (bookmark fold omitted —
    # the real Finder symlink icon covers the interior).
    draw.line([pt(5.5, 5), pt(9.1, 5), pt(11.2, 7.6)], fill=outline, width=width, joint="curve")
    draw.rounded_rectangle(
        [pt(3.5, 7.6)[0], pt(3.5, 7.6)[1], pt(20.5, 20.5)[0], pt(20.5, 20.5)[1]],
        radius=int(2 * u), outline=outline, width=width)


def main():
    base = Image.new("RGBA", (W2, H2), CANVAS + (255,))
    gfx = Image.new("RGBA", (W2, H2), (0, 0, 0, 0))
    d = ImageDraw.Draw(gfx)

    # Ghost watermark: 70cqw mark at 5% ink, bleeding off the lower-left.
    ghost_s = 70 * CQW
    draw_mark(d, -19 * CQW + ghost_s / 2, H2 + 17 * CQW - ghost_s / 2,
              ghost_s, INK + (13,), max(1, round(2.25 * ghost_s / 24.0)))

    # Finder slot centers (@2x px). pt (150,210)/(390,210) -> px (*2).
    left_x, right_x, icon_y = 300, 780, 420

    # App hero: 25cqw ink squircle (22.4%), white mark at 14cqw,
    # one soft shadow — the real Finder icon lands on this exact spot.
    app_s = 25 * CQW
    app_r = int(app_s * 0.224)
    sh = Image.new("RGBA", (W2, H2), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        [left_x - app_s / 2, icon_y - app_s / 2 + 8,
         left_x + app_s / 2, icon_y + app_s / 2 + 8],
        radius=app_r, fill=(29, 29, 31, 36))
    sh = sh.filter(ImageFilter.GaussianBlur(18))
    base = Image.alpha_composite(base, sh)
    d.rounded_rectangle(
        [left_x - app_s / 2, icon_y - app_s / 2,
         left_x + app_s / 2, icon_y + app_s / 2],
        radius=app_r, fill=INK + (255,))
    mark_s = 14 * CQW
    draw_mark(d, left_x, icon_y, mark_s, (255, 255, 255, 255),
              max(1, round(2.25 * mark_s / 24.0)))

    # Folder placeholder: 20cqw folder-solid (12% fill), label beneath.
    fld_s = 20 * CQW
    draw_folder(d, right_x, icon_y, fld_s,
                INK + (31,), INK + (230,), max(1, round(1.6 * fld_s / 24.0)))
    f_label = load_font(32)
    lbl = "Applications"
    bb = d.textbbox((0, 0), lbl, font=f_label)
    d.text((right_x - (bb[2] - bb[0]) // 2, icon_y + fld_s / 2 + 20),
           lbl, font=f_label, fill=INK + (204,))

    # Dashed arrow between the wells (1.75pt -> ~4px @2x, 50% ink).
    ay = icon_y
    x0, x1 = left_x + app_s / 2 + 20, right_x - fld_s / 2 - 30
    dash, gap = 12, 10
    x = x0
    while x < x1:
        d.line([(x, ay), (min(x + dash, x1), ay)], fill=INK + (128,), width=4)
        x += dash + gap
    tip_x = x1 + 26
    d.line([(tip_x, ay), (x1, ay - 14)], fill=INK + (128,), width=4, joint="curve")
    d.line([(tip_x, ay), (x1, ay + 14)], fill=INK + (128,), width=4, joint="curve")

    # Brandline top-center: mark (6.5cqw) + "Flowline" (4.8cqw semibold).
    brand_y = 150
    mark_b = 6.5 * CQW
    f_brand = load_font(56, bold=True)
    wb = d.textbbox((0, 0), "Flowline", font=f_brand)
    text_w = wb[2] - wb[0]
    gap_b = 2.4 * CQW
    group_w = mark_b + gap_b + text_w
    gx = W2 // 2 - group_w / 2
    draw_mark(d, gx + mark_b / 2, brand_y, mark_b, INK + (255,),
              max(1, round(2.25 * mark_b / 24.0)))
    d.text((gx + mark_b + gap_b, brand_y - (wb[3] - wb[1]) / 2 - wb[1]),
           "Flowline", font=f_brand, fill=INK + (255,))

    # Instruction bottom-center (ink at 55%).
    f_inst = load_font(37)
    inst = "Drag Flowline to Applications"
    ib = d.textbbox((0, 0), inst, font=f_inst)
    d.text((W2 // 2 - (ib[2] - ib[0]) // 2, 656), inst, font=f_inst, fill=INK + (140,))

    base = Image.alpha_composite(base, gfx)
    os.makedirs(ASSETS_DIR, exist_ok=True)
    rgb = Image.new("RGB", (W2, H2), CANVAS)
    rgb.paste(base, (0, 0), base)
    rgb.save(os.path.join(ASSETS_DIR, "background@2x.png"), "PNG", optimize=True)
    rgb.resize((540, 400), Image.LANCZOS).save(os.path.join(ASSETS_DIR, "background.png"), "PNG", optimize=True)
    print(f"✅ Flowline DMG background 540x400 @2x at {ASSETS_DIR}")


if __name__ == "__main__":
    main()
