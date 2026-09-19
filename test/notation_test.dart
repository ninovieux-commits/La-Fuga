/// Notation `.nmc` : aller-retour et formes particulières.
library;

import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/notation.dart';
import 'package:test/test.dart';

void main() {
  group('Cases', () {
    test('cellToNotation suit la convention note + rangée', () {
      expect(cellToNotation(0, 0), 'Do1');
      expect(cellToNotation(3, 4), 'Fa5');
      expect(cellToNotation(6, 7), 'Si8');
      expect(cellToNotation(4, 2), 'Sol3');
    });

    test('une case hors plateau n a pas de notation', () {
      expect(cellToNotation(3, 8), isNull, reason: 'ralliement Blanc');
      expect(cellToNotation(3, -1), isNull, reason: 'ralliement Noir');
      expect(cellToNotation(7, 0), isNull);
    });

    test('aller-retour sur les 56 cases', () {
      for (var c = 0; c < kCols; c++) {
        for (var r = 0; r < kRows; r++) {
          final n = cellToNotation(c, r)!;
          expect(notationToCell(n), Cell(c, r), reason: n);
        }
      }
    });

    test('notationToCell rejette les entrées invalides', () {
      expect(notationToCell(''), isNull);
      expect(notationToCell(null), isNull);
      expect(notationToCell('Do9'), isNull, reason: 'rangée hors bornes');
      expect(notationToCell('Do0'), isNull);
      expect(notationToCell('Xx3'), isNull);
      expect(notationToCell('Do'), isNull, reason: 'pas de rangée');
    });

    test('Sol et Si ne se confondent pas avec So/S', () {
      expect(notationToCell('Sol3'), const Cell(4, 2));
      expect(notationToCell('Si3'), const Cell(6, 2));
    });
  });

  group('parseCellsConcat', () {
    test('découpe une concaténation de cases', () {
      expect(parseCellsConcat('Do1Mi3Sol5'), [
        const Cell(0, 0),
        const Cell(2, 2),
        const Cell(4, 4),
      ]);
    });

    test('gère les notes de longueurs différentes', () {
      expect(parseCellsConcat('Ré2Si8Fa1'), [
        const Cell(1, 1),
        const Cell(6, 7),
        const Cell(3, 0),
      ]);
    });

    test('rejette une chaîne mal formée', () {
      expect(parseCellsConcat('Do1Zz2'), isNull);
      expect(parseCellsConcat('Do'), isNull);
    });

    test('chaîne vide = liste vide', () {
      expect(parseCellsConcat(''), isEmpty);
    });
  });

  group('buildMoveNotation', () {
    test('déplacement simple', () {
      expect(
        buildMoveNotation(start: const Cell(3, 1), end: const Cell(3, 2)),
        'Fa2-Fa3',
      );
    });

    test('fugue : case d arrivée hors plateau', () {
      expect(
        buildMoveNotation(start: const Cell(3, 6), end: const Cell(3, 8)),
        'Fa7*',
      );
      expect(buildMoveNotation(start: const Cell(3, 6)), 'Fa7*');
    });

    test('manœuvre : cases initiales entre parenthèses, maîtresse en tête', () {
      expect(
        buildMoveNotation(
          start: const Cell(0, 0),
          end: const Cell(0, 1),
          isManeuver: true,
          maneuverPieces: const [Cell(0, 0), Cell(1, 0)],
        ),
        '(Do1Ré1)-Do2',
      );
    });

    test('poussée totale : rien après le chevron', () {
      expect(
        buildMoveNotation(
          start: const Cell(0, 0),
          end: const Cell(0, 1),
          isPush: true,
          pushTargets: const [Cell(1, 2)],
          pushableDirs: const [Cell(1, 2)],
        ),
        'Do1-Do2>',
      );
    });

    test('poussée partielle : les cibles sont écrites', () {
      expect(
        buildMoveNotation(
          start: const Cell(0, 0),
          end: const Cell(0, 1),
          isPush: true,
          pushTargets: const [Cell(1, 2)],
          pushableDirs: const [Cell(1, 2), Cell(2, 3)],
        ),
        'Do1-Do2>Ré3',
      );
    });
  });

  group('formatNmcMoves', () {
    test('numérote par paires de coups', () {
      expect(
        formatNmcMoves(['Do1-Do2', 'Do8-Do7', 'Ré1-Ré2']),
        '1.Do1-Do2/Do8-Do7  2.Ré1-Ré2',
      );
    });

    test('historique vide', () {
      expect(formatNmcMoves([]), '');
    });
  });
}
