"""Fabrique les icônes Android depuis les images du jeu.

Kivy les déclare dans `buildozer.spec` et laisse buildozer faire le travail :

    icon.filename            = icon.png        # icône classique (avant Android 8)
    icon.adaptive_foreground = icon_fg.png     # calque avant de l'icône adaptative
    icon.adaptive_background = icon_bg.png     # calque arrière (gris uni)
    android.add_resources    = icon_notif.png:drawable/notif_icon.png

Flutter n'a pas d'équivalent : il faut produire les fichiers à la main. Ce
script les fabrique aux tailles qu'Android attend, à partir des mêmes images.

  - icône adaptative : calque avant de 108 dp, fond de couleur unie ;
  - icône classique : 48 dp, pour les Android antérieurs à 8 ;
  - icône de notification : 24 dp, blanche sur fond transparent.

Usage : python3 tool/gen_android_icons.py
"""

import os

from PIL import Image

RES = "android/app/src/main/res"
SOURCES = "assets/images"

# Facteur d'échelle de chaque densité : 1 dp vaut tant de pixels.
DENSITIES = {
    "mdpi": 1,
    "hdpi": 1.5,
    "xhdpi": 2,
    "xxhdpi": 3,
    "xxxhdpi": 4,
}


def emit(image: Image.Image, folder: str, name: str, dp: int) -> None:
    """Écrit l'image à la taille voulue dans chaque densité."""
    for density, scale in DENSITIES.items():
        side = round(dp * scale)
        target = os.path.join(RES, f"{folder}-{density}")
        os.makedirs(target, exist_ok=True)
        resized = image.resize((side, side), Image.LANCZOS)
        resized.save(os.path.join(target, f"{name}.png"), optimize=True)


def background_color() -> str:
    """Couleur du calque arrière. L'image de Kivy est unie : on en garde la
    couleur plutôt que cinq copies d'un carré gris."""
    bg = Image.open(f"{SOURCES}/icon_bg.webp").convert("RGB")
    colors = bg.getcolors(maxcolors=1 << 24)
    if len(colors) != 1:
        raise SystemExit("icon_bg n'est plus uni : il faut un vrai calque.")
    r, g, b = colors[0][1]
    return f"#{r:02X}{g:02X}{b:02X}"


def main() -> None:
    # Icône classique (Android 7 et avant) : l'image carrée telle quelle.
    emit(Image.open(f"{SOURCES}/icon.webp").convert("RGBA"),
         "mipmap", "ic_launcher", 48)

    # Calque avant de l'icône adaptative : 108 dp, dont seuls les 72 dp
    # centraux sont toujours visibles — le logo de Kivy tient dans cette zone.
    emit(Image.open(f"{SOURCES}/icon_fg.webp").convert("RGBA"),
         "mipmap", "ic_launcher_foreground", 108)

    # Icône de notification : blanche sur fond transparent, 24 dp.
    emit(Image.open(f"{SOURCES}/icon_notif.webp").convert("RGBA"),
         "drawable", "notif_icon", 24)

    os.makedirs(f"{RES}/mipmap-anydpi-v26", exist_ok=True)
    with open(f"{RES}/mipmap-anydpi-v26/ic_launcher.xml", "w",
              encoding="utf-8") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background" />\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
            '</adaptive-icon>\n'
        )

    os.makedirs(f"{RES}/values", exist_ok=True)
    with open(f"{RES}/values/ic_launcher_background.xml", "w",
              encoding="utf-8") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<resources>\n'
            f'    <color name="ic_launcher_background">{background_color()}</color>\n'
            '</resources>\n'
        )

    print("icônes écrites dans", RES)


if __name__ == "__main__":
    main()
