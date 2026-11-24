/// Géométrie du plateau — portage de `_geom`, `_row_to_y`, `_col_to_x` et
/// `_pixel_to_cell` (BoardWidget, main.py).
///
/// ⚠️ Kivy place l'origine en bas à gauche avec Y vers le haut ; Flutter la
/// place en haut à gauche avec Y vers le bas. Les formules ne sont donc pas
/// recopiées telles quelles : on raisonne en **index de rangée depuis le haut
/// de la zone dessinée**, ce qui est indépendant du sens de l'axe.
library;

import 'dart:math' as math;
import 'dart:ui';

import '../../engine/board.dart';
import '../../engine/piece.dart';

/// Conversion entre cases de jeu et pixels écran.
///
/// LE PLATEAU PREND LA LARGEUR QUAND IL PEUT, ET LA HAUTEUR LE LIMITE SINON.
///
/// Huit rangées jouables plus deux zones de ralliement font [kExtRows] cases
/// de haut pour [kCols] de large : le plateau est donc dix septièmes plus
/// haut que large. La taille de case se calait sur la largeur seule, et sur
/// un téléphone cela tombe juste — les bandeaux cèdent au plateau ce qui lui
/// manque, et la place qu'il reçoit vaut exactement sa hauteur naturelle.
///
/// Sur une tablette, non. Nino : « sur tablette, l'écran n'a pas la même
/// forme et ça rend n'importe comment ». Plus large par rapport à sa hauteur,
/// elle donne au plateau une largeur dont la hauteur naturelle dépasse de
/// très loin la place disponible — bien plus que ce que les bandeaux peuvent
/// rendre —, et le plateau venait peindre par-dessus eux : le nom du joueur,
/// son chrono et ses touches disparaissaient sous les zones de ralliement.
///
/// La case vaut donc le plus petit des deux : un septième de la largeur, ou
/// un dixième de la hauteur. Le plateau est centré dans ce qui reste. Sur un
/// téléphone c'est la largeur qui gagne, au pixel près, et rien ne change.
///
/// Quand [flipped] est vrai, les Blancs sont en bas. Quand il est faux (vue du
/// joueur Noir), le plateau est tourné à 180° comme aux échecs : colonnes
/// **et** rangées sont inversées.
final class BoardGeometry {
  BoardGeometry({
    required this.size,
    required this.flipped,
    this.rall = Ralliements.standard,
    this.rangeeOuverte,
    this.ralliementsTouchables = false,
  }) : cellSize = _cote(size),
       originX = (size.width - _cote(size) * kCols) / 2,
       originY = (size.height - _cote(size) * kExtRows) / 2;

  /// Le côté d'une case : la largeur quand elle rentre, la hauteur sinon.
  ///
  /// Une hauteur infinie — une boîte qui ne contraint pas — redonne la
  /// largeur, c'est-à-dire ce que faisait la version d'avant.
  static double _cote(Size size) =>
      math.min(size.width / kCols, size.height / kExtRows);

  final Size size;
  final bool flipped;

  /// Les zones de ralliement de la position dessinée. Elles ne sont plus les
  /// mêmes d'une partie à l'autre, et la géométrie doit savoir où elles sont
  /// pour les peindre et pour savoir ce qu'un doigt touche.
  final Ralliements rall;

  /// Le camp dont on choisit la zone : toute sa rangée répond au doigt, y
  /// compris les colonnes qui ne rallient pas encore. Sans cela, on ne
  /// pourrait qu'en RETIRER.
  final Camp? rangeeOuverte;

  /// Dans le COMPOSEUR : les deux rangées de ralliement répondent au doigt,
  /// toujours, même là où rien ne rallie.
  ///
  /// Sans quoi une zone qu'on a vidée ne se rouvre jamais : il n'y aurait
  /// plus une seule case à toucher pour revenir dessus.
  final bool ralliementsTouchables;

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

  /// Le camp dont la zone de ralliement occupe cette rangée.
  static Camp campDeLaRangee(int row) => row >= kRows ? Camp.blanc : Camp.noir;

  /// Les rectangles écran de la zone de ralliement d'un camp
  /// (`row == 8` pour les Blancs, `row == -1` pour les Noirs).
  ///
  /// UN PAR BLOC DE COLONNES CONTIGUËS, et non un seul : une zone choisie
  /// peut être trouée — « rr-----  --r-r-- » — et un rectangle unique
  /// peindrait le vide entre les deux morceaux.
  List<Rect> rallyRects(int row) {
    final cols = rall.colonnes(campDeLaRangee(row));
    final rects = <Rect>[];
    var i = 0;
    while (i < cols.length) {
      var j = i;
      while (j + 1 < cols.length && cols[j + 1] == cols[j] + 1) {
        j++;
      }
      final gauche = colToX(flipped ? cols[i] : cols[j]);
      rects.add(
        Rect.fromLTWH(gauche, rowToY(row), cellSize * (j - i + 1), cellSize),
      );
      i = j + 1;
    }
    return rects;
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

    // Hors du plateau, la case n'existe que si elle rallie — ou si sa rangée
    // est ouverte : celle qu'on est en train de choisir, ou les deux dans le
    // composeur.
    if (row < 0 || row >= kRows) {
      final camp = campDeLaRangee(row);
      final ouverte = ralliementsTouchables || camp == rangeeOuverte;
      if (!ouverte && !rall.contient(camp, col)) return null;
    }
    return Cell(col, row);
  }
}
