"""Génère lib/theme/theme_assets.dart depuis les fichiers réellement présents.

Les images sont en WebP sans perte (voir tool/to_webp.py) : pixels identiques
aux PNG du dépôt Kivy, fichiers 40 % plus légers.

Kivy sonde le disque à l'exécution et accepte deux conventions de nommage
(`heritierblanc` et `heritier_blanc`). En Flutter, les assets sont
déclarés à la compilation : on résout donc la table une fois pour toutes,
depuis les fichiers eux-mêmes.
"""
import os

# Thèmes à images complètes (pièces + fonds).
IMG_DIR = {
    "medieval": "themebataille",
    "fleur": "themefleurs",
    "insectes": "themeinsectes",
    "dragon": "themedragon",
}
# Thèmes n'ayant QUE des images de fond : leurs pièces restent dessinées.
BG_DIR = {"deepgrey": "theme_deepgrey"}

TYPES = {
    "heritier": "PieceType.heritier",
    "nurse": "PieceType.nurse",
    "soldat": "PieceType.soldat",
    "garde": "PieceType.garde",
    "chevalier": "PieceType.chevalier",
}
CAMPS = {"blanc": "Camp.blanc", "noir": "Camp.noir"}

# Filigrane dans un coin de certaines images : on arrondit les coins pour
# qu'il disparaisse et que la forme paraisse voulue.
WM_ROUND = {"medieval": 0.35}

root = "assets/themes"


def find(folder, base):
    """Cherche les deux conventions de nommage."""
    spaced = base.replace("blanc", "_blanc").replace("noir", "_noir")
    for name in (f"{base}.webp", f"{spaced}.webp"):
        if os.path.exists(os.path.join(root, folder, name)):
            return f"{root}/{folder}/{name}"
    return None


lines = ['''/// Images des thèmes — table générée par `tool/gen_theme_assets.py`
/// depuis les fichiers réellement présents dans `assets/themes/`.
///
/// Kivy sonde le disque à l'exécution et accepte deux conventions de nommage
/// (`heritierblanc` et `heritier_blanc`). En Flutter les assets sont
/// déclarés à la compilation : la table est donc résolue une fois pour toutes.
/// Ne pas modifier à la main — régénérer.
library;

import '../engine/piece.dart';

/// Images d'un thème.
final class ThemeImages {
  const ThemeImages({
    this.background,
    this.board,
    this.pieces = const {},
    this.cornerRadius = 0,
  });

  /// Fond du menu.
  final String? background;

  /// Image du plateau.
  final String? board;

  /// Image de chaque pièce, quand le thème en a.
  final Map<(PieceType, Camp), String> pieces;

  /// Arrondi des coins, en fraction du côté.
  ///
  /// Certaines images portent un filigrane dans un coin : l'arrondir le fait
  /// disparaître, et la forme paraît voulue. 0.5 donne un cercle complet.
  final double cornerRadius;

  /// Vrai si ce thème dessine ses pièces avec des images.
  bool get hasPieceImages => pieces.isNotEmpty;

  /// Vrai si ce thème a au moins une image de fond.
  bool get hasBackgrounds => background != null || board != null;
}

/// Images par thème. Un thème absent se dessine en rendu géométrique.
const Map<String, ThemeImages> kThemeImages = {''']

for theme, folder in list(IMG_DIR.items()) + list(BG_DIR.items()):
    bg = f"{root}/{folder}/fond.webp" if os.path.exists(f"{root}/{folder}/fond.webp") else None
    board = (
        f"{root}/{folder}/plateau.webp"
        if os.path.exists(f"{root}/{folder}/plateau.webp")
        else None
    )

    pieces = []
    if theme in IMG_DIR:
        for t, dart_t in TYPES.items():
            for c, dart_c in CAMPS.items():
                # Le thème insectes partage une seule image pour les carrées.
                base = "carree" if (theme == "insectes" and t in ("soldat", "garde")) else t
                path = find(folder, f"{base}{c}")
                if path:
                    pieces.append(f"    ({dart_t}, {dart_c}): '{path}',")

    lines.append(f"  '{theme}': ThemeImages(")
    if bg:
        lines.append(f"    background: '{bg}',")
    if board:
        lines.append(f"    board: '{board}',")
    if pieces:
        lines.append("    pieces: {")
        lines.extend(pieces)
        lines.append("    },")
    if theme in WM_ROUND:
        lines.append(f"    cornerRadius: {WM_ROUND[theme]},")
    lines.append("  ),")

lines.append("};")
lines.append("")
lines.append("/// Images d'un thème, ou `null` s'il se dessine en géométrique.")
lines.append("ThemeImages? imagesFor(String theme) => kThemeImages[theme];")

open("lib/theme/theme_assets.dart", "w", encoding="utf-8").write("\n".join(lines) + "\n")

total = sum(len(v.pieces) if hasattr(v, 'pieces') else 0 for v in [])
print("theme_assets.dart généré")
for theme, folder in list(IMG_DIR.items()) + list(BG_DIR.items()):
    n = sum(1 for t in TYPES for c in CAMPS
            if find(folder, ("carree" if (theme == "insectes" and t in ("soldat", "garde")) else t) + c))
    print(f"  {theme:10s} ({folder:15s}) : {n} images de pièces")
