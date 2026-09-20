/// Relecture littérale d'une notation — portage de `_apply_notation`,
/// `_apply_simple_or_push`, `_apply_maneuver` et `do_push` (main.py).
///
/// Kivy relit une partie en **déplaçant les pièces comme la notation le dit**,
/// sans les confronter aux règles : c'est ce qui lui permet d'afficher une
/// partie même quand un coup ne se laisse pas retrouver par le générateur.
/// [resolveNotation] reste le chemin principal — il rend un vrai coup, avec
/// ses prises et sa mise en évidence. Celui-ci est le filet, et il évite de
/// répondre « partie illisible » là où Kivy affiche quelque chose.
library;

import 'board.dart';
import 'notation.dart';
import 'piece.dart';

/// Résultat d'une application littérale.
typedef LiteralMove = ({Board board, Set<Cell> from, Set<Cell> to});

/// Applique [notation] sur [board]. `null` si elle ne veut rien dire.
LiteralMove? applyNotationLiterally(Board board, String notation) {
  final parts = parseNotation(notation);
  if (parts == null) return null;
  final next = board.clone();

  switch (parts) {
    // `Mi7*` : la pièce quitte le plateau par sa zone de ralliement.
    case FugueNotation(:final start):
      if (next.atCell(start) == null) return null;
      next.setCell(start, null);
      return (board: next, from: {start}, to: const {});

    case ManeuverNotation(:final cells, :final dest):
      final master = cells.first;
      final piece = next.atCell(master);
      if (piece == null) return null;
      // Une seule case nommée : c'est tout le groupe qui bouge.
      final group = cells.length == 1
          ? next.groupOf(master.col, master.row).toList()
          : cells;

      final dc = dest.col - master.col;
      final dr = dest.row - master.row;
      final moved = <Cell, Piece>{};
      for (final cell in group) {
        final p = next.atCell(cell);
        if (p == null) return null;
        final landing = Cell(cell.col + dc, cell.row + dr);
        if (!landing.onBoard) return null;
        moved[landing] = p;
      }
      for (final cell in group) {
        next.setCell(cell, null);
      }
      moved.forEach(next.setCell);
      return (board: next, from: group.toSet(), to: moved.keys.toSet());

    case SimpleNotation(:final start, :final end, :final isPush, :final pushed):
      final piece = next.atCell(start);
      if (piece == null) return null;
      next.setCell(start, null);
      if (end != null) next.setCell(end, piece);
      if (!isPush || end == null) {
        return (board: next, from: {start}, to: end == null ? const {} : {end});
      }

      // Rien après le chevron : Kivy pousse TOUT ce qui peut l'être.
      final targets =
          pushed ?? _pushableCells(next, end.col, end.row, piece.type);
      for (final target in targets) {
        _push(next, target, target.col - end.col, target.row - end.row);
      }
      return (board: next, from: {start}, to: {end});
  }
}

/// Cases adjacentes occupées, dans les directions de poussée du type —
/// `_compute_pushable_dirs`.
List<Cell> _pushableCells(Board board, int c, int r, PieceType type) {
  final dirs = switch (type) {
    PieceType.soldat => const [(-1, -1), (1, -1), (-1, 1), (1, 1)],
    PieceType.garde => const [(0, -1), (0, 1), (-1, 0), (1, 0)],
    _ => const <(int, int)>[],
  };
  return [
    for (final (dc, dr) in dirs)
      if (Board.onBoard(c + dc, r + dr) && board.at(c + dc, r + dr) != null)
        Cell(c + dc, r + dr),
  ];
}

/// Pousse la ligne qui commence en [from], d'une case dans la direction
/// donnée — portage de `do_push`. Un Chevalier bloque toute la ligne ; ce qui
/// sort du plateau disparaît.
void _push(Board board, Cell from, int dc, int dr) {
  final line = <(Cell, Piece)>[];
  var c = from.col, r = from.row;
  while (Board.onBoard(c, r)) {
    final p = board.at(c, r);
    if (p == null) break;
    // Le Chevalier est inamovible : la poussée entière ne se fait pas.
    if (p.type == PieceType.chevalier) return;
    line.add((Cell(c, r), p));
    c += dc;
    r += dr;
  }

  for (final (cell, piece) in line.reversed) {
    board.setCell(cell, null);
    final landing = Cell(cell.col + dc, cell.row + dr);
    if (landing.onBoard) board.setCell(landing, piece);
  }
}
