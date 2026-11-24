import os
import math
from PIL import Image, ImageDraw, ImageFilter

def create_squircle_mask(width, height, radius):
    # Supersampled mask (4x)
    scale = 4
    sw, sh = width * scale, height * scale
    sr = radius * scale
    mask = Image.new("L", (sw, sh), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, sw - 1, sh - 1], radius=sr, fill=255)
    return mask

def make_gradient(width, height, color_top, color_bottom):
    # Generates a smooth linear vertical gradient
    base = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    for y in range(height):
        ratio = y / float(height - 1)
        r = int(color_top[0] * (1 - ratio) + color_bottom[0] * ratio)
        g = int(color_top[1] * (1 - ratio) + color_bottom[1] * ratio)
        b = int(color_top[2] * (1 - ratio) + color_bottom[2] * ratio)
        a = 255
        for x in range(width):
            base.putpixel((x, y), (r, g, b, a))
    return base

def draw_flat_power_icon(output_path, is_battery=False):
    # 4x canvas for ultra sharp antialiasing
    S = 4
    size = 1024 * S
    
    # Target icon canvas
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Squircle dimensions: 824x824 on 1024 (standard Apple macOS icon grid)
    tile_w = int(824 * S)
    tile_h = int(824 * S)
    pad_x = (size - tile_w) // 2
    pad_y = (size - tile_h) // 2
    radius = int(185 * S)

    # 1. Subtle macOS Drop Shadow
    shadow_offset_y = int(18 * S)
    shadow_blur = int(24 * S)
    shadow_mask = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow_mask)
    s_draw.rounded_rectangle(
        [pad_x, pad_y + shadow_offset_y, pad_x + tile_w, pad_y + tile_h + shadow_offset_y],
        radius=radius,
        fill=(0, 0, 0, 80)
    )
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(shadow_blur))
    img.alpha_composite(shadow_mask)

    # 2. Main Squircle Tile Background
    # Apple vibrant flat gradient (Teal-Mint to Deep Cyan/Electric Blue)
    if not is_battery:
        # Energy Power: Emerald Mint (#10B981) to Deep Teal-Cyan (#0284C7)
        c_top = (16, 185, 129)      # #10B981
        c_bottom = (2, 132, 199)    # #0284C7
    else:
        # Battery Mode: Warm Amber / Coral (#F59E0B) to Deep Orange (#EA580C)
        c_top = (245, 158, 11)      # #F59E0B
        c_bottom = (234, 88, 12)    # #EA580C

    gradient_tile = Image.new("RGBA", (tile_w, tile_h), (0, 0, 0, 0))
    # Vertical gradient
    for y in range(tile_h):
        r_ratio = y / float(tile_h - 1)
        r = int(c_top[0] * (1 - r_ratio) + c_bottom[0] * r_ratio)
        g = int(c_top[1] * (1 - r_ratio) + c_bottom[1] * r_ratio)
        b = int(c_top[2] * (1 - r_ratio) + c_bottom[2] * r_ratio)
        for x in range(tile_w):
            gradient_tile.putpixel((x, y), (r, g, b, 255))

    # Squircle mask for tile
    mask = Image.new("L", (tile_w, tile_h), 0)
    m_draw = ImageDraw.Draw(mask)
    m_draw.rounded_rectangle([0, 0, tile_w, tile_h], radius=radius, fill=255)

    tile = Image.new("RGBA", (tile_w, tile_h), (0, 0, 0, 0))
    tile.paste(gradient_tile, (0, 0), mask)

    # Add very subtle top hairline inner rim (standard macOS HIG 1px light rim)
    rim_draw = ImageDraw.Draw(tile)
    rim_draw.rounded_rectangle(
        [0, 0, tile_w, tile_h],
        radius=radius,
        outline=(255, 255, 255, 50),
        width=int(2 * S)
    )

    img.paste(tile, (pad_x, pad_y), tile)

    # 3. Draw Flat Icon Glyph inside the tile
    glyph_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    g_draw = ImageDraw.Draw(glyph_layer)

    cx = size // 2
    cy = size // 2

    if not is_battery:
        # FLAT MINIMALIST LIGHTNING BOLT & METER RING
        # A. Outer Power Arc / Pulse Ring (clean flat circle stroke with opening)
        ring_radius = int(220 * S)
        ring_width = int(22 * S)
        # Draw circular arc
        bbox = [cx - ring_radius, cy - ring_radius, cx + ring_radius, cy + ring_radius]
        g_draw.arc(bbox, start=135, end=405, fill=(255, 255, 255, 70), width=ring_width)
        # Tick marks on the meter
        for angle_deg in [180, 225, 270, 315, 360]:
            rad = math.radians(angle_deg)
            inner_r = ring_radius - int(24 * S)
            outer_r = ring_radius - int(6 * S)
            x1 = cx + inner_r * math.cos(rad)
            y1 = cy + inner_r * math.sin(rad)
            x2 = cx + outer_r * math.cos(rad)
            y2 = cy + outer_r * math.sin(rad)
            g_draw.line([(x1, y1), (x2, y2)], fill=(255, 255, 255, 90), width=int(6 * S))

        # B. Central Sharp Flat Lightning Bolt
        # Scaled coordinates
        # Geometric bold lightning bolt points
        pts = [
            (cx + int(30 * S), cy - int(210 * S)),   # Top tip
            (cx - int(120 * S), cy + int(15 * S)),   # Left indent corner
            (cx - int(10 * S), cy + int(15 * S)),    # Inner waist left
            (cx - int(50 * S), cy + int(215 * S)),   # Bottom tip
            (cx + int(120 * S), cy - int(10 * S)),   # Right indent corner
            (cx + int(15 * S), cy - int(10 * S))     # Inner waist right
        ]
        g_draw.polygon(pts, fill=(255, 255, 255, 255))

    else:
        # FLAT BATTERY GLYPH
        bat_w = int(320 * S)
        bat_h = int(180 * S)
        bat_radius = int(36 * S)
        bat_border = int(18 * S)

        bx0 = cx - bat_w // 2 - int(15 * S)
        by0 = cy - bat_h // 2
        bx1 = bx0 + bat_w
        by1 = by0 + bat_h

        # Battery Outer Body
        g_draw.rounded_rectangle(
            [bx0, by0, bx1, by1],
            radius=bat_radius,
            outline=(255, 255, 255, 240),
            width=bat_border
        )

        # Terminal Cap
        cap_w = int(22 * S)
        cap_h = int(70 * S)
        cx0 = bx1 + int(8 * S)
        cy0 = cy - cap_h // 2
        cx1 = cx0 + cap_w
        cy1 = cy + cap_h // 2
        g_draw.rounded_rectangle(
            [cx0, cy0, cx1, cy1],
            radius=int(10 * S),
            fill=(255, 255, 255, 240)
        )

        # Inside Flat Charge Level Blocks (3 green/white bars)
        inner_pad = int(16 * S)
        available_w = (bx1 - bx0) - (2 * (bat_border + inner_pad))
        bar_count = 3
        gap = int(10 * S)
        single_bar_w = (available_w - (bar_count - 1) * gap) // bar_count
        bar_h = (by1 - by0) - (2 * (bat_border + inner_pad))

        for i in range(bar_count):
            bar_x0 = bx0 + bat_border + inner_pad + i * (single_bar_w + gap)
            bar_y0 = by0 + bat_border + inner_pad
            bar_x1 = bar_x0 + single_bar_w
            bar_y1 = bar_y0 + bar_h
            g_draw.rounded_rectangle(
                [bar_x0, bar_y0, bar_x1, bar_y1],
                radius=int(10 * S),
                fill=(255, 255, 255, 255 if i < 2 else 120)
            )

    # Composite glyph onto base image
    img.alpha_composite(glyph_layer)

    # Downsample from 4096x4096 to 1024x1024 with Lanczos for razor-sharp vector antialiasing
    final_img = img.resize((1024, 1024), Image.Resampling.LANCZOS)
    final_img.save(output_path, "PNG", optimize=True)
    print(f"Generated flat icon at {output_path}")

if __name__ == "__main__":
    draw_flat_power_icon("assets/logo.png", is_battery=False)
    draw_flat_power_icon("assets/logo_battery.png", is_battery=True)
