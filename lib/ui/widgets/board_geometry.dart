/// Géométrie du plateau — portage de `_geom`, `_row_to_y`, `_col_to_x` et
/// `_pixel_to_cell` (BoardWidget, main.py).
///
/// ⚠️ Kivy place l'origine en bas à gauche avec Y vers le haut ; Flutter la
/// place en haut à gauche avec Y vers le bas. Les formules ne sont donc pas
/// recopiées telles quelles : on raisonne en **index de rangée depuis le haut
/// de la zone dessinée**, ce qui est indépendant du sens de l'axe.
library;

import 'dart:ui';

import '../../engine/board.dart';

/// Conversion entre cases de jeu et pixels écran.
///
/// Le plateau occupe toute la largeur : la taille de case est calée dessus.
/// Les 8 rangées jouables plus les 2 zones de ralliement font [kExtRows] cases
/// de haut ; si cela dépasse la hauteur allouée, les zones de ralliement
/// débordent volontairement dans les cadres d'information.
///
/// Quand [flipped] est vrai, les Blancs sont en bas. Quand il est faux (vue du
/// joueur Noir), le plateau est tourné à 180° comme aux échecs : colonnes
/// **et** rangées sont inversées.
final class BoardGeometry {
  BoardGeometry({required this.size, required this.flipped})
    : cellSize = size.width / kCols,
      originX = 0,
      originY = (size.height - (size.width / kCols) * kExtRows) / 2;

  final Size size;
  final bool flipped;

  /// Côté d'une case, en pixels.
  final double cellSize;

  final double originX;

  /// Haut de la zone dessinée (zones de ralliement comprises).
  final double originY;

  double get boardHeight => cellSize * kExtRows;

  /// Index de la rangée depuis le haut de la zone dessinée, de 0 à 9.
  ///
  /// Blancs en bas : de haut en bas `[8, 7, 6, …, 0, -1]`.
  /// Blancs en haut : de haut en bas `[-1, 0, 1, …, 7, 8]`.
  int rowToIndex(int row) {
    if (flipped) {
      if (row >= 8) return 0;
      if (row <= -1) return 9;
      return 8 - row;
    }
    if (row <= -1) return 0;
    if (row >= 8) return 9;
    return row + 1;
  }

  /// Rangée de jeu correspondant à un index depuis le haut.
  int indexToRow(int index) {
    if (flipped) {
      if (index == 0) return 8;
      if (index == 9) return -1;
      return 8 - index;
    }
    if (index == 0) return -1;
    if (index == 9) return 8;
    return index - 1;
  }

  /// Ordonnée écran du **haut** d'une rangée.
  double rowToY(int row) => originY + rowToIndex(row) * cellSize;

  /// Abscisse écran du bord gauche d'une colonne.
  double colToX(int col) {
    final screenCol = flipped ? col : (kCols - 1 - col);
    return originX + screenCol * cellSize;
  }

  /// Rectangle écran d'une case.
  Rect cellRect(int col, int row) =>
      Rect.fromLTWH(colToX(col), rowToY(row), cellSize, cellSize);

  /// Centre écran d'une case.
  Offset cellCenter(int col, int row) => cellRect(col, row).center;

  /// Rectangle écran de la zone de ralliement d'un camp
  /// (`row == 8` pour les Blancs, `row == -1` pour les Noirs).
  Rect rallyRect(int row) {
    final cols = kRally.toList()..sort();
    final left = colToX(flipped ? cols.first : cols.last);
    return Rect.fromLTWH(left, rowToY(row), cellSize * cols.length, cellSize);
  }

  /// Case correspondant à un point de l'écran, ou `null` en dehors.
  ///
  /// Renvoie une case de ralliement (`row == -1` ou `8`) quand le point tombe
  /// dans l'une des deux bandes, et seulement sur les colonnes concernées.
  Cell? pixelToCell(Offset p) {
    if (cellSize <= 0) return null;
    final screenCol = ((p.dx - originX) / cellSize).floor();
    if (screenCol < 0 || screenCol >= kCols) return null;
    final col = flipped ? screenCol : (kCols - 1 - screenCol);

    final relY = p.dy - originY;
    if (relY < 0 || relY >= kExtRows * cellSize) return null;
    final index = (relY / cellSize).floor().clamp(0, kExtRows - 1);
    final row = indexToRow(index);

    // Les zones de ralliement n'existent que sur les colonnes centrales.
    if ((row < 0 || row >= kRows) && !kRally.contains(col)) return null;
    return Cell(col, row);
  }
}
