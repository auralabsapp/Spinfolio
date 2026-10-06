#!/usr/bin/env python3
"""Variante du correctif d'heure pour les captures à fond photo (03, 09) : au lieu
d'un aplat de couleur (qui crée un rectangle visible sur un fond dégradé/flou), on
floute localement la zone pour dissoudre les anciens chiffres dans le fond, avec un
masque à bords adoucis pour éviter toute coupure nette, puis on redessine "9:41"."""

from PIL import Image, ImageDraw, ImageFont, ImageFilter

CANVAS_W, CANVAS_H = 1284, 2778
DIR = "/Users/aurelienscarpa/Desktop/Spinlog/Marketing/AppStoreScreenshots/6.5inch"
FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"

# (fichier, couleur de texte détectée précédemment)
FILES = [
    ("03-fiche-disque.png", (0, 0, 0)),
    ("09-rangement.png", (0, 0, 0)),
    ("10-scan.png", (255, 255, 255)),
    ("11-theme-sombre.png", (255, 255, 255)),
]

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


SEARCH_X0, SEARCH_Y0 = 100, 55
SEARCH_X1, SEARCH_Y1 = 340, 140
fx0, fy0 = to_final(SEARCH_X0, SEARCH_Y0)
fx1, fy1 = to_final(SEARCH_X1, SEARCH_Y1)
fx0, fy0, fx1, fy1 = round(fx0), round(fy0), round(fx1), round(fy1)

PAD = 40
# Étend la zone à effacer plus loin à droite pour couvrir une éventuelle icône
# (cloche muette, flèche de localisation) après l'heure d'origine.
RIGHT_EXTRA = 60


def average_color(img, box):
    region = img.crop(box)
    small = region.resize((1, 1), Image.BOX)
    return small.getpixel((0, 0))


def process(path, text_color):
    img = Image.open(path).convert("RGB")

    core = (fx0, fy0, fx1 + RIGHT_EXTRA, fy1)
    outer = (core[0] - PAD, core[1] - PAD, core[2] + PAD, core[3] + PAD)

    # Couleur de fond moyenne échantillonnée juste au-dessus et en dessous de la
    # zone à effacer (bandes très probablement libres de tout texte).
    strip_h = 14
    top_strip = average_color(img, (outer[0], outer[1], outer[2], outer[1] + strip_h))
    bottom_strip = average_color(img, (outer[0], outer[3] - strip_h, outer[2], outer[3]))
    fill = tuple(round((a + b) / 2) for a, b in zip(top_strip, bottom_strip))

    # Calque entièrement plat (même couleur partout, cœur ET marge) : là où le
    # masque est opaque, on colle donc toujours de l'aplat pur — jamais l'ancien
    # texte flouté — donc aucun résidu ("ghosting") possible. Le masque contrôle
    # uniquement la transition douce vers le fond photo environnant.
    outer_size = (outer[2] - outer[0], outer[3] - outer[1])
    flat_layer = Image.new("RGB", outer_size, fill)

    mask = Image.new("L", outer_size, 0)
    core_local = (core[0] - outer[0], core[1] - outer[1], core[2] - outer[0], core[3] - outer[1])
    ImageDraw.Draw(mask).rectangle(core_local, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(PAD * 0.5))
    # `filter` renvoie une NOUVELLE image : il faut redessiner sur cette nouvelle
    # instance (pas sur l'ancien objet `mask` déjà remplacé) pour que le cœur
    # reste bien à 255 après le flou, qui ne doit adoucir que la marge extérieure.
    ImageDraw.Draw(mask).rectangle(core_local, fill=255)

    img.paste(flat_layer, (outer[0], outer[1]), mask)

    draw = ImageDraw.Draw(img)
    text_h = fy1 - fy0 - 18  # légère marge, cohérent avec le script précédent
    font_size = round(text_h * 0.78)
    font = ImageFont.truetype(FONT_BOLD, font_size)
    text_x = fx0 + 10
    text_y = fy0 + (fy1 - fy0 - font_size) / 2 - font_size * 0.05
    draw.text((text_x, text_y), "9:41", font=font, fill=text_color)

    img.save(path, "PNG")
    print(f"OK -> {path}")


if __name__ == "__main__":
    for name, color in FILES:
        process(f"{DIR}/{name}", color)
