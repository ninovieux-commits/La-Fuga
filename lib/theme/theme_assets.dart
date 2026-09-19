/// Images des thèmes — table générée par `tool/gen_theme_assets.py`
/// depuis les fichiers réellement présents dans `assets/themes/`.
///
/// Kivy sonde le disque à l'exécution et accepte deux conventions de nommage
/// (`heritierblanc.png` et `heritier_blanc.png`). En Flutter les assets sont
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
    background: 'assets/themes/themebataille/fond.png',
    board: 'assets/themes/themebataille/plateau.png',
    pieces: {
      (PieceType.heritier, Camp.blanc):
          'assets/themes/themebataille/heritierblanc.png',
      (PieceType.heritier, Camp.noir):
          'assets/themes/themebataille/heritiernoir.png',
      (PieceType.nurse, Camp.blanc):
          'assets/themes/themebataille/nurseblanc.png',
      (PieceType.nurse, Camp.noir): 'assets/themes/themebataille/nursenoir.png',
      (PieceType.soldat, Camp.blanc):
          'assets/themes/themebataille/soldatblanc.png',
      (PieceType.soldat, Camp.noir):
          'assets/themes/themebataille/soldatnoir.png',
      (PieceType.garde, Camp.blanc):
          'assets/themes/themebataille/gardeblanc.png',
      (PieceType.garde, Camp.noir): 'assets/themes/themebataille/gardenoir.png',
      (PieceType.chevalier, Camp.blanc):
          'assets/themes/themebataille/chevalierblanc.png',
      (PieceType.chevalier, Camp.noir):
          'assets/themes/themebataille/chevaliernoir.png',
    },
    cornerRadius: 0.35,
  ),
  'fleur': ThemeImages(
    background: 'assets/themes/themefleurs/fond.png',
    board: 'assets/themes/themefleurs/plateau.png',
    pieces: {
      (PieceType.heritier, Camp.blanc):
          'assets/themes/themefleurs/heritierblanc.png',
      (PieceType.heritier, Camp.noir):
          'assets/themes/themefleurs/heritiernoir.png',
      (PieceType.nurse, Camp.blanc): 'assets/themes/themefleurs/nurseblanc.png',
      (PieceType.nurse, Camp.noir): 'assets/themes/themefleurs/nursenoir.png',
      (PieceType.soldat, Camp.blanc):
          'assets/themes/themefleurs/soldatblanc.png',
      (PieceType.soldat, Camp.noir): 'assets/themes/themefleurs/soldatnoir.png',
      (PieceType.garde, Camp.blanc): 'assets/themes/themefleurs/gardeblanc.png',
      (PieceType.garde, Camp.noir): 'assets/themes/themefleurs/gardenoir.png',
      (PieceType.chevalier, Camp.blanc):
          'assets/themes/themefleurs/chevalierblanc.png',
      (PieceType.chevalier, Camp.noir):
          'assets/themes/themefleurs/chevaliernoir.png',
    },
  ),
  'insectes': ThemeImages(
    background: 'assets/themes/themeinsectes/fond.png',
    board: 'assets/themes/themeinsectes/plateau.png',
    pieces: {
      (PieceType.heritier, Camp.blanc):
          'assets/themes/themeinsectes/heritierblanc.png',
      (PieceType.heritier, Camp.noir):
          'assets/themes/themeinsectes/heritiernoir.png',
      (PieceType.nurse, Camp.blanc):
          'assets/themes/themeinsectes/nurseblanc.png',
      (PieceType.nurse, Camp.noir): 'assets/themes/themeinsectes/nursenoir.png',
      (PieceType.soldat, Camp.blanc):
          'assets/themes/themeinsectes/carreeblanc.png',
      (PieceType.soldat, Camp.noir):
          'assets/themes/themeinsectes/carreenoir.png',
      (PieceType.garde, Camp.blanc):
          'assets/themes/themeinsectes/carreeblanc.png',
      (PieceType.garde, Camp.noir):
          'assets/themes/themeinsectes/carreenoir.png',
      (PieceType.chevalier, Camp.blanc):
          'assets/themes/themeinsectes/chevalierblanc.png',
      (PieceType.chevalier, Camp.noir):
          'assets/themes/themeinsectes/chevaliernoir.png',
    },
  ),
  'dragon': ThemeImages(
    background: 'assets/themes/themedragon/fond.png',
    board: 'assets/themes/themedragon/plateau.png',
    pieces: {
      (PieceType.heritier, Camp.blanc):
          'assets/themes/themedragon/heritier_blanc.png',
      (PieceType.heritier, Camp.noir):
          'assets/themes/themedragon/heritier_noir.png',
      (PieceType.nurse, Camp.blanc):
          'assets/themes/themedragon/nurse_blanc.png',
      (PieceType.nurse, Camp.noir): 'assets/themes/themedragon/nurse_noir.png',
      (PieceType.soldat, Camp.blanc):
          'assets/themes/themedragon/soldat_blanc.png',
      (PieceType.soldat, Camp.noir):
          'assets/themes/themedragon/soldat_noir.png',
      (PieceType.garde, Camp.blanc):
          'assets/themes/themedragon/garde_blanc.png',
      (PieceType.garde, Camp.noir): 'assets/themes/themedragon/garde_noir.png',
      (PieceType.chevalier, Camp.blanc):
          'assets/themes/themedragon/chevalier_blanc.png',
      (PieceType.chevalier, Camp.noir):
          'assets/themes/themedragon/chevalier_noir.png',
    },
  ),
  'deepgrey': ThemeImages(
    background: 'assets/themes/theme_deepgrey/fond.png',
    board: 'assets/themes/theme_deepgrey/plateau.png',
  ),
};

/// Images d'un thème, ou `null` s'il se dessine en géométrique.
ThemeImages? imagesFor(String theme) => kThemeImages[theme];
