#!/usr/bin/env python3
"""Remplace l'heure de la barre de statut (ex: 20:01) par 9:41 (convention Apple)
sur les captures déjà composées dans le mockup iPhone. Détecte automatiquement la
couleur de fond et de texte à chaque emplacement (certaines captures ont un fond
photo derrière la barre de statut plutôt qu'un fond blanc uni)."""

from PIL import Image, ImageDraw, ImageFont

CANVAS_W, CANVAS_H = 1284, 2778
DIR = "/Users/aurelienscarpa/Desktop/Spinlog/Marketing/AppStoreScreenshots/6.5inch"
FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"

FILES = [
    "01-collection.png", "02-carousel.png", "03-fiche-disque.png",
    "04-tags-champs.png", "05-wantlist.png", "06-cote-marche.png",
    "07-statistiques.png", "08-podium.png", "09-rangement.png",
]

# --- Reproduit exactement la géométrie du cadre iPhone du script de génération ---
frame_top_y = 560
bottom_margin = 90
frame_h = CANVAS_H - frame_top_y - bottom_margin
device_ratio = 2622 / 1206
frame_w = round(frame_h / device_ratio)
frame_x = round((CANVAS_W - frame_w) / 2)
bezel = round(frame_w * 0.026)
inner_x = frame_x + bezel
inner_y = frame_top_y + bezel
inner_w = frame_w - 2 * bezel
inner_h = frame_h - 2 * bezel

# Correspondance avec le mapping "cover" du script de génération (source 1206x2622)
src_w, src_h = 1206, 2622
src_ratio = src_w / src_h
dst_ratio = inner_w / inner_h
if src_ratio > dst_ratio:
    new_h = inner_h
    new_w = round(new_h * src_ratio)
else:
    new_w = inner_w
    new_h = round(new_w / src_ratio)
crop_x = round((new_w - inner_w) / 2)
crop_y = round((new_h - inner_h) / 2)
scale = new_h / src_h


def to_final(x, y):
    return (inner_x + (x * scale - crop_x), inner_y + (y * scale - crop_y))


# Zone de recherche généreuse autour de l'heure, en coordonnées de l'écran source (1206x2622)
# (bbox réelle mesurée sur un screenshot brut : 123,76 -> 317,117)
SEARCH_X0, SEARCH_Y0 = 100, 55
SEARCH_X1, SEARCH_Y1 = 340, 140

fx0, fy0 = to_final(SEARCH_X0, SEARCH_Y0)
fx1, fy1 = to_final(SEARCH_X1, SEARCH_Y1)
fx0, fy0, fx1, fy1 = round(fx0), round(fy0), round(fx1), round(fy1)


def luminance(rgb):
    r, g, b = rgb
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def process(path):
    img = Image.open(path).convert("RGB")
    region = img.crop((fx0, fy0, fx1, fy1))
    pixels = region.load()
    w, h = region.size

    # Couleur de fond = pixel du coin haut-gauche de la zone (avant tout glyphe)
    bg = pixels[2, 2]
    bg_lum = luminance(bg)

    # Cherche le pixel le plus contrasté (texte) pour connaître sa couleur et sa bbox
    max_diff = 0
    text_color = None
    min_x, min_y, max_x, max_y = w, h, 0, 0
    for yy in range(h):
        for xx in range(w):
            p = pixels[xx, yy]
            diff = abs(luminance(p) - bg_lum)
            if diff > 60:  # seuil de contraste texte/fond
                if xx < min_x:
                    min_x = xx
                if yy < min_y:
                    min_y = yy
                if xx > max_x:
                    max_x = xx
                if yy > max_y:
                    max_y = yy
                if diff > max_diff:
                    max_diff = diff
                    text_color = p

    if text_color is None:
        print(f"SKIP (aucun texte détecté) -> {path}")
        return

    pad = 6
    box = (
        max(0, min_x - pad), max(0, min_y - pad),
        min(w, max_x + pad), min(h, max_y + pad),
    )
    text_h = box[3] - box[1]

    draw = ImageDraw.Draw(img)
    abs_box = (fx0 + box[0], fy0 + box[1], fx0 + box[2], fy0 + box[3])
    draw.rectangle(abs_box, fill=bg)

    font_size = round(text_h * 0.92)
    font = ImageFont.truetype(FONT_BOLD, font_size)
    text_y = fy0 + box[1] + (text_h - font.size) / 2 - font_size * 0.08
    draw.text((fx0 + box[0], text_y), "9:41", font=font, fill=text_color)

    img.save(path, "PNG")
    print(f"OK bg={bg} text={text_color} bbox={box} -> {path}")


if __name__ == "__main__":
    for name in FILES:
        process(f"{DIR}/{name}")
