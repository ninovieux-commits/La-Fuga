#!/usr/bin/env python3
"""Fabrique les deux dessins qui manquaient au menu : le podium et le buste.

Les quatre grosses touches du menu portent un symbole, comme en partie :
`chat.webp` existait déjà pour « conversations », il fallait les deux autres.
Nino : « je t'ai joint le nouveau symbole pour classement » — c'est le podium,
qu'on DÉCALQUE de son image ; et pour « affronter Deep Grey » il a dessiné une
silhouette, qu'on TRACE, parce qu'un dessin géométrique reste net là où un
décalque de photo bave.

Un dessin de touche est, comme ses huit voisins : 192 × 192, BLANC sur fond
transparent (c'est le thème qui le teinte), tenant dans un carré de 172 pour
garder la marge de 10 que tous ont, et centré sur sa boîte.

Usage : python3 tool/gen_pictos_menu.py <podium_source.jpeg>
"""
import sys

from PIL import Image, ImageDraw

COTE = 192
MARGE = 10
DEDANS = COTE - 2 * MARGE  # 172
FIN = 4  # on dessine quatre fois trop grand, puis on réduit : bords lisses

# Le fond de l'image du podium est clair, la forme est d'un gris foncé, et
# les chiffres sont blancs À L'INTÉRIEUR de la forme. On prend donc pour
# opacité « à quel point c'est sombre » : les chiffres et le liseré
# redeviennent des TROUS, et le gris de la touche s'y voit — exactement comme
# les fenêtres de l'enveloppe.
SOMBRE = 100   # en deçà : plein
CLAIR = 165    # au-delà : rien


def blanc_sur_transparent(alpha):
    """Une image blanche dont l'opacité est [alpha], recadrée et centrée."""
    boite = alpha.getbbox()
    if boite is None:
        raise SystemExit('image vide')
    alpha = alpha.crop(boite)
    l, h = alpha.size
    k = DEDANS / max(l, h)
    alpha = alpha.resize((max(1, round(l * k)), max(1, round(h * k))), Image.LANCZOS)
    fond = Image.new('L', (COTE, COTE), 0)
    fond.paste(alpha, ((COTE - alpha.size[0]) // 2, (COTE - alpha.size[1]) // 2))
    plein = Image.new('RGBA', (COTE, COTE), (255, 255, 255, 0))
    plein.putalpha(fond)
    return plein


def podium(source):
    gris = Image.open(source).convert('L')
    alpha = gris.point(
        lambda v: 255 if v <= SOMBRE else (0 if v >= CLAIR else round(255 * (CLAIR - v) / (CLAIR - SOMBRE)))
    )
    return blanc_sur_transparent(alpha)


def buste():
    """Tête et épaules, comme sur le croquis : deux formes, un court écart."""
    d = DEDANS * FIN
    toile = Image.new('L', (d, d), 0)
    crayon = ImageDraw.Draw(toile)
    # La tête : un disque, dans le tiers haut.
    rayon = round(0.185 * d)
    cx, cy = d // 2, round(0.205 * d)
    crayon.ellipse([cx - rayon, cy - rayon, cx + rayon, cy + rayon], fill=255)
    # Les épaules : un rectangle aux deux coins hauts très arrondis, posé au
    # bas de la boîte. L'écart avec la tête laisse passer le trait noir entre
    # les deux, sans quoi la silhouette devient une seule masse illisible.
    haut = round(0.465 * d)
    cote = round(0.085 * d)
    crayon.rounded_rectangle(
        [cote, haut, d - cote, d], radius=round(0.34 * d), fill=255,
        corners=(True, True, False, False),
    )
    return blanc_sur_transparent(toile)


def ecrire(image, chemin):
    image.save(chemin, lossless=True, method=6, exact=True)
    print(chemin, image.size, 'bbox', image.split()[3].getbbox())


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    ecrire(podium(sys.argv[1]), 'assets/images/podium.webp')
    ecrire(buste(), 'assets/images/buste.webp')


if __name__ == '__main__':
    main()
