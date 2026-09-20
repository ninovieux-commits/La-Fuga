/// Images des thèmes — table générée par `tool/gen_theme_assets.py`
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
const Map<String, ThemeImages> kThemeImages = {
  'medieval': ThemeImages(
    background: 'assets/themes/themebataille/fond.webp',
    board: 'assets/themes/themebataille/plateau.webp',
    pieces: {
      (PieceType.heritier, Camp.blanc):
          'assets/themes/themebataille/heritierblanc.webp',
      (PieceType.heritier, Camp.noir):
          'assets/themes/themebataille/heritiernoir.webp',
      (PieceType.nurse, Camp.blanc):
          'assets/themes/themebataille/nurseblanc.webp',
      (PieceType.nurse, Camp.noir):
          'assets/themes/themebataille/nursenoir.webp',
      (PieceType.soldat, Camp.blanc):
          'assets/themes/themebataille/soldatblanc.webp',
      (PieceType.soldat, Camp.noir):
          'assets/themes/themebataille/soldatnoir.webp',
      (PieceType.garde, Camp.blanc):
          'assets/themes/themebataille/gardeblanc.webp',
      (PieceType.garde, Camp.noir):
          'assets/themes/themebataille/gardenoir.webp',
      (PieceType.chevalier, Camp.blanc):
          'assets/themes/themebataille/chevalierblanc.webp',
      (PieceType.chevalier, Camp.noir):
          'assets/themes/themebataille/chevaliernoir.webp',
    },
    cornerRadius: 0.35,
  ),
  'fleur': ThemeImages(
    background: 'assets/themes/themefleurs/fond.webp',
    board: 'assets/themes/themefleurs/plateau.webp',
    pieces: {
      (PieceType.heritier, Camp.blanc):
          'assets/themes/themefleurs/heritierblanc.webp',
      (PieceType.heritier, Camp.noir):
          'assets/themes/themefleurs/heritiernoir.webp',
      (PieceType.nurse, Camp.blanc):
          'assets/themes/themefleurs/nurseblanc.webp',
      (PieceType.nurse, Camp.noir): 'assets/themes/themefleurs/nursenoir.webp',
      (PieceType.soldat, Camp.blanc):
          'assets/themes/themefleurs/soldatblanc.webp',
      (PieceType.soldat, Camp.noir):
          'assets/themes/themefleurs/soldatnoir.webp',
      (PieceType.garde, Camp.blanc):
          'assets/themes/themefleurs/gardeblanc.webp',
      (PieceType.garde, Camp.noir): 'assets/themes/themefleurs/gardenoir.webp',
      (PieceType.chevalier, Camp.blanc):
          'assets/themes/themefleurs/chevalierblanc.webp',
      (PieceType.chevalier, Camp.noir):
          'assets/themes/themefleurs/chevaliernoir.webp',
    },
  ),
  'insectes': ThemeImages(
    background: 'assets/themes/themeinsectes/fond.webp',
    board: 'assets/themes/themeinsectes/plateau.webp',
    pieces: {
      (PieceType.heritier, Camp.blanc):
          'assets/themes/themeinsectes/heritierblanc.webp',
      (PieceType.heritier, Camp.noir):
          'assets/themes/themeinsectes/heritiernoir.webp',
      (PieceType.nurse, Camp.blanc):
          'assets/themes/themeinsectes/nurseblanc.webp',
      (PieceType.nurse, Camp.noir):
          'assets/themes/themeinsectes/nursenoir.webp',
      (PieceType.soldat, Camp.blanc):
          'assets/themes/themeinsectes/carreeblanc.webp',
      (PieceType.soldat, Camp.noir):
          'assets/themes/themeinsectes/carreenoir.webp',
      (PieceType.garde, Camp.blanc):
          'assets/themes/themeinsectes/carreeblanc.webp',
      (PieceType.garde, Camp.noir):
          'assets/themes/themeinsectes/carreenoir.webp',
      (PieceType.chevalier, Camp.blanc):
          'assets/themes/themeinsectes/chevalierblanc.webp',
      (PieceType.chevalier, Camp.noir):
          'assets/themes/themeinsectes/chevaliernoir.webp',
    },
  ),
  'dragon': ThemeImages(
    background: 'assets/themes/themedragon/fond.webp',
    board: 'assets/themes/themedragon/plateau.webp',
    pieces: {
      (PieceType.heritier, Camp.blanc):
          'assets/themes/themedragon/heritier_blanc.webp',
      (PieceType.heritier, Camp.noir):
          'assets/themes/themedragon/heritier_noir.webp',
      (PieceType.nurse, Camp.blanc):
          'assets/themes/themedragon/nurse_blanc.webp',
      (PieceType.nurse, Camp.noir): 'assets/themes/themedragon/nurse_noir.webp',
      (PieceType.soldat, Camp.blanc):
          'assets/themes/themedragon/soldat_blanc.webp',
      (PieceType.soldat, Camp.noir):
          'assets/themes/themedragon/soldat_noir.webp',
      (PieceType.garde, Camp.blanc):
          'assets/themes/themedragon/garde_blanc.webp',
      (PieceType.garde, Camp.noir): 'assets/themes/themedragon/garde_noir.webp',
      (PieceType.chevalier, Camp.blanc):
          'assets/themes/themedragon/chevalier_blanc.webp',
      (PieceType.chevalier, Camp.noir):
          'assets/themes/themedragon/chevalier_noir.webp',
    },
  ),
  'deepgrey': ThemeImages(
    background: 'assets/themes/theme_deepgrey/fond.webp',
    board: 'assets/themes/theme_deepgrey/plateau.webp',
  ),
};

/// Images d'un thème, ou `null` s'il se dessine en géométrique.
ThemeImages? imagesFor(String theme) => kThemeImages[theme];
