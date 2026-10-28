#!/usr/bin/env python3
"""Rend les pictogrammes OPAQUES, et donc nets.

Un pictogramme est une forme pleine : son intérieur devrait être tout entier
à 255 d'opacité, et seul son bord porter des valeurs intermédiaires. Les
neuf dessins des touches avaient un intérieur à 216-229 — le noir du dessin
d'origine n'était pas tout à fait noir, et le seuil de saturation du
générateur (229) ne se déclenchait jamais.

À l'écran, cela se voyait : la touche superpose le dessin TEINTÉ sur une
copie NOIRE et dilatée, qui fait le contour. Un dessin à 86 % laisse passer
le noir d'en dessous, et la forme se salit au lieu de se détacher. Nino :
« le problème c'est que c'est mal fait... j'aimerais que ça soit plus net. »

On remet donc le palier à 255, par une simple règle de trois sur l'alpha, et
on RAIDIT la pente du bord : le dessin est passé par un agrandissement de
Lanczos, qui étale la transition sur plusieurs pixels, et c'est cette rampe
molle que la dilatation transforme en halo au lieu d'un contour. Resserrée
autour de la moitié, elle garde son anticrénelage — le bord reste lisse —
mais le contour redevient une ligne. Le dessin ne bouge pas d'un pixel.

C'est une RÉPARATION, applicable aux dessins déjà fabriqués ; le générateur
`gen_instruments.py` ne produit plus ce défaut.

Usage : python3 tool/durcir_pictos.py <image.webp> [autres...]
"""
import sys

from PIL import Image

# En deçà, la forme n'a pas de palier franc : c'est un dessin en dégradé, et
# l'étirer l'abîmerait. On n'y touche pas.
PART_MINIMALE = 0.20

# De combien on resserre la rampe du bord. Plus haut, le bord redeviendrait
# un escalier ; plus bas, le contour reste mou.
RAIDEUR = 2.2


def raidit(v):
    """La rampe du bord, resserrée autour de la moitié."""
    x = (v / 255.0 - 0.5) * RAIDEUR + 0.5
    return max(0, min(255, int(round(255 * x))))


def palier_de(alpha):
    """L'opacité la plus répandue parmi les pixels dessinés, et sa part."""
    hist = alpha.histogram()
    dessines = sum(hist[1:])
    if not dessines:
        return None, 0.0
    valeur = max(range(1, 256), key=lambda v: hist[v])
    return valeur, hist[valeur] / dessines


def durcir(chemin):
    im = Image.open(chemin).convert('RGBA')
    r, g, b, a = im.split()
    valeur, part = palier_de(a)
    if valeur is None:
        return '%s : vide, laissé tel quel' % chemin
    if part < PART_MINIMALE:
        return '%s : pas de palier (%.0f %%), laissé tel quel' % (
            chemin, 100 * part)
    if valeur == 255:
        return '%s : déjà opaque' % chemin
    table = [raidit(min(255, int(round(255.0 * v / valeur))))
             for v in range(256)]
    dur = Image.merge('RGBA', (r, g, b, a.point(table)))
    dur.save(chemin, 'WEBP', lossless=True, quality=100, method=6)
    return '%s : palier %d -> 255, bord raidi (%.0f %% du dessin)' % (
        chemin, valeur, 100 * part)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    for chemin in sys.argv[1:]:
        print(durcir(chemin))
    return 0


if __name__ == '__main__':
    sys.exit(main())
