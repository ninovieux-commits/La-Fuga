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
    final pieces = maneuverPieces
        .map(cellToNotationOf)
        .whereType<String>()
        .join();
    return '($pieces)-$endStr';
  }

  if (isPush) {
    final base = '$startStr-$endStr>';
    // Toutes les directions poussables ont-elles été poussées ? Alors on
    // n'écrit rien après le chevron.
    final pushed = pushTargets.toSet();
    final all = pushableDirs.toSet();
    if (all.isNotEmpty &&
        pushed.length == all.length &&
        pushed.containsAll(all)) {
      return base;
    }
    final targets = pushTargets
        .map(cellToNotationOf)
        .whereType<String>()
        .join();
    return base + targets;
  }

  return '$startStr-$endStr';
}

/// Notation d'un coup produit par le générateur (chemin IA, réseau, analyse).
///
/// Portage de `_ai_notation`, qui n'écrit PAS comme le chemin humain : une
/// poussée y nomme toujours ses cases, même quand toutes les directions
/// disponibles ont été poussées, là où `_build_move_notation` écrit alors
/// `Do1-Do2>` tout court. Les deux orthographes désignent le même coup et
/// [resolveNotation] les accepte l'une comme l'autre ; on garde celle de Kivy
/// pour que deux appareils enregistrent la même partie au même octet.
///
/// [pushTargets] sont les cases effectivement poussées.
String notationOfMove(Move move, {List<Cell> pushTargets = const []}) {
  if (move.fugue) {
    return buildMoveNotation(start: move.from, end: null);
  }
  if (move.kind == MoveKind.maneuver) {
    // La maîtresse en tête, comme chez Kivy : c'est elle qui donne le delta.
    final pieces = move.fromCells ?? [move.from];
    return buildMoveNotation(
      start: move.from,
      end: move.to,
      isManeuver: true,
      maneuverPieces: [move.from, ...pieces.where((c) => c != move.from)],
    );
  }
  if (move.kind == MoveKind.square && pushTargets.isNotEmpty) {
    final targets = pushTargets
        .map(cellToNotationOf)
        .whereType<String>()
        .join();
    return '${buildMoveNotation(start: move.from, end: move.to)}>$targets';
  }
  return buildMoveNotation(start: move.from, end: move.to);
}

/// Ce qu'une notation `.nmc` décrit, une fois découpée.
///
/// Portage du découpage de `_apply_notation`, `_apply_simple_or_push` et
/// `_apply_maneuver` (main.py). Kivy relit une partie en appliquant la
/// notation telle quelle ; nous la comparons aux coups légaux. Le découpage,
/// lui, doit être le même : sinon un fichier écrit par l'app Kivy deviendrait
/// illisible ici.
sealed class NotationParts {
  const NotationParts();
}

/// `Mi7*` — la pièce quitte le plateau par sa zone de ralliement.
final class FugueNotation extends NotationParts {
  const FugueNotation(this.start);
  final Cell start;
}

/// `Do1-Do2`, `Do1-Do2>` ou `Do1-Do2>Ré3Mi4`.
///
/// [pushed] vaut `null` quand rien ne suit le chevron : Kivy pousse alors
/// **toutes** les directions disponibles.
final class SimpleNotation extends NotationParts {
  const SimpleNotation(
    this.start,
    this.end, {
    this.isPush = false,
    this.pushed,
  });
  final Cell start;
  final Cell? end;
  final bool isPush;
  final List<Cell>? pushed;
}

/// `(Do8Mi8)-Do7`. Une seule case désigne le groupe entier.
final class ManeuverNotation extends NotationParts {
  const ManeuverNotation(this.cells, this.dest);
  final List<Cell> cells;
  final Cell dest;
}

/// Découpe une notation. `null` si elle ne veut rien dire.
NotationParts? parseNotation(String notation) {
  var s = notation.trim();
  if (s.isEmpty) return null;
  // Les marques de fin de partie ne font pas partie du coup.
  while (s.endsWith('#')) {
    s = s.substring(0, s.length - 1).trimRight();
  }
  if (s.isEmpty) return null;

  if (s.startsWith('(')) {
    final m = RegExp(r'^\((.*)\)-(.+)$').firstMatch(s);
    if (m == null) return null;
    var destStr = m.group(2)!;
    if (destStr.endsWith('#')) {
      destStr = destStr.substring(0, destStr.length - 1);
    }
    final cells = parseCellsConcat(m.group(1)!);
    final dest = notationToCell(destStr);
    if (cells == null || cells.isEmpty || dest == null) return null;
    return ManeuverNotation(cells, dest);
  }

  // Fugue : la case d'arrivée n'a pas de nom.
  if (s.contains('*') && !s.contains('-')) {
    final start = notationToCell(s.replaceAll('*', '').trim());
    return start == null ? null : FugueNotation(start);
  }

  String movePart = s;
  String? pushPart;
  final chevron = s.indexOf('>');
  if (chevron >= 0) {
    movePart = s.substring(0, chevron);
    pushPart = s.substring(chevron + 1);
  }

  final dash = movePart.indexOf('-');
  if (dash < 0) return null;
  var endStr = movePart.substring(dash + 1);
  // `Do1-Do2*` : fugue sur une case nommable.
  if (endStr.endsWith('*')) endStr = endStr.substring(0, endStr.length - 1);

  final start = notationToCell(movePart.substring(0, dash));
  if (start == null) return null;
  final end = notationToCell(endStr);

  if (pushPart == null || end == null) {
    return SimpleNotation(start, end);
  }
  if (pushPart.trim().isEmpty) {
    return SimpleNotation(start, end, isPush: true);
  }
  final cells = parseCellsConcat(pushPart);
  if (cells == null) return null;
  return SimpleNotation(start, end, isPush: true, pushed: cells);
}
