#!/usr/bin/env python3
"""Génère les 10 images « Aperçu d'app et captures d'écran » de la fiche App Store
(1206 x 2622 px, iPhone 6,3") et la planche qui les réunit côte à côte.

Chaque image : fond dégradé aux couleurs de la marque, accroche en New York (la police serif
des titres de l'app), sous-titre en SF, pastille « PREMIUM » dorée pour les fonctions
Premium, et capture simulateur (dossier `raw/`, 1206 x 2622 natifs) dans un cadre d'iPhone.

Usage : python3 docs/appstore-screenshots/generate.py
Dépendance : Pillow. Aucune dépendance au projet Xcode.
"""

import math
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
RAW_DIR = os.path.join(HERE, "raw")

W, H = 1206, 2622

SERIF = "/System/Library/Fonts/NewYork.ttf"
SANS = "/System/Library/Fonts/SFNS.ttf"

# Or Premium : mêmes teintes que `goldLight` / `goldWarm` / `goldDeep` dans AppColors.swift.
GOLD_LIGHT = (250, 199, 71)
GOLD_WARM = (224, 133, 31)
GOLD_TEXT = (74, 38, 4)

# Dynamic Island, en pixels de la capture native 1206 x 2622 (relevée dans la hiérarchie
# d'accessibilité : 125,3 x 36,7 pt à (138,3 ; 14) en 3x). Le simulateur ne la dessine pas
# dans ses captures.
ISLAND = (415, 42, 376, 110)

# Géométrie du téléphone : large, ancré en bas de l'image comme dans les fiches des autres apps.
PHONE_W = 980
PHONE_TOP = 580
BEZEL = 14
SCREEN_RADIUS = 142

# Fonds : tous dans la famille de la palette Signature de l'app (violet 158/61/207, clair 210/122/245, foncé
# 133/46/184 dans AppTheme.swift) et de l'orchidée de l'icône. Chaque image a son propre dégradé : angle
# (0° = de haut en bas), arrêts de couleur et halos. Les zones sous le texte restent assez sombres pour un
# texte blanc lisible (contrôlé par `contrast_check`).
PALETTES = {
    "orchidee": {"angle": 20, "stops": [(0.0, (150, 66, 204)), (0.5, (122, 50, 180)), (1.0, (66, 26, 112))],
                 "glows": [((236, 150, 250), 0.18, 0.34), ((120, 56, 200), 0.85, 0.60)]},
    "rose": {"angle": -28, "stops": [(0.0, (154, 60, 174)), (0.5, (134, 52, 172)), (1.0, (72, 28, 118))],
             "glows": [((255, 150, 214), 0.85, 0.34), ((150, 70, 220), 0.12, 0.64)]},
    "lavande": {"angle": 14, "stops": [(0.0, (92, 42, 152)), (0.55, (128, 76, 198)), (1.0, (178, 132, 238))],
                "glows": [((226, 184, 255), 0.50, 0.92), ((130, 70, 210), 0.15, 0.40)]},
    "prune": {"angle": 0, "stops": [(0.0, (116, 46, 170)), (0.5, (70, 26, 116)), (1.0, (34, 12, 64))],
              "glows": [((196, 100, 240), 0.50, 0.34), ((140, 66, 204), 0.10, 0.62)]},
    "magenta": {"angle": 36, "stops": [(0.0, (172, 66, 180)), (0.5, (136, 52, 172)), (1.0, (80, 30, 126))],
                "glows": [((255, 168, 224), 0.92, 0.40), ((130, 60, 210), 0.10, 0.70)]},
    "amethyste": {"angle": -42, "stops": [(0.0, (146, 84, 214)), (0.5, (110, 58, 184)), (1.0, (60, 26, 112))],
                  "glows": [((214, 150, 250), 0.10, 0.36), ((100, 50, 180), 0.90, 0.68)]},
    "lilas": {"angle": -16, "stops": [(0.0, (104, 52, 170)), (0.6, (146, 90, 214)), (1.0, (196, 150, 244))],
              "glows": [((240, 210, 255), 0.50, 0.80), ((122, 62, 200), 0.80, 0.55)]},
    "pourpre": {"angle": 12, "stops": [(0.0, (150, 62, 200)), (0.5, (104, 40, 158)), (1.0, (48, 18, 90))],
                "glows": [((222, 128, 244), 0.80, 0.36), ((96, 46, 168), 0.14, 0.66)]},
    "aube": {"angle": 52, "stops": [(0.0, (180, 74, 196)), (0.45, (140, 56, 186)), (1.0, (86, 34, 140))],
             "glows": [((255, 190, 232), 0.90, 0.36), ((150, 74, 222), 0.14, 0.60)]},
    "nuit": {"angle": 0, "stops": [(0.0, (62, 32, 98)), (0.5, (30, 15, 52)), (1.0, (10, 6, 20))],
             "glows": [((150, 80, 210), 0.50, 0.12), ((110, 50, 170), 0.10, 0.62)]},
}

# Conditions de prise de vue (simulateur iPhone 17, compte réel, barre d'état 09:41, apparence claire sauf
# la 10) et procédure de reprise : voir QA/captures-appstore.md. Une ligne par image ci-dessous.
SLIDES = [
    # 01 : mosaïque, tri Année décroissant (compte réel, 30/10/2026)
    {"raw": "01_mosaic.png", "out": "01-collection.png", "palette": "orchidee",
     "title": ["Toute ta collection,", "en un coup d'œil"],
     "subtitle": "Vinyles, CD et K7 synchronisés avec Discogs"},
    # 02 : carrousel centré sur Californication (RHCP), tri Date d'ajout, n° 183/291
    {"raw": "02_carousel.png", "out": "02-carrousel.png", "palette": "rose",
     "title": ["Parcours tes albums", "comme chez le disquaire"],
     "subtitle": "Le carrousel qui met chaque pochette en scène"},
    # 03 : fiche de Hurry Up, We're Dreaming (M83), en collection
    {"raw": "03_release.png", "out": "03-fiche-disque.png", "palette": "lavande",
     "title": ["Une fiche complète", "pour chaque disque"],
     "subtitle": "Exemplaires, notes, rangement et écoutes sur platine"},
    # 04 : « Mon exemplaire » de Fallen (Evanescence, 2023), plus-value +57 € (Premium)
    {"raw": "04_instance.png", "out": "04-plus-value.png", "palette": "prune", "premium": True,
     "title": ["Mesure la plus-value", "de chaque exemplaire"],
     "subtitle": "Plus-value, tags et champs personnalisés"},
    # 05 : guide de rangement, Garbage n° 90/287 (Premium)
    {"raw": "05_shelf.png", "out": "05-rangement.png", "palette": "magenta", "premium": True,
     "title": ["Retrouve la place", "exacte de chaque disque"],
     "subtitle": "Le guide de rangement, entre ses deux voisins"},
    # 06 : feuille « Alerte de prix » de Thriller, alerte à 25 € déjà enregistrée (Premium)
    {"raw": "06_alert.png", "out": "06-alerte-prix.png", "palette": "amethyste", "premium": True,
     "title": ["Ta wantlist,", "toujours sous surveillance"],
     "subtitle": "Fixe ton prix maximum, sois prévenu dès qu'une annonce l'atteint"},
    # 07 : Statistiques, haut de page
    {"raw": "07_stats.png", "out": "07-statistiques.png", "palette": "lilas",
     "title": ["Ta discothèque", "en chiffres"],
     "subtitle": "Derniers ajouts, ajouts par année, sorties originales"},
    # 08 : estimation, investi vs cote et palmarès d'écoute (Premium)
    {"raw": "08_value.png", "out": "08-valeur-palmares.png", "palette": "pourpre", "premium": True,
     "title": ["Suis la valeur", "de ta collection"],
     "subtitle": "Investi vs cote actuelle, plus-value et palmarès d'écoute"},
    # 09 : Réglages › Mes grades, grade Disquaire (gratuit)
    {"raw": "09_grades.png", "out": "09-grades.png", "palette": "aube",
     "title": ["Deviens un vrai", "collectionneur"],
     "subtitle": "Des grades à atteindre, au fil de tes disques et de tes écoutes"},
    # 10 : collection en liste, apparence sombre, tri Date d'ajout
    {"raw": "10_dark_list.png", "out": "10-theme-sombre.png", "palette": "nuit",
     "title": ["Clair ou sombre,", "selon ton humeur"],
     "subtitle": "Un thème sombre soigné jusque dans les détails"},
]


def font(path, size, variation):
    f = ImageFont.truetype(path, size)
    f.set_variation_by_name(variation)
    return f


def background(palette):
    """Dégradé linéaire incliné à plusieurs arrêts + halos flous (positions en fraction de la largeur/hauteur).
    Calculé sur une grille réduite puis agrandi : lisse, sans bandes, sans dépendance à numpy."""
    scale = 6
    w, h = W // scale, H // scale
    angle = math.radians(palette["angle"])
    dx, dy = math.sin(angle), math.cos(angle)
    length = abs(w * dx) + abs(h * dy)
    stops = palette["stops"]
    small = Image.new("RGB", (w, h))
    px = small.load()
    for y in range(h):
        for x in range(w):
            t = ((x - w / 2) * dx + (y - h / 2) * dy) / length + 0.5
            t = min(1.0, max(0.0, t))
            for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
                if t <= t1:
                    k = (t - t0) / (t1 - t0) if t1 > t0 else 0.0
                    px[x, y] = tuple(round(c0[i] + (c1[i] - c0[i]) * k) for i in range(3))
                    break
    canvas = small.resize((W, H), Image.BICUBIC).convert("RGBA")
    for color, fx, fy in palette["glows"]:
        glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        cx, cy, r = fx * W, fy * H, 620
        ImageDraw.Draw(glow).ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (120,))
        canvas = Image.alpha_composite(canvas, glow.filter(ImageFilter.GaussianBlur(260)))
    return canvas


def contrast_check(canvas):
    """Rapport de contraste d'un texte blanc sur le fond, dans la zone du titre (haut de l'image) : renvoie le
    plus faible des points échantillonnés (WCAG, 3:1 minimum pour un grand texte gras)."""
    def lin(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    worst = 99.0
    for fx in (0.10, 0.30, 0.50, 0.70, 0.90):
        for fy in (0.04, 0.10, 0.16, 0.21):
            r, g, b = canvas.getpixel((int(fx * W), int(fy * H)))[:3]
            lum = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
            worst = min(worst, 1.05 / (lum + 0.05))
    return worst


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return mask


def fit_font(draw, lines, path, variation, max_w, start, minimum):
    """Plus grande taille pour laquelle toutes les lignes tiennent dans `max_w`."""
    size = start
    while size > minimum:
        f = font(path, size, variation)
        if max(draw.textlength(line, font=f) for line in lines) <= max_w:
            return f
        size -= 2
    return font(path, minimum, variation)


def draw_text_line(draw, text, f, x, y, fill):
    """Dessine une ligne de texte. New York Bold (variable) n'a aucun contour pour le trait
    d'union : sans correctif, « plus-value » s'affiche « plus value ». Quand le glyphe est vide,
    le trait est dessiné à la main, centré dans l'espace que la police lui réserve."""
    draw.text((x, y), text, font=f, fill=fill)
    if f.getmask("-").getbbox() is not None:
        return
    advance = f.getlength("-")
    for i, char in enumerate(text):
        if char != "-":
            continue
        left = x + draw.textlength(text[:i], font=f)
        bar_w = advance * 0.72
        bar_h = max(4, f.size * 0.075)
        cy = y + f.size * 0.62
        draw.rounded_rectangle(
            [left + (advance - bar_w) / 2, cy - bar_h / 2, left + (advance + bar_w) / 2, cy + bar_h / 2],
            radius=bar_h / 2, fill=fill)


def draw_centered(canvas, text, f, y, fill, shadow=True):
    draw = ImageDraw.Draw(canvas)
    x = (W - draw.textlength(text, font=f)) / 2
    if shadow:
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        draw_text_line(ImageDraw.Draw(layer), text, f, x, y + 6, (10, 0, 30, 110))
        canvas.alpha_composite(layer.filter(ImageFilter.GaussianBlur(10)))
        draw = ImageDraw.Draw(canvas)
    draw_text_line(draw, text, f, x, y, fill)


def star_points(cx, cy, r):
    """Étincelle à 4 branches (comme le sparkles des pastilles Premium de l'app)."""
    pts = []
    for i in range(8):
        a = math.pi / 4 * i - math.pi / 2
        rr = r if i % 2 == 0 else r * 0.32
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return pts


def premium_pill(canvas, y):
    f = font(SANS, 38, "Bold")
    label = "PREMIUM"
    spacing = 6
    draw = ImageDraw.Draw(canvas)
    text_w = sum(draw.textlength(c, font=f) + spacing for c in label) - spacing
    pill_w, pill_h = int(text_w + 150), 84
    x0 = (W - pill_w) // 2

    pill = Image.new("RGBA", (pill_w, pill_h), (0, 0, 0, 0))
    grad = Image.new("RGB", (pill_w, 1))
    gp = grad.load()
    for x in range(pill_w):
        t = x / (pill_w - 1)
        gp[x, 0] = tuple(round(GOLD_LIGHT[i] + (GOLD_WARM[i] - GOLD_LIGHT[i]) * t) for i in range(3))
    pill.paste(grad.resize((pill_w, pill_h)), (0, 0), rounded_mask((pill_w, pill_h), pill_h // 2))

    shadow = Image.new("RGBA", (pill_w + 200, pill_h + 200), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([100, 110, 100 + pill_w, 110 + pill_h], radius=pill_h // 2, fill=(255, 170, 40, 120))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(28)), (x0 - 100, y - 100))
    canvas.alpha_composite(pill, (x0, y))

    d = ImageDraw.Draw(canvas)
    d.polygon(star_points(x0 + 62, y + pill_h / 2, 22), fill=GOLD_TEXT)
    tx = x0 + 100
    ty = y + (pill_h - f.size) / 2 - 4
    for c in label:
        d.text((tx, ty), c, font=f, fill=GOLD_TEXT)
        tx += d.textlength(c, font=f) + spacing


def phone(canvas, raw_path):
    """Capture du simulateur dans un cadre titane, ancrée en bas (le bas du cadre déborde)."""
    shot = Image.open(raw_path).convert("RGB")
    assert shot.size == (W, H), f"{raw_path} : {shot.size}, attendu {(W, H)}"

    # Dynamic Island absente des captures du simulateur.
    ImageDraw.Draw(shot).rounded_rectangle(
        [ISLAND[0], ISLAND[1], ISLAND[0] + ISLAND[2], ISLAND[1] + ISLAND[3]], radius=ISLAND[3] // 2, fill=(0, 0, 0)
    )

    screen_w = PHONE_W - 2 * BEZEL
    screen_h = round(screen_w * H / W)
    phone_h = screen_h + 2 * BEZEL
    x0 = (W - PHONE_W) // 2
    outer_radius = SCREEN_RADIUS + BEZEL

    # Ombre portée
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [x0, PHONE_TOP + 40, x0 + PHONE_W, PHONE_TOP + 40 + phone_h], radius=outer_radius, fill=(8, 0, 24, 190)
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(50)))

    # Anneau titane : dégradé diagonal clair -> sombre -> clair
    ring = Image.new("RGB", (PHONE_W, phone_h))
    rp = ring.load()
    for y in range(phone_h):
        for x in range(PHONE_W):
            t = (math.sin((x / PHONE_W * 0.45 + y / phone_h * 0.55) * math.pi * 1.7) + 1) / 2
            v = round(92 - 62 * t)
            rp[x, y] = (v, v, v + 3)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    layer.paste(ring, (x0, PHONE_TOP), rounded_mask((PHONE_W, phone_h), outer_radius))
    canvas.alpha_composite(layer)

    # Lisière noire autour de l'écran, puis l'écran lui-même
    inner = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(inner).rounded_rectangle(
        [x0 + 5, PHONE_TOP + 5, x0 + PHONE_W - 6, PHONE_TOP + phone_h - 6], radius=outer_radius - 5, fill=(0, 0, 0, 255)
    )
    canvas.alpha_composite(inner)

    screen = shot.resize((screen_w, screen_h), Image.LANCZOS)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    layer.paste(screen, (x0 + BEZEL, PHONE_TOP + BEZEL), rounded_mask((screen_w, screen_h), SCREEN_RADIUS))
    canvas.alpha_composite(layer)


def make_slide(slide):
    canvas = background(PALETTES[slide["palette"]])
    ratio = contrast_check(canvas)
    if ratio < 4.5:
        print(f"ATTENTION {slide['out']} : contraste du texte blanc {ratio:.1f}:1 (< 4,5:1), assombrir le fond")
    probe = ImageDraw.Draw(canvas)

    title_font = fit_font(probe, slide["title"], SERIF, "Bold", W - 140, 112, 70)
    sub_font = fit_font(probe, [slide["subtitle"]], SANS, "Medium", W - 160, 46, 32)
    line_h = round(title_font.size * 1.12)
    pill_h, pill_gap = (84, 36) if slide.get("premium") else (0, 0)
    block_h = pill_h + pill_gap + line_h * len(slide["title"]) + 30 + sub_font.size

    # Bloc de texte centré verticalement dans la zone au-dessus du téléphone
    y = 70 + (PHONE_TOP - 70 - 40 - block_h) / 2
    if slide.get("premium"):
        premium_pill(canvas, int(y))
        y += pill_h + pill_gap
    for line in slide["title"]:
        draw_centered(canvas, line, title_font, y, (255, 255, 255))
        y += line_h
    draw_centered(canvas, slide["subtitle"], sub_font, y + 30, (255, 255, 255, 215), shadow=False)

    phone(canvas, os.path.join(RAW_DIR, slide["raw"]))
    out = os.path.join(HERE, slide["out"])
    canvas.convert("RGB").save(out, "PNG", optimize=True)
    print("OK", slide["out"])
    return out


def make_board(paths):
    """Planche : les 10 images côte à côte sur une seule ligne."""
    scale, gap, margin = 0.34, 44, 70
    tw, th = round(W * scale), round(H * scale)
    board_w = margin * 2 + len(paths) * tw + (len(paths) - 1) * gap
    board_h = margin * 2 + th
    board = Image.new("RGB", (board_w, board_h), (24, 20, 32))
    for i, path in enumerate(paths):
        thumb = Image.open(path).convert("RGB").resize((tw, th), Image.LANCZOS)
        x = margin + i * (tw + gap)
        mask = rounded_mask((tw, th), 34)
        board.paste(thumb, (x, margin), mask)
    out = os.path.join(HERE, "planche.png")
    board.save(out, "PNG", optimize=True)
    print("OK planche.png", board.size)


if __name__ == "__main__":
    make_board([make_slide(s) for s in SLIDES])
