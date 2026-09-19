/// Notation `.nmc` de La Fuga — Dart pur.
///
/// Les colonnes portent des noms de notes ; une case s'écrit `Fa5`.
/// Portage de `cell_to_notation`, `notation_to_cell`, `parse_cells_concat`
/// et `_build_move_notation` (main.py).
library;

import 'board.dart';
import 'move.dart';

/// Noms des colonnes, index 0 → 6.
const List<String> kNotes = ['Do', 'Ré', 'Mi', 'Fa', 'Sol', 'La', 'Si'];

/// `(col, row)` → `'Fa5'`. `null` pour une case hors plateau
/// (les zones de ralliement n'ont pas de notation propre : on écrit `Départ*`).
String? cellToNotation(int c, int r) {
  if (!Board.onBoard(c, r)) return null;
  return '${kNotes[c]}${r + 1}';
}

String? cellToNotationOf(Cell cell) => cellToNotation(cell.col, cell.row);

/// `'Fa5'` → `(col, row)`. `null` si la chaîne n'est pas une case valide.
Cell? notationToCell(String? notation) {
  if (notation == null || notation.isEmpty) return null;
  for (var i = 0; i < kNotes.length; i++) {
    final note = kNotes[i];
    if (!notation.startsWith(note)) continue;
    final rest = notation.substring(note.length);
    final num = int.tryParse(rest);
    if (num != null && num >= 1 && num <= 8) return Cell(i, num - 1);
    return null;
  }
  return null;
}

/// Découpe `'Do1Mi3Sol5'` en `[(0,0), (2,2), (4,4)]`.
/// `null` si la chaîne contient quoi que ce soit d'autre.
List<Cell>? parseCellsConcat(String s) {
  final cells = <Cell>[];
  var i = 0;
  while (i < s.length) {
    var matched = false;
    for (final note in kNotes) {
      if (i + note.length > s.length) continue;
      if (s.substring(i, i + note.length) != note) continue;
      var k = i + note.length;
      while (k < s.length && _isDigit(s.codeUnitAt(k))) {
        k++;
      }
      if (k > i + note.length) {
        final cell = notationToCell(s.substring(i, k));
        if (cell == null) return null;
        cells.add(cell);
        i = k;
        matched = true;
        break;
      }
    }
    if (!matched) return null;
  }
  return cells;
}

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

/// Construit la notation d'un coup.
///
/// - déplacement / multisaut : `Fa2-Fa3`
/// - manœuvre : `(Do1Ré1)-Do2` (cases **initiales**, maîtresse en tête)
/// - poussée : `Do1-Do2>` si toutes les directions disponibles ont été
///   poussées, sinon `Do1-Do2>Ré3Mi4` avec les cases explicitement poussées
/// - fugue : `Fa7*`
String buildMoveNotation({
  required Cell start,
  Cell? end,
  bool isManeuver = false,
  List<Cell> maneuverPieces = const [],
  bool isPush = false,
  List<Cell> pushTargets = const [],
  List<Cell> pushableDirs = const [],
}) {
  final startStr = cellToNotationOf(start);
  if (startStr == null) return '';

  // Fugue : la case d'arrivée est hors plateau.
  if (end == null || !end.onBoard) return '$startStr*';

  final endStr = cellToNotationOf(end);
  if (endStr == null) return '$startStr*';

  if (isManeuver) {
    final pieces = maneuverPieces.map(cellToNotationOf).whereType<String>().join();
    return '($pieces)-$endStr';
  }

  if (isPush) {
    final base = '$startStr-$endStr>';
    // Toutes les directions poussables ont-elles été poussées ? Alors on
    // n'écrit rien après le chevron.
    final pushed = pushTargets.toSet();
    final all = pushableDirs.toSet();
    if (all.isNotEmpty && pushed.length == all.length && pushed.containsAll(all)) {
      return base;
    }
    final targets =
        pushTargets.map(cellToNotationOf).whereType<String>().join();
    return base + targets;
  }

  return '$startStr-$endStr';
}

/// Notation d'un coup produit par le générateur (chemin IA / analyse).
String notationOfMove(Move move, {List<Cell> pushTargets = const []}) {
  if (move.fugue) {
    return buildMoveNotation(start: move.from, end: null);
  }
  if (move.kind == MoveKind.maneuver) {
    return buildMoveNotation(
      start: move.from,
      end: move.to,
      isManeuver: true,
      maneuverPieces: move.fromCells ?? [move.from],
    );
  }
  if (move.pushDirsUsed.isNotEmpty) {
    return buildMoveNotation(
      start: move.from,
      end: move.to,
      isPush: true,
      pushTargets: pushTargets,
      pushableDirs: pushTargets,
    );
  }
  return buildMoveNotation(start: move.from, end: move.to);
}

/// Formate l'historique en texte `.nmc` : `1.Do1-Do2/Do8-Do7  2.…`
String formatNmcMoves(List<String> history) {
  final parts = <String>[];
  var i = 0;
  var turn = 1;
  while (i < history.length) {
    final blanc = history[i];
    final noir = (i + 1 < history.length) ? history[i + 1] : null;
    parts.add(noir == null ? '$turn.$blanc' : '$turn.$blanc/$noir');
    i += 2;
    turn++;
  }
  return parts.join('  ');
}
