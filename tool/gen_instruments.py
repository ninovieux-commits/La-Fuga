#!/usr/bin/env python3
"""Prépare les dessins d'instruments pour l'aperçu des réglages.

Les images d'origine sont des pictogrammes gris foncé sur fond blanc. Posées
telles quelles sur l'écran des réglages, qui est sombre, elles feraient un
carré blanc. On en tire donc un PNG BLANC sur fond TRANSPARENT, dont la
forme vient de l'obscurité du pixel : l'application le teinte ensuite à la
couleur du thème, et il suit le décor au lieu de le trouer.

Usage : python3 tool/gen_instruments.py <dossier_source>

Le dossier source contient un fichier par instrument, nommé comme lui :
piano.jpg, orgue.jpg, guitare.jpg, cloche.jpg, xylophone.jpg, harpe.jpg,
choeur.jpg.
"""
import os
import sys

from PIL import Image

TAILLE = 192  # trois fois la taille affichée : net sur tous les écrans
DEST = 'assets/instruments'


def prepare(src, dest):
    im = Image.open(src).convert('L')
    # Carré, puis à la bonne taille.
    cote = min(im.size)
    g = (im.width - cote) // 2, (im.height - cote) // 2
    im = im.crop((g[0], g[1], g[0] + cote, g[1] + cote))
    im = im.resize((TAILLE, TAILLE), Image.LANCZOS)

    # L'alpha vient de l'obscurité, et on étire le contraste : le fond de ces
    # images n'est pas blanc pur mais légèrement gris, et sans cet étirement
    # il resterait un voile sur toute la vignette.
    pixels = list(im.getdata())
    sombre, clair = min(pixels), max(pixels)
    etendue = max(1, clair - sombre)
    alpha = []
    for v in pixels:
        a = 255 - int(round(255 * (v - sombre) / etendue))
        # On écrase le reste du fond, et on sature la forme.
        if a < 26:
            a = 0
        elif a > 229:
            a = 255
        alpha.append(a)

    out = Image.new('RGBA', (TAILLE, TAILLE), (255, 255, 255, 0))
    out.putalpha(Image.new('L', (TAILLE, TAILLE)))
    masque = Image.new('L', (TAILLE, TAILLE))
    masque.putdata(alpha)
    blanc = Image.new('RGBA', (TAILLE, TAILLE), (255, 255, 255, 255))
    blanc.putalpha(masque)
    blanc.save(dest, 'PNG', optimize=True)
    pleins = sum(1 for a in alpha if a > 0)
    return 100.0 * pleins / (TAILLE * TAILLE)


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    source = sys.argv[1]
    os.makedirs(DEST, exist_ok=True)
    fait = 0
    for f in sorted(os.listdir(source)):
        nom, ext = os.path.splitext(f)
        if ext.lower() not in ('.jpg', '.jpeg', '.png'):
            continue
        part = prepare(os.path.join(source, f),
                       os.path.join(DEST, nom + '.png'))
        print('%-10s %5.1f %% de la vignette dessinée' % (nom, part))
        fait += 1
    print('%d dessins préparés dans %s' % (fait, DEST))
    return 0


if __name__ == '__main__':
    sys.exit(main())
