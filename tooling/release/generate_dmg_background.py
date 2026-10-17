#!/usr/bin/env python3
import os
import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

# Resolve paths relative to the repository root so the script works from any CWD.
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS_DIR = os.path.join(REPO_ROOT, "Assets", "dmg")

def create_fun_apple_dmg_background():
    # Window dimensions in create_dmg.sh: 660 x 440 pt -> 1320 x 880 px (@2x Retina)
    W, H = 1320, 880
    
    # 1. Base Canvas: Ultra-refined Apple Space Titanium Gradient
    # Smooth subtle vertical gradient from #18181b (top) to #0f0f11 (bottom)
    base = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bdraw = ImageDraw.Draw(base)
    
    for y in range(H):
        t = y / float(H)
        r = int(24 * (1 - t) + 14 * t)
        g = int(24 * (1 - t) + 14 * t)
        b = int(27 * (1 - t) + 17 * t)
        bdraw.line([(0, y), (W, y)], fill=(r, g, b, 255))
        
    # 2. Studio Spotlight (gentle ambient light centered on the action area)
    spotlight = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(spotlight)
    cx, cy = 660, 440
    max_r = 540
    for r in range(max_r, 0, -10):
        alpha = int(18 * (1.0 - (r / max_r) ** 1.6))
        sdraw.ellipse([cx - r, cy - int(r * 0.72), cx + r, cy + int(r * 0.72)], fill=(255, 255, 255, alpha))
    spotlight = spotlight.filter(ImageFilter.GaussianBlur(36))
    base = Image.alpha_composite(base, spotlight)
    
    # 3. Typography setup (macOS SF Pro or Helvetica Neue)
    font_sf = "/System/Library/Fonts/SFNS.ttf"
    if not os.path.exists(font_sf):
        font_sf = "/System/Library/Fonts/HelveticaNeue.ttc"
        
    logo_font = ImageFont.truetype(font_sf, 54)
    subtitle_font = ImageFont.truetype(font_sf, 20)
    tag_font = ImageFont.truetype(font_sf, 18)
    prompt_font = ImageFont.truetype(font_sf, 18)
    footer_font = ImageFont.truetype(font_sf, 15)
    
    gfx = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(gfx)
    
    # 4. Icon Coordinates:
    # StepIt.app at (180, 220) pt -> (360, 440) px
    # Applications at (480, 220) pt -> (960, 440) px
    left_x, right_x = 360, 960
    icon_y = 440
    ped_w, ped_h = 208, 208
    ped_radius = 44
    
    # Tactile Pedestals with whisper-thin hairlines & soft shadows
    for px in [left_x, right_x]:
        # Soft ambient shadow
        shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        sh_draw = ImageDraw.Draw(shadow)
        sh_draw.rounded_rectangle(
            [px - ped_w//2, icon_y - ped_h//2 + 6, px + ped_w//2, icon_y + ped_h//2 + 6],
            radius=ped_radius,
            fill=(0, 0, 0, 45)
        )
        shadow = shadow.filter(ImageFilter.GaussianBlur(14))
        base = Image.alpha_composite(base, shadow)
        
        # Glassmorphic drop plate
        draw.rounded_rectangle(
            [px - ped_w//2, icon_y - ped_h//2, px + ped_w//2, icon_y + ped_h//2],
            radius=ped_radius,
            fill=(255, 255, 255, 9),
            outline=(255, 255, 255, 26),
            width=1
        )
        
    # Playful Step Pedestal Annotations:
    # "Step 1: Drag me" under left pedestal, "Step 2: Drop to install" under right pedestal
    p1_text = "Step 1: Drag me"
    p1_box = tag_font.getbbox(p1_text)
    p1_w = p1_box[2] - p1_box[0]
    draw.text((left_x - p1_w // 2, icon_y + ped_h // 2 + 18), p1_text, font=tag_font, fill=(160, 160, 170, 220))
    
    p2_text = "Step 2: Drop to install"
    p2_box = tag_font.getbbox(p2_text)
    p2_w = p2_box[2] - p2_box[0]
    draw.text((right_x - p2_w // 2, icon_y + ped_h // 2 + 18), p2_text, font=tag_font, fill=(41, 151, 255, 240))
    
    # 5. Playful Stepped Trajectory connecting Left to Right
    start_x = left_x + ped_w // 2 + 24   # 360 + 104 + 24 = 488
    end_x = right_x - ped_w // 2 - 24    # 960 - 104 - 24 = 832
    trail_y = icon_y
    
    prompt_text = "Drag to Applications"
    pbbox = prompt_font.getbbox(prompt_text)
    pw = pbbox[2] - pbbox[0]
    ph = pbbox[3] - pbbox[1]
    
    # Pill in the center of the trail
    pill_w = pw + 34
    pill_h = ph + 16
    pill_x1 = 660 - pill_w // 2
    pill_y1 = trail_y - pill_h // 2
    pill_x2 = 660 + pill_w // 2
    pill_y2 = trail_y + pill_h // 2
    
    # Draw dashed lines on left and right of the central pill
    dash_len = 8
    gap_len = 7
    line_col = (255, 255, 255, 50)
    
    # Left segment: start_x to pill_x1 - 14
    curr_x = start_x
    while curr_x < pill_x1 - 14:
        next_x = min(curr_x + dash_len, pill_x1 - 14)
        draw.line([(curr_x, trail_y), (next_x, trail_y)], fill=line_col, width=2)
        curr_x += dash_len + gap_len
        
    # Right segment: pill_x2 + 14 to end_x - 16
    curr_x = pill_x2 + 14
    while curr_x < end_x - 16:
        next_x = min(curr_x + dash_len, end_x - 16)
        draw.line([(curr_x, trail_y), (next_x, trail_y)], fill=line_col, width=2)
        curr_x += dash_len + gap_len
        
    # Sleek Arrowhead at end_x
    arr_poly = [(end_x, trail_y), (end_x - 12, trail_y - 6), (end_x - 12, trail_y + 6)]
    draw.polygon(arr_poly, fill=(41, 151, 255, 220))
    
    # Frosted Center Pill
    draw.rounded_rectangle([pill_x1, pill_y1, pill_x2, pill_y2], radius=14, fill=(26, 26, 29, 230), outline=(255, 255, 255, 30), width=1)
    draw.text((660 - pw // 2, trail_y - ph // 2 - 2), prompt_text, font=prompt_font, fill=(235, 235, 240, 240))
    
    # 6. Fun Typography Logo Header - Perfectly Centered
    word_text = "step·it"
    wbbox = logo_font.getbbox(word_text)
    ww = wbbox[2] - wbbox[0]
    wh = wbbox[3] - wbbox[1]
    
    # Logomark width: 3 pills (each 12px wide with 8px gap) + dot (10px) + gap
    # Pill 1: x0 to x0+12
    # Pill 2: x0+18 to x0+30
    # Pill 3: x0+36 to x0+48
    # Blue Dot: x0+58 to x0+68
    glyph_w = 70
    gap_logo = 18
    total_logo_w = glyph_w + gap_logo + ww
    
    logo_start_x = 660 - total_logo_w // 2
    logo_base_y = 150
    
    # Pill 1 (Low)
    draw.rounded_rectangle([logo_start_x, logo_base_y - 24, logo_start_x + 12, logo_base_y], radius=6, fill=(255, 255, 255, 95))
    # Pill 2 (Mid)
    draw.rounded_rectangle([logo_start_x + 18, logo_base_y - 38, logo_start_x + 30, logo_base_y], radius=6, fill=(255, 255, 255, 175))
    # Pill 3 (High)
    draw.rounded_rectangle([logo_start_x + 36, logo_base_y - 52, logo_start_x + 48, logo_base_y], radius=6, fill=(255, 255, 255, 255))
    # Playful Blue Stepping Stone
    draw.ellipse([logo_start_x + 58, logo_base_y - 48, logo_start_x + 68, logo_base_y - 38], fill=(41, 151, 255, 255))
    
    # Wordmark text
    text_x = logo_start_x + glyph_w + gap_logo
    text_y = logo_base_y - wh - 2
    draw.text((text_x, text_y), word_text, font=logo_font, fill=(255, 255, 255, 250))
    
    # Subtitle with playful, minimal Airbnb/Apple copy
    subtitle_text = "One small drag. One giant workflow."
    sbbox = subtitle_font.getbbox(subtitle_text)
    sw = sbbox[2] - sbbox[0]
    draw.text((660 - sw // 2, logo_base_y + 22), subtitle_text, font=subtitle_font, fill=(155, 155, 165, 220))
    
    # 7. Minimalist Footer
    footer_text = "macOS Sonoma 14.0 or later · Universal (Apple Silicon & Intel)"
    fbbox = footer_font.getbbox(footer_text)
    fw = fbbox[2] - fbbox[0]
    draw.text((660 - fw // 2, 804), footer_text, font=footer_font, fill=(110, 110, 120, 200))
    
    tip_text = "Option + Space to start capturing anywhere"
    tbox = footer_font.getbbox(tip_text)
    tw = tbox[2] - tbox[0]
    draw.text((660 - tw // 2, 834), tip_text, font=footer_font, fill=(80, 80, 90, 180))
    
    base = Image.alpha_composite(base, gfx)
    
    # 8. Export 2x and 1x Retina PNGs
    os.makedirs(ASSETS_DIR, exist_ok=True)
    
    final_rgb = Image.new("RGB", (W, H), (18, 18, 20))
    final_rgb.paste(base, (0, 0), base)
    
    final_rgb.save(os.path.join(ASSETS_DIR, "background@2x.png"), "PNG", optimize=True)
    final_1x = final_rgb.resize((660, 440), Image.LANCZOS)
    final_1x.save(os.path.join(ASSETS_DIR, "background.png"), "PNG", optimize=True)
    
    print(f"✅ Generated DMG background at {ASSETS_DIR} (background.png + background@2x.png)")

if __name__ == "__main__":
    create_fun_apple_dmg_background()
