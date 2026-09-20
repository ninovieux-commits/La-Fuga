/// Relecture d'une notation — portage de `_apply_notation`,
/// `_apply_simple_or_push`, `_apply_maneuver` et `do_push` (main.py).
///
/// **C'est le seul chemin de relecture**, comme en Kivy. Une partie
/// enregistrée — `.nmc`, correspondance, reconnexion en ligne — n'est jamais
/// relue en cherchant le coup légal qui correspondrait à la notation : elle
/// est relue en **déplaçant les pièces comme la notation le dit**. Kivy fait
/// exactement cela partout (`_corr_board_from_moves`, l'ouverture d'une
/// correspondance, `_on_etat_partie`, la lecture d'un `.nmc`), et c'est ce qui
/// garantit que deux appareils reconstruisent la même position à partir du
/// même texte.
///
/// Passer par le générateur de coups donnerait parfois un autre plateau : sur
/// `Do1-Do2>`, par exemple, la relecture littérale pousse TOUT ce qui touche
/// la case d'arrivée, là où un coup retrouvé par les règles pourrait n'en
/// pousser qu'une partie. Ces deux plateaux-là ne se voient pas à l'œil, mais
/// ils divergent pour toujours.
library;

import 'board.dart';
import 'notation.dart';
import 'piece.dart';

/// Résultat d'une application littérale.
///
/// [ok] reprend le booléen de `_apply_notation`. Comme en Kivy, un `false`
/// ne veut pas dire que le plateau est intact : une notation dont la partie
/// « poussée » est illisible a déjà déplacé sa pièce. C'est au lecteur de
/// `.nmc` d'en tirer les conséquences (Kivy y refuse la partie entière) ;
/// une correspondance, elle, passe simplement au coup suivant.
typedef LiteralMove = ({Board board, bool ok});

/// Applique [notation] sur [board], à la lettre — `_apply_notation`.
LiteralMove applyNotationLiterally(Board board, String notation) {
  final clean = notation.trim();
  if (clean.isEmpty) return (board: board, ok: false);
  // Seule la marque de fin de partie est retirée ; le `*` d'une fugue, lui,
  // fait partie du coup.
  final s = clean.endsWith('#') ? clean.substring(0, clean.length - 1) : clean;
  if (s.startsWith('(')) return _maneuver(board, s);
  return _simpleOrPush(board, s);
}

/// `Do1-Do2`, `Do1-Do2>`, `Do1-Do2>Ré7Do6`, `Mi7*` — `_apply_simple_or_push`.
LiteralMove _simpleOrPush(Board board, String s) {
  // Fugue vers une case sans nom : la pièce sort par sa zone de ralliement.
  if (s.contains('*') && !s.contains('-')) {
    final start = notationToCell(s.replaceAll('*', '').trim());
    if (start == null) return (board: board, ok: false);
    if (board.atCell(start) == null) return (board: board, ok: false);
    return (board: board.clone()..setCell(start, null), ok: true);
  }

  var movePart = s;
  var pushPart = '';
  final chevron = s.indexOf('>');
  if (chevron >= 0) {
    movePart = s.substring(0, chevron);
    pushPart = s.substring(chevron + 1);
  }

  final dash = movePart.indexOf('-');
  if (dash < 0) return (board: board, ok: false);
  var endStr = movePart.substring(dash + 1);
  // `Do1-Do2*` : fugue vers une case qui, elle, a un nom.
  if (endStr.endsWith('*')) endStr = endStr.substring(0, endStr.length - 1);

  final start = notationToCell(movePart.substring(0, dash));
  if (start == null) return (board: board, ok: false);
  final piece = board.atCell(start);
  if (piece == null) return (board: board, ok: false);

  final end = notationToCell(endStr);
  final next = board.clone();
  next.setCell(start, null);
  if (end != null) next.setCell(end, piece);

  if (chevron >= 0 && end != null) {
    if (pushPart.trim().isEmpty) {
      // Rien après le chevron : Kivy pousse TOUT ce qui peut l'être.
      for (final target in _pushableCells(next, end.col, end.row, piece.type)) {
        _push(next, target, target.col - end.col, target.row - end.row);
      }
    } else {
      final cells = parseCellsConcat(pushPart);
      // Cases illisibles : le déplacement reste fait, les poussées non.
      if (cells == null) return (board: next, ok: false);
      for (final target in cells) {
        _push(next, target, target.col - end.col, target.row - end.row);
      }
    }
  }
  return (board: next, ok: true);
}

/// `(Do1)-Ré2` ou `(Do8Mi8)-Do7` — `_apply_maneuver`.
LiteralMove _maneuver(Board board, String s) {
  final m = RegExp(r'^\((.*)\)-(.+)$').firstMatch(s);
  if (m == null) return (board: board, ok: false);
  var destStr = m.group(2)!;
  if (destStr.endsWith('#')) {
    destStr = destStr.substring(0, destStr.length - 1);
  }
  var cells = parseCellsConcat(m.group(1)!);
  if (cells == null || cells.isEmpty) return (board: board, ok: false);
  final dest = notationToCell(destStr);
  if (dest == null) return (board: board, ok: false);

  final master = cells.first;
  // Une seule case nommée : c'est le groupe entier qui bouge.
  if (cells.length == 1) {
    final group = board.groupOf(master.col, master.row);
    if (group.isEmpty) return (board: board, ok: false);
    final others = group.where((c) => c != master).toList()
      ..sort((a, b) => a.col != b.col ? a.col - b.col : a.row - b.row);
    cells = [master, ...others];
  }

  final dc = dest.col - master.col;
  final dr = dest.row - master.row;
  final next = board.clone();
  final carried = {for (final cell in cells) cell: next.atCell(cell)};
  for (final cell in cells) {
    next.setCell(cell, null);
  }
  for (final entry in carried.entries) {
    final p = entry.value;
    if (p == null) return (board: next, ok: false);
    final nc = entry.key.col + dc;
    final nr = entry.key.row + dr;
    if (!Board.onBoard(nc, nr)) return (board: next, ok: false);
    next.set(nc, nr, p);
  }
  return (board: next, ok: true);
}

/// Cases adjacentes occupées, dans les directions de poussée du type —
/// `_compute_pushable_dirs`.
List<Cell> _pushableCells(Board board, int c, int r, PieceType type) {
  final dirs = pushDirsOfType(type);
  return [
    for (final (dc, dr) in dirs)
      if (Board.onBoard(c + dc, r + dr) && board.at(c + dc, r + dr) != null)
        Cell(c + dc, r + dr),
  ];
}

/// Directions dans lesquelles un type pousse. Vide pour tout le reste.
List<(int, int)> pushDirsOfType(PieceType type) => switch (type) {
  PieceType.soldat => kSoldatPushDirs,
  PieceType.garde => kGardePushDirs,
  _ => const <(int, int)>[],
};

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
