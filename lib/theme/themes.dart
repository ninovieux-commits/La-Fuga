/// Les 17 thèmes de La Fuga — extraits tels quels du dictionnaire `THEMES`
/// de `main.py` par `tool/extracted/THEMES.json`. Ne pas modifier à la main :
/// régénérer depuis le JSON si le thème change côté Kivy.
library;

import 'dart:ui';

/// Épaisseur Flutter correspondant à un `Line(width: w)` de Kivy.
///
/// Kivy décale les bords de ±w de part et d'autre de l'axe : le trait fait
/// **2w** à l'écran, alors que Flutter prend l'épaisseur totale. Sans cette
/// conversion, tous les traits du jeu — contours des pièces, signes, grille,
/// cadres du dernier coup — paraissent deux fois trop fins.
double kivyLine(double kivyWidth) => kivyWidth * 2;

/// Palette d'un thème : 7 couleurs.
final class ThemePalette {
  const ThemePalette({
    required this.clair,
    required this.fonce,
    required this.clairDim,
    required this.fonceDim,
    required this.board,
    required this.menu,
    required this.grid,
  });

  /// Accent du camp Blanc.
  final Color clair;

  /// Accent du camp Noir.
  final Color fonce;

  /// Accent Blanc atténué (bandeau inactif).
  final Color clairDim;

  /// Accent Noir atténué.
  final Color fonceDim;

  /// Fond du plateau, quand le thème n'a pas d'image de plateau.
  final Color board;

  /// Fond des menus et écrans secondaires.
  final Color menu;

  /// Lignes de la grille.
  final Color grid;
}

/// Couleurs fixes, indépendantes du thème (cf. main.py).
abstract final class FugaColors {
  /// Corps des pièces blanches.
  static const Color whitePiece = Color.fromRGBO(245, 240, 219, 1);

  /// Corps des pièces noires.
  static const Color blackPiece = Color.fromRGBO(18, 18, 33, 1);

  /// Contour de la pièce sélectionnée.
  static const Color selection = Color.fromRGBO(255, 255, 0, 1);

  /// Contour des pièces du groupe sélectionné.
  static const Color groupSelection = Color.fromRGBO(255, 102, 255, 1);

  /// Contour d'une pièce immobilisée.
  static const Color immobile = Color.fromRGBO(255, 51, 51, 1);

  /// Gris des boutons.
  static const Color buttonGrey = Color.fromRGBO(89, 89, 89, 1);

  /// Contour par défaut d'une pièce blanche.
  static const Color whiteOutline = Color.fromRGBO(222, 222, 222, 1);

  /// Contour par défaut d'une pièce noire.
  static const Color blackOutline = Color.fromRGBO(51, 51, 84, 1);
}

/// Toutes les palettes, par identifiant de thème.
const Map<String, ThemePalette> kThemes = {
  'original': ThemePalette(
    clair: Color.fromRGBO(255, 140, 0, 1),
    fonce: Color.fromRGBO(0, 128, 255, 1),
    clairDim: Color.fromRGBO(115, 56, 0, 1),
    fonceDim: Color.fromRGBO(0, 56, 115, 1),
    board: Color.fromRGBO(140, 140, 140, 1),
    menu: Color.fromRGBO(199, 199, 199, 1),
    grid: Color.fromRGBO(112, 112, 112, 1),
  ),
  'foret': ThemePalette(
    clair: Color.fromRGBO(115, 199, 76, 1),
    fonce: Color.fromRGBO(33, 102, 33, 1),
    clairDim: Color.fromRGBO(56, 97, 38, 1),
    fonceDim: Color.fromRGBO(15, 51, 15, 1),
    board: Color.fromRGBO(107, 128, 102, 1),
    menu: Color.fromRGBO(158, 178, 153, 1),
    grid: Color.fromRGBO(82, 102, 76, 1),
  ),
  'ocean': ThemePalette(
    clair: Color.fromRGBO(89, 191, 242, 1),
    fonce: Color.fromRGBO(13, 64, 140, 1),
    clairDim: Color.fromRGBO(43, 94, 120, 1),
    fonceDim: Color.fromRGBO(5, 31, 69, 1),
    board: Color.fromRGBO(102, 122, 140, 1),
    menu: Color.fromRGBO(153, 173, 191, 1),
    grid: Color.fromRGBO(76, 97, 115, 1),
  ),
  'volcan': ThemePalette(
    clair: Color.fromRGBO(255, 166, 64, 1),
    fonce: Color.fromRGBO(166, 51, 0, 1),
    clairDim: Color.fromRGBO(122, 76, 31, 1),
    fonceDim: Color.fromRGBO(82, 26, 0, 1),
    board: Color.fromRGBO(133, 117, 107, 1),
    menu: Color.fromRGBO(189, 168, 153, 1),
    grid: Color.fromRGBO(107, 92, 82, 1),
  ),
  'hemo': ThemePalette(
    clair: Color.fromRGBO(242, 89, 89, 1),
    fonce: Color.fromRGBO(128, 13, 20, 1),
    clairDim: Color.fromRGBO(120, 43, 43, 1),
    fonceDim: Color.fromRGBO(64, 5, 10, 1),
    board: Color.fromRGBO(133, 112, 112, 1),
    menu: Color.fromRGBO(189, 158, 158, 1),
    grid: Color.fromRGBO(107, 87, 87, 1),
  ),
  'spatial': ThemePalette(
    clair: Color.fromRGBO(178, 115, 242, 1),
    fonce: Color.fromRGBO(76, 26, 128, 1),
    clairDim: Color.fromRGBO(89, 56, 120, 1),
    fonceDim: Color.fromRGBO(38, 13, 64, 1),
    board: Color.fromRGBO(122, 112, 138, 1),
    menu: Color.fromRGBO(173, 158, 189, 1),
    grid: Color.fromRGBO(97, 87, 112, 1),
  ),
  'imperial': ThemePalette(
    clair: Color.fromRGBO(217, 178, 76, 1),
    fonce: Color.fromRGBO(191, 191, 204, 1),
    clairDim: Color.fromRGBO(107, 89, 38, 1),
    fonceDim: Color.fromRGBO(94, 94, 102, 1),
    board: Color.fromRGBO(115, 41, 61, 1),
    menu: Color.fromRGBO(148, 61, 82, 1),
    grid: Color.fromRGBO(87, 26, 43, 1),
  ),
  'royal': ThemePalette(
    clair: Color.fromRGBO(217, 178, 76, 1),
    fonce: Color.fromRGBO(191, 191, 204, 1),
    clairDim: Color.fromRGBO(107, 89, 38, 1),
    fonceDim: Color.fromRGBO(94, 94, 102, 1),
    board: Color.fromRGBO(51, 71, 140, 1),
    menu: Color.fromRGBO(89, 107, 173, 1),
    grid: Color.fromRGBO(36, 51, 107, 1),
  ),
  'terre': ThemePalette(
    clair: Color.fromRGBO(204, 158, 107, 1),
    fonce: Color.fromRGBO(102, 66, 33, 1),
    clairDim: Color.fromRGBO(102, 79, 54, 1),
    fonceDim: Color.fromRGBO(51, 33, 15, 1),
    board: Color.fromRGBO(133, 112, 92, 1),
    menu: Color.fromRGBO(173, 148, 122, 1),
    grid: Color.fromRGBO(102, 82, 61, 1),
  ),
  'bonbon': ThemePalette(
    clair: Color.fromRGBO(255, 184, 217, 1),
    fonce: Color.fromRGBO(217, 56, 140, 1),
    clairDim: Color.fromRGBO(128, 92, 110, 1),
    fonceDim: Color.fromRGBO(107, 28, 69, 1),
    board: Color.fromRGBO(153, 122, 140, 1),
    menu: Color.fromRGBO(209, 173, 191, 1),
    grid: Color.fromRGBO(122, 92, 110, 1),
  ),
  'arcenciel': ThemePalette(
    clair: Color.fromRGBO(242, 140, 76, 1),
    fonce: Color.fromRGBO(76, 128, 217, 1),
    clairDim: Color.fromRGBO(153, 115, 102, 1),
    fonceDim: Color.fromRGBO(76, 102, 140, 1),
    board: Color.fromRGBO(184, 217, 242, 1),
    menu: Color.fromRGBO(199, 230, 250, 1),
    grid: Color.fromRGBO(140, 178, 217, 1),
  ),
  'etoile': ThemePalette(
    clair: Color.fromRGBO(255, 217, 51, 1),
    fonce: Color.fromRGBO(191, 153, 20, 1),
    clairDim: Color.fromRGBO(115, 102, 31, 1),
    fonceDim: Color.fromRGBO(76, 61, 10, 1),
    board: Color.fromRGBO(15, 15, 26, 1),
    menu: Color.fromRGBO(26, 26, 41, 1),
    grid: Color.fromRGBO(64, 59, 26, 1),
  ),
  'medieval': ThemePalette(
    clair: Color.fromRGBO(255, 140, 0, 1),
    fonce: Color.fromRGBO(0, 128, 255, 1),
    clairDim: Color.fromRGBO(115, 56, 0, 1),
    fonceDim: Color.fromRGBO(0, 56, 115, 1),
    board: Color.fromRGBO(107, 107, 112, 1),
    menu: Color.fromRGBO(107, 107, 112, 1),
    grid: Color.fromRGBO(76, 76, 82, 1),
  ),
  'fleur': ThemePalette(
    clair: Color.fromRGBO(242, 102, 115, 1),
    fonce: Color.fromRGBO(242, 178, 209, 1),
    clairDim: Color.fromRGBO(158, 82, 89, 1),
    fonceDim: Color.fromRGBO(166, 133, 148, 1),
    board: Color.fromRGBO(250, 224, 230, 1),
    menu: Color.fromRGBO(252, 235, 240, 1),
    grid: Color.fromRGBO(0, 0, 0, 1),
  ),
  'insectes': ThemePalette(
    clair: Color.fromRGBO(115, 178, 76, 1),
    fonce: Color.fromRGBO(51, 115, 46, 1),
    clairDim: Color.fromRGBO(76, 117, 51, 1),
    fonceDim: Color.fromRGBO(36, 76, 31, 1),
    board: Color.fromRGBO(217, 235, 204, 1),
    menu: Color.fromRGBO(230, 242, 219, 1),
    grid: Color.fromRGBO(0, 0, 0, 1),
  ),
  'dragon': ThemePalette(
    clair: Color.fromRGBO(180, 34, 34, 1),
    fonce: Color.fromRGBO(27, 69, 148, 1),
    clairDim: Color.fromRGBO(107, 20, 20, 1),
    fonceDim: Color.fromRGBO(15, 41, 89, 1),
    board: Color.fromRGBO(41, 26, 23, 1),
    menu: Color.fromRGBO(128, 128, 128, 1),
    grid: Color.fromRGBO(89, 51, 31, 1),
  ),
  'deepgrey': ThemePalette(
    clair: Color.fromRGBO(128, 128, 128, 1),
    fonce: Color.fromRGBO(128, 128, 128, 1),
    clairDim: Color.fromRGBO(64, 64, 64, 1),
    fonceDim: Color.fromRGBO(64, 64, 64, 1),
    board: Color.fromRGBO(128, 128, 128, 1),
    menu: Color.fromRGBO(184, 184, 184, 1),
    grid: Color.fromRGBO(102, 102, 102, 1),
  ),
};

/// Ordre d'affichage des thèmes — `THEME_ORDER` de Kivy. C'est celui des
/// sélecteurs, du composeur et du choix de photo.
const List<String> kThemeOrder = [
  'original',
  'foret',
  'ocean',
  'volcan',
  'hemo',
  'spatial',
  'imperial',
  'royal',
  'terre',
  'bonbon',
  'arcenciel',
  'etoile',
  'medieval',
  'fleur',
  'insectes',
  'dragon',
  'deepgrey',
];

/// Nom affiché de chaque thème.
const Map<String, String> kThemeLabels = {
  'original': 'Original',
  'foret': 'Forêt',
  'ocean': 'Océan',
  'volcan': 'Volcan',
  'hemo': 'Hémo',
  'spatial': 'Spatial',
  'imperial': 'Impérial',
  'royal': 'Royal',
  'terre': 'Terre',
  'bonbon': 'Bonbon',
  'arcenciel': 'Arc-en-ciel',
  'etoile': 'Étoile',
  'medieval': 'Médiéval',
  'fleur': 'Fleur',
  'insectes': 'Insectes',
  'dragon': 'Dragon',
  'deepgrey': 'Deep Grey',
};

/// Thème de repli quand un identifiant est inconnu.
const String kDefaultTheme = 'original';

/// Palette d'un thème, avec repli sur [kDefaultTheme].
ThemePalette paletteOf(String name) => kThemes[name] ?? kThemes[kDefaultTheme]!;
