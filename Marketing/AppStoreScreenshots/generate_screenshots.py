#!/usr/bin/env python3
"""Génère les captures App Store 6,3 pouces : screenshot encadré dans un mockup iPhone
avec un libellé de fonctionnalité au-dessus. Usage ponctuel, pas de dépendance au projet."""

import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

CANVAS_W, CANVAS_H = 1206, 2622
OUT_DIR = "/Users/aurelienscarpa/Desktop/Spinlog/Marketing/AppStoreScreenshots/6.3inch"

FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"

BG_TOP = (251, 249, 253)
BG_BOTTOM = (240, 234, 247)
TEXT_COLOR = (28, 28, 30)
FRAME_TOP = (74, 74, 77)
FRAME_MID = (10, 10, 11)
FRAME_BOTTOM = (40, 40, 43)

SHOTS = [
    {
        "src": "/var/folders/l_/6h129vcx4hddx9qlcrn1cw1c0000gn/T/Coding Assistant/Attachments/Conversations/102550AB-1456-4C1D-952F-81C57324CD87/Dropped/93E36CE5-82D1-47C7-BB3F-926002356C56/IMG_5682.PNG",
        "out": "01-collection.png",
        "caption": "Toute ta collection,\norganisée à ta façon",
    },
    {
        "src": "/var/folders/l_/6h129vcx4hddx9qlcrn1cw1c0000gn/T/Coding Assistant/Attachments/Conversations/102550AB-1456-4C1D-952F-81C57324CD87/Dropped/15225E16-1612-494B-8445-CF088547B4A1/IMG_5691.PNG",
        "out": "02-carousel.png",
        "caption": "Parcours ta collection\nen un coup d'œil",
    },
    {
        "src": "/var/folders/l_/6h129vcx4hddx9qlcrn1cw1c0000gn/T/Coding Assistant/Attachments/Conversations/102550AB-1456-4C1D-952F-81C57324CD87/Dropped/B9B7E597-FBE7-46D6-8673-8C6BB0BA469E/IMG_5684.PNG",
        "out": "03-fiche-disque.png",
        "caption": "Suis la valeur et l'emplacement\nde chaque disque",
    },
    {
        "src": "/var/folders/l_/6h129vcx4hddx9qlcrn1cw1c0000gn/T/Coding Assistant/Attachments/Conversations/102550AB-1456-4C1D-952F-81C57324CD87/Dropped/5D3808BA-DD67-43E1-9984-FAAEC596B85D/IMG_5690.PNG",
        "out": "04-tags-champs.png",
        "caption": "Tags et champs personnalisés\npour chaque exemplaire",
    },
    {
        "src": "/var/folders/l_/6h129vcx4hddx9qlcrn1cw1c0000gn/T/Coding Assistant/Attachments/Conversations/102550AB-1456-4C1D-952F-81C57324CD87/Dropped/87B74C06-FD25-4EA9-87D5-A266F4D9032A/IMG_5685.PNG",
        "out": "05-wantlist.png",
        "caption": "Alertes de prix sur\nta liste d'envies",
    },
    {
        "src": "/var/folders/l_/6h129vcx4hddx9qlcrn1cw1c0000gn/T/Coding Assistant/Attachments/Conversations/102550AB-1456-4C1D-952F-81C57324CD87/Dropped/35CD5342-664F-4CE5-9A19-B111D676A481/IMG_5689.PNG",
        "out": "06-cote-marche.png",
        "caption": "Cote de marché en temps réel,\npar état du disque",
    },
    {
        "src": "/var/folders/l_/6h129vcx4hddx9qlcrn1cw1c0000gn/T/Coding Assistant/Attachments/Conversations/102550AB-1456-4C1D-952F-81C57324CD87/Dropped/BFFC234F-CCEC-41D3-A203-60614AFBC4BF/IMG_5686.PNG",
        "out": "07-statistiques.png",
        "caption": "Toutes les statistiques\nde ta discothèque",
    },
    {
        "src": "/var/folders/l_/6h129vcx4hddx9qlcrn1cw1c0000gn/T/Coding Assistant/Attachments/Conversations/102550AB-1456-4C1D-952F-81C57324CD87/Dropped/233044AF-B3F6-4BC0-9618-8E3DCCD9427B/IMG_5688.PNG",
        "out": "08-podium.png",
        "caption": "Ton palmarès d'écoute\net tes podiums",
    },
    {
        "src": "/var/folders/l_/6h129vcx4hddx9qlcrn1cw1c0000gn/T/Coding Assistant/Attachments/Conversations/102550AB-1456-4C1D-952F-81C57324CD87/Dropped/35C7B1C2-AE54-44DE-969D-63450AAE55FA/IMG_5692.PNG",
        "out": "09-rangement.png",
        "caption": "Localise chaque disque\ndans ton meuble",
    },
    {
        "src": "/var/folders/l_/6h129vcx4hddx9qlcrn1cw1c0000gn/T/Coding Assistant/Attachments/Conversations/102550AB-1456-4C1D-952F-81C57324CD87/Dropped/A9183021-5702-404F-B408-01A4352EDFF0/IMG_5694.PNG",
        "out": "10-scan.png",
        "caption": "Scanne toute ta pile\nen un instant",
    },
    {
        "src": "/var/folders/l_/6h129vcx4hddx9qlcrn1cw1c0000gn/T/Coding Assistant/Attachments/Conversations/102550AB-1456-4C1D-952F-81C57324CD87/Dropped/1C752A5A-52F5-47A9-B66F-27CC47A9D3D3/IMG_5695.PNG",
        "out": "11-theme-sombre.png",
        "caption": "Compatible thème sombre,\njusqu'au moindre détail",
    },
]


def vertical_gradient(w, h, top, bottom):
    base = Image.new("RGB", (w, h), top)
    top_arr = top
    bottom_arr = bottom
    for y in range(h):
        t = y / (h - 1)
        r = round(top_arr[0] + (bottom_arr[0] - top_arr[0]) * t)
        g = round(top_arr[1] + (bottom_arr[1] - top_arr[1]) * t)
        b = round(top_arr[2] + (bottom_arr[2] - top_arr[2]) * t)
        ImageDraw.Draw(base).line([(0, y), (w, y)], fill=(r, g, b))
    return base


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return mask


def wrap_and_draw_caption(draw, text, font, canvas_w, top_y, color):
    lines = text.split("\n")
    line_height = font.size + 14
    total_h = line_height * len(lines)
    y = top_y
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=font)
        w = bbox[2] - bbox[0]
        x = (canvas_w - w) / 2
        draw.text((x, y), line, font=font, fill=color)
        y += line_height
    return total_h


def build_frame_gradient(w, h, radius):
    """Anneau 'titane' du cadre iPhone : dégradé diagonal clair -> foncé -> clair."""
    grad = Image.new("RGB", (w, h))
    px = grad.load()
    for y in range(h):
        for x in range(0, w, 4):
            t = ((x / w) * 0.4 + (y / h) * 0.6)
            t = (math.sin(t * math.pi * 1.6) + 1) / 2
            r = round(FRAME_TOP[0] + (FRAME_MID[0] - FRAME_TOP[0]) * t)
            g = round(FRAME_TOP[1] + (FRAME_MID[1] - FRAME_TOP[1]) * t)
            b = round(FRAME_TOP[2] + (FRAME_MID[2] - FRAME_TOP[2]) * t)
            for dx in range(4):
                if x + dx < w:
                    px[x + dx, y] = (r, g, b)
    mask = rounded_mask((w, h), radius)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(grad, (0, 0), mask)
    return out


def make_shot(src_path, caption, out_path):
    canvas = vertical_gradient(CANVAS_W, CANVAS_H, BG_TOP, BG_BOTTOM).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    caption_font = ImageFont.truetype(FONT_BOLD, 76)
    caption_top_y = 150
    wrap_and_draw_caption(draw, caption, caption_font, CANVAS_W, caption_top_y, TEXT_COLOR)

    frame_top_y = 560
    bottom_margin = 90
    frame_h = CANVAS_H - frame_top_y - bottom_margin
    device_ratio = 2622 / 1206
    frame_w = round(frame_h / device_ratio)
    frame_x = round((CANVAS_W - frame_w) / 2)

    outer_radius = round(frame_w * 0.135)
    bezel = round(frame_w * 0.026)
    inner_radius = max(outer_radius - bezel, 10)

    # Ombre portée
    shadow = Image.new("RGBA", (frame_w + 200, frame_h + 200), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [100, 130, 100 + frame_w, 130 + frame_h], radius=outer_radius, fill=(20, 10, 30, 120)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(40))
    canvas.paste(shadow, (frame_x - 100, frame_top_y - 100), shadow)

    # Cadre titane
    frame_img = build_frame_gradient(frame_w, frame_h, outer_radius)
    canvas.paste(frame_img, (frame_x, frame_top_y), frame_img)

    # Écran (screenshot) découpé et centré-cropé dans l'ouverture intérieure
    inner_x = frame_x + bezel
    inner_y = frame_top_y + bezel
    inner_w = frame_w - 2 * bezel
    inner_h = frame_h - 2 * bezel

    shot = Image.open(src_path).convert("RGB")
    src_ratio = shot.width / shot.height
    dst_ratio = inner_w / inner_h
    if src_ratio > dst_ratio:
        new_h = inner_h
        new_w = round(new_h * src_ratio)
    else:
        new_w = inner_w
        new_h = round(new_w / src_ratio)
    shot_resized = shot.resize((new_w, new_h), Image.LANCZOS)
    crop_x = round((new_w - inner_w) / 2)
    crop_y = round((new_h - inner_h) / 2)
    shot_cropped = shot_resized.crop((crop_x, crop_y, crop_x + inner_w, crop_y + inner_h))

    inner_mask = rounded_mask((inner_w, inner_h), inner_radius)
    screen_layer = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    screen_layer.paste(shot_cropped, (inner_x, inner_y), inner_mask)
    canvas = Image.alpha_composite(canvas, screen_layer)

    # Pas de Dynamic Island redessinée ici : elle est déjà présente nativement
    # dans le screenshot capturé (rendue par iOS), la redessiner créait un doublon
    # mal aligné qui recouvrait la barre de statut.

    canvas.convert("RGB").save(out_path, "PNG")
    print(f"OK -> {out_path}")


def run_for_size(canvas_w, canvas_h, out_dir):
    global CANVAS_W, CANVAS_H, OUT_DIR
    CANVAS_W, CANVAS_H, OUT_DIR = canvas_w, canvas_h, out_dir
    import os
    os.makedirs(out_dir, exist_ok=True)
    for shot in SHOTS:
        make_shot(shot["src"], shot["caption"], f"{out_dir}/{shot['out']}")


if __name__ == "__main__":
    run_for_size(1206, 2622, "/Users/aurelienscarpa/Desktop/Spinlog/Marketing/AppStoreScreenshots/6.3inch")
    run_for_size(1284, 2778, "/Users/aurelienscarpa/Desktop/Spinlog/Marketing/AppStoreScreenshots/6.5inch")
