"""Convertit les images du jeu en WebP **sans perte**.

Un PNG réoptimisé ne gagne que ~2 % : le gain vient du changement de format.
En WebP sans perte, les pixels sont strictement identiques — l'affichage ne
change pas d'un cheveu — et les fichiers pèsent environ 40 % de moins.

Chaque conversion est VÉRIFIÉE : on relit le WebP produit et on compare ses
pixels à ceux du PNG d'origine. Un fichier qui ne correspond pas n'est pas
remplacé.

Les fichiers d'origine du dépôt Kivy ne sont pas touchés : on ne convertit
que la copie de ce dépôt-ci.

Usage : python3 tool/to_webp.py assets/themes assets/logos assets/images
"""

import os
import sys

from PIL import Image, ImageChops


def convert(path: str) -> tuple[int, int]:
    """Convertit un PNG en WebP sans perte. Renvoie (avant, après) en octets."""
    source = Image.open(path).convert("RGBA")
    target = os.path.splitext(path)[0] + ".webp"
    source.save(target, lossless=True, method=6, exact=True)

    # Vérification : les pixels doivent être identiques, sinon on renonce.
    check = Image.open(target).convert("RGBA")
    if check.size != source.size or ImageChops.difference(source, check).getbbox():
        os.remove(target)
        raise SystemExit(f"pixels différents après conversion : {path}")

    before, after = os.path.getsize(path), os.path.getsize(target)
    os.remove(path)
    return before, after


def main() -> None:
    total_before = total_after = 0
    count = 0
    for folder in sys.argv[1:]:
        for dirpath, _, names in os.walk(folder):
            for name in sorted(names):
                if not name.endswith(".png"):
                    continue
                before, after = convert(os.path.join(dirpath, name))
                total_before += before
                total_after += after
                count += 1
    gain = 100 * (1 - total_after / total_before) if total_before else 0
    print(
        f"{count} images : {total_before / 1e6:.1f} Mo -> "
        f"{total_after / 1e6:.1f} Mo ({gain:.0f} % de moins), pixels identiques"
    )


if __name__ == "__main__":
    main()
