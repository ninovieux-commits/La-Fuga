#!/usr/bin/env python3
"""Prépare les dessins d'instruments pour l'aperçu des réglages.

Les images d'origine sont des pictogrammes gris foncé sur fond blanc. Posées
telles quelles sur l'écran des réglages, qui est sombre, elles feraient un
carré blanc. On en tire donc un PNG BLANC sur fond TRANSPARENT, dont la
forme vient de l'obscurité du pixel : l'application le teinte ensuite à la
couleur du thème, et il suit le décor au lieu de le trouer.

Usage : python3 tool/gen_instruments.py <dossier_source>
        python3 tool/gen_instruments.py <image> <nom> [dossier]

La première forme prend un dossier contenant un fichier par instrument,
nommé comme lui : piano.jpg, orgue.jpg, guitare.jpg, cloche.jpg,
xylophone.jpg, harpe.jpg, choeur.jpg.

La seconde prépare UN pictogramme isolé — le drapeau de la touche d'abandon,
par exemple — selon la même recette. Elle le ROGNE d'abord sur son sujet :
une vignette d'instrument est déjà cadrée, une image trouvée ailleurs a
souvent du vide autour, et un carré centré y couperait le dessin au lieu de
le cadrer.
"""
import os
import sys

from PIL import Image

TAILLE = 192  # trois fois la taille affichée : net sur tous les écrans
DEST = 'assets/instruments'


def prepare(src, dest, rogne_au_sujet=False):
    im = Image.open(src).convert('L')
    if rogne_au_sujet:
        # Le sujet, c'est ce qui est SOMBRE. On prend sa boîte, on l'élargit
        # un peu pour ne pas coller aux bords, et on la rend carrée : le
        # dessin garde ses proportions.
        sujet = im.point(lambda v: 255 if v < 200 else 0).getbbox()
        if sujet:
            x0, y0, x1, y1 = sujet
            cote = max(x1 - x0, y1 - y0)
            marge = int(cote * 0.06)
            cote += 2 * marge
            cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
            im = im.crop((cx - cote // 2, cy - cote // 2,
                          cx + cote // 2, cy + cote // 2))
    else:
        # Carré centré : une vignette d'instrument est déjà cadrée.
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

    # LE PALIER DE LA FORME DOIT ÊTRE 255, SANS QUOI LE DESSIN EST SALE.
    #
    # Un pictogramme est une forme pleine : son intérieur est tout entier à
    # la même opacité. Le seuil ci-dessus (229) ne la saturait que si le
    # dessin d'origine était presque noir ; sur les neuf dessins des touches,
    # l'intérieur tombait entre 216 et 229 et y restait. À l'écran, la touche
    # superpose le dessin teinté sur une copie noire et dilatée qui fait le
    # contour : un dessin à 86 % laisse passer ce noir, et la forme se salit.
    # Nino : « le problème c'est que c'est mal fait... j'aimerais que ça soit
    # plus net. »
    #
    # On remet donc le palier — l'opacité la plus répandue — à 255, par une
    # règle de trois : le bord garde sa pente, proportionnellement. Sans
    # palier franc, le dessin est en dégradé et on n'y touche pas : l'étirer
    # l'abîmerait.
    dessines = [v for v in alpha if v > 0]
    if dessines:
        compte = [0] * 256
        for v in dessines:
            compte[v] += 1
        palier = max(range(1, 256), key=lambda v: compte[v])
        if compte[palier] >= 0.2 * len(dessines) and palier < 255:
            # Et on RAIDIT la pente du bord : l'agrandissement de Lanczos
            # ci-dessus étale la transition sur plusieurs pixels, et c'est
            # cette rampe molle que la dilatation change en halo au lieu d'un
            # contour. Resserrée autour de la moitié, elle garde son
            # anticrénelage et le contour redevient une ligne.
            def net(v):
                v = min(255, 255.0 * v / palier)
                x = (v / 255.0 - 0.5) * 2.2 + 0.5
                return max(0, min(255, int(round(255 * x))))

            alpha = [net(v) for v in alpha]

    out = Image.new('RGBA', (TAILLE, TAILLE), (255, 255, 255, 0))
    out.putalpha(Image.new('L', (TAILLE, TAILLE)))
    masque = Image.new('L', (TAILLE, TAILLE))
    masque.putdata(alpha)
    blanc = Image.new('RGBA', (TAILLE, TAILLE), (255, 255, 255, 255))
    blanc.putalpha(masque)
    # Le format suit l'extension : les vignettes d'instruments sont en PNG,
    # et tout ce qui vit dans `assets/images` est en WebP SANS PERTE —
    # `theme_assets_test.dart` refuse les PNG oubliés dans ces dossiers-là.
    if dest.lower().endswith('.webp'):
        blanc.save(dest, 'WEBP', lossless=True, quality=100, method=6)
    else:
        blanc.save(dest, 'PNG', optimize=True)
    pleins = sum(1 for a in alpha if a > 0)
    return 100.0 * pleins / (TAILLE * TAILLE)


def main():
    if len(sys.argv) == 4 or (len(sys.argv) == 3 and
                              os.path.isfile(sys.argv[1])):
        src, nom = sys.argv[1], sys.argv[2]
        dossier = sys.argv[3] if len(sys.argv) == 4 else DEST
        os.makedirs(dossier, exist_ok=True)
        ext = '.webp' if 'images' in dossier.split(os.sep) else '.png'
        dest = os.path.join(dossier, nom + ext)
        part = prepare(src, dest, rogne_au_sujet=True)
        print('%-10s %5.1f %% de la vignette dessinée -> %s'
              % (nom, part, dest))
        return 0
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
