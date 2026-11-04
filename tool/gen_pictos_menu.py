#!/usr/bin/env python3
"""Fabrique les deux dessins qui manquaient au menu : le podium et Deep Grey.

Les quatre grosses touches du menu portent un symbole, comme en partie :
`chat.webp` existait déjà pour « conversations », il fallait les deux autres.
Nino : « je t'ai joint le nouveau symbole pour classement » — c'est le podium,
qu'on DÉCALQUE de son image ; et « pour la touche de Deep Grey je voudrais
avoir la silhouette exacte de l'image de profil de deepgrey comme symbole » —
c'est son portrait, dont le canal alpha EST la silhouette.

Un dessin de touche est, comme ses huit voisins : 192 × 192, BLANC sur fond
transparent (c'est le thème qui le teinte), tenant dans un carré de 172 pour
garder la marge de 10 que tous ont, et centré sur sa boîte.

Usage : python3 tool/gen_pictos_menu.py <podium_source.jpeg>
"""
import sys

from PIL import Image

COTE = 192
MARGE = 10
DEDANS = COTE - 2 * MARGE  # 172

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


def silhouette_deepgrey():
    """La silhouette EXACTE du portrait de Deep Grey.

    Nino : « pour la touche de Deep Grey je voudrais avoir la silhouette
    exacte de l'image de profil de deepgrey comme symbole. » Le portrait est
    deja detoure — fond transparent, figure opaque : sa silhouette est donc
    son canal alpha, couronne comprise, et il n'y a rien a decalquer. On la
    rend franche (tout ou rien au-dessus de la moitie) pour que le trait noir
    du picto tombe net plutot que de baver dans le degrade du bord.
    """
    portrait = Image.open('assets/images/deepgrey.webp').convert('RGBA')
    alpha = portrait.split()[3].point(lambda v: 255 if v >= 128 else 0)
    return blanc_sur_transparent(alpha)


def ecrire(image, chemin):
    image.save(chemin, lossless=True, method=6, exact=True)
    print(chemin, image.size, 'bbox', image.split()[3].getbbox())


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    ecrire(podium(sys.argv[1]), 'assets/images/podium.webp')
    ecrire(silhouette_deepgrey(), 'assets/images/deepgrey_silhouette.webp')


if __name__ == '__main__':
    main()
