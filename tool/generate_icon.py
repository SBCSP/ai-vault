#!/usr/bin/env python3
"""Generate AV logo app icons for macOS at all required sizes."""

from PIL import Image, ImageDraw
import math
import os

def lerp_color(c1, c2, t):
    """Linear interpolation between two RGB tuples."""
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))

def lerp_offset(x1, y1, x2, y2, target_y):
    """Find x position on line (x1,y1)-(x2,y2) at given y."""
    t = (target_y - y1) / (y2 - y1)
    return x1 + t * (x2 - x1)

def draw_av_icon(size):
    """Draw the AV logo at given pixel size, returns RGBA Image."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    cx, cy = size / 2, size / 2
    radius = size / 2

    # --- Background circle with gradient (simulated) ---
    primary = (63, 81, 181)       # Indigo
    light = lerp_color(primary, (255, 255, 255), 0.2)
    dark = lerp_color(primary, (0, 0, 0), 0.45)

    # Draw gradient circle using concentric circles
    for r in range(int(radius), 0, -1):
        t = 1.0 - (r / radius)
        # Bias the gradient to simulate top-left lighting
        if t < 0.4:
            color = lerp_color(light, primary, t / 0.4)
        else:
            color = lerp_color(primary, dark, (t - 0.4) / 0.6)
        draw.ellipse(
            [cx - r, cy - r, cx + r, cy + r],
            fill=color + (255,)
        )

    scale = size / 120.0
    stroke_w = max(1, int(4.5 * scale))
    cross_w = max(1, int(3.0 * scale))

    def draw_letters(offset_y, color, alpha=255):
        ccy = cy + offset_y
        shared_x = cx
        a_left = cx - 28 * scale
        a_top = ccy - 24 * scale
        a_bottom = ccy + 24 * scale
        a_mid = (a_left + shared_x) / 2
        a_cross_y = ccy + 4 * scale

        fill = color + (alpha,)

        # "A" letter
        draw.line([(a_left, a_bottom), (a_mid, a_top)], fill=fill, width=stroke_w)
        draw.line([(a_mid, a_top), (shared_x, a_bottom)], fill=fill, width=stroke_w)

        # A crossbar
        cl = lerp_offset(a_left, a_bottom, a_mid, a_top, a_cross_y)
        cr = lerp_offset(shared_x, a_bottom, a_mid, a_top, a_cross_y)
        draw.line([(cl, a_cross_y), (cr, a_cross_y)], fill=fill, width=cross_w)

        # "V" letter
        v_right = cx + 28 * scale
        v_mid = (shared_x + v_right) / 2
        v_top = ccy - 24 * scale

        draw.line([(shared_x, v_top), (v_mid, a_bottom)], fill=fill, width=stroke_w)
        draw.line([(v_mid, a_bottom), (v_right, v_top)], fill=fill, width=stroke_w)

        # Draw rounded joints/endpoints
        joint_r = max(1, stroke_w // 2)
        points = [
            (a_left, a_bottom), (a_mid, a_top), (shared_x, a_bottom),
            (shared_x, v_top), (v_mid, a_bottom), (v_right, v_top),
        ]
        for px, py in points:
            draw.ellipse(
                [px - joint_r, py - joint_r, px + joint_r, py + joint_r],
                fill=fill
            )
        # Crossbar endpoints
        cr_r = max(1, cross_w // 2)
        for px, py in [(cl, a_cross_y), (cr, a_cross_y)]:
            draw.ellipse(
                [px - cr_r, py - cr_r, px + cr_r, py + cr_r],
                fill=fill
            )

    # Shadow layer
    shadow_color = lerp_color(primary, (0, 0, 0), 0.6)
    draw_letters(2.5 * scale, shadow_color, alpha=128)

    # Main white letters
    draw_letters(0, (255, 255, 255), alpha=255)

    # Highlight layer
    draw_letters(-1.0 * scale, (255, 255, 255), alpha=55)

    return img

def main():
    base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    icon_dir = os.path.join(
        base, 'macos', 'Runner', 'Assets.xcassets',
        'AppIcon.appiconset'
    )

    sizes = [16, 32, 64, 128, 256, 512, 1024]

    for s in sizes:
        img = draw_av_icon(s)
        path = os.path.join(icon_dir, f'app_icon_{s}.png')
        img.save(path, 'PNG')
        print(f'Generated {path} ({s}x{s})')

    print('Done! All macOS icons generated.')
    print('Rebuild the app with: flutter build macos')

if __name__ == '__main__':
    main()
