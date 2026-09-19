/// Géométrie du plateau : l'orientation, les zones de ralliement et la
/// conversion pixel → case.
///
/// Kivy a l'axe Y vers le haut, Flutter vers le bas : ces tests existent
/// surtout pour attraper un plateau dessiné à l'envers.
library;

import 'dart:ui';

import 'package:lafuga/engine/board.dart';
import 'package:lafuga/ui/widgets/board_geometry.dart';
import 'package:test/test.dart';

void main() {
  // 700 de large → case de 100 ; 1000 de haut → zone de 1000, donc originY = 0.
  const size = Size(700, 1000);

  group('Blancs en bas (flipped)', () {
    final g = BoardGeometry(size: size, flipped: true);

    test('la case de départ des Blancs est en bas', () {
      final blancBack = g.rowToY(0); // rangée 1
      final noirBack = g.rowToY(7); // rangée 8
      expect(
        blancBack,
        greaterThan(noirBack),
        reason: 'row 0 doit être plus bas à l écran que row 7',
      );
    });

    test('le ralliement des Blancs est tout en haut', () {
      expect(g.rowToIndex(8), 0);
      expect(g.rowToY(8), g.originY);
    });

    test('le ralliement des Noirs est tout en bas', () {
      expect(g.rowToIndex(-1), 9);
    });

    test('la colonne do est à gauche', () {
      expect(g.colToX(0), lessThan(g.colToX(6)));
    });
  });

  group('Blancs en haut (vue du joueur Noir, 180°)', () {
    final g = BoardGeometry(size: size, flipped: false);

    test('la case de départ des Noirs est en bas', () {
      expect(g.rowToY(7), greaterThan(g.rowToY(0)));
    });

    test('le ralliement des Noirs est tout en haut', () {
      expect(g.rowToIndex(-1), 0);
    });

    test('la colonne do passe à droite', () {
      expect(g.colToX(0), greaterThan(g.colToX(6)));
    });
  });

  group('pixelToCell', () {
    for (final flipped in [true, false]) {
      test('aller-retour sur les 56 cases (flipped=$flipped)', () {
        final g = BoardGeometry(size: size, flipped: flipped);
        for (var c = 0; c < kCols; c++) {
          for (var r = 0; r < kRows; r++) {
            final centre = g.cellCenter(c, r);
            expect(
              g.pixelToCell(centre),
              Cell(c, r),
              reason: 'case ($c,$r) en flipped=$flipped',
            );
          }
        }
      });

      test('les zones de ralliement (flipped=$flipped)', () {
        final g = BoardGeometry(size: size, flipped: flipped);
        for (final row in [8, -1]) {
          for (final col in kRally) {
            expect(
              g.pixelToCell(g.cellCenter(col, row)),
              Cell(col, row),
              reason: 'ralliement ($col,$row)',
            );
          }
          // Hors des colonnes centrales, la bande n'existe pas.
          for (final col in [0, 1, 5, 6]) {
            expect(
              g.pixelToCell(g.cellCenter(col, row)),
              isNull,
              reason: 'pas de ralliement en colonne $col',
            );
          }
        }
      });
    }

    test('un point hors du plateau ne donne aucune case', () {
      final g = BoardGeometry(size: size, flipped: true);
      expect(g.pixelToCell(const Offset(-10, 500)), isNull);
      expect(g.pixelToCell(Offset(size.width + 10, 500)), isNull);
      expect(g.pixelToCell(Offset(350, g.originY - 10)), isNull);
      expect(
        g.pixelToCell(Offset(350, g.originY + g.boardHeight + 10)),
        isNull,
      );
    });
  });

  test('les 10 rangées dessinées sont distinctes et contiguës', () {
    final g = BoardGeometry(size: size, flipped: true);
    final ys = [for (var i = 0; i < kExtRows; i++) g.rowToY(g.indexToRow(i))];
    for (var i = 1; i < ys.length; i++) {
      expect(
        ys[i] - ys[i - 1],
        closeTo(g.cellSize, 1e-9),
        reason: 'rangées $i et ${i - 1} contiguës',
      );
    }
  });
}
