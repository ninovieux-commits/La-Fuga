/// Mise en évidence du dernier coup — portage de
/// `_build_highlight_from_notation`, `_reconstruct_jump_path` et du bloc de
/// dessin correspondant de `BoardWidget._redraw` (main.py).
///
/// Ce que Kivy montre après un coup : un cadre autour des cases de départ et
/// d'arrivée, des petits carrés sur les atterrissages intermédiaires d'un
/// multisaut, et — sur la pièce qui a poussé — les points de poussée grossis
/// dans les directions effectivement utilisées.
///
/// Dart pur : rien ici ne dépend de Flutter.
library;

import 'dart:collection';

import '../engine/board.dart';
import '../engine/literal_replay.dart';
import '../engine/move.dart';
import '../engine/notation.dart';
import '../engine/piece.dart';

/// Ce qu'il faut mettre en évidence après un coup.
final class LastMove {
  const LastMove({
    required this.camp,
    this.from = const {},
    this.to = const {},
    this.jumpPath = const [],
    this.pushDirs = const {},
  });

  /// Camp qui a joué. Le cadre est NOIR pour un coup blanc, BLANC pour un
  /// coup noir — comme en Kivy, pour rester lisible sur toutes les pièces.
  final Camp camp;

  final Set<Cell> from;
  final Set<Cell> to;

  /// Atterrissages intermédiaires d'un multisaut, sans le départ ni l'arrivée.
  final List<Cell> jumpPath;

  /// Directions de poussée utilisées, par case de la pièce qui a poussé.
  final Map<Cell, List<(int, int)>> pushDirs;

  /// Toutes les cases à encadrer.
  Set<Cell> get framedCells => {...from, ...to};

  bool get isEmpty => from.isEmpty && to.isEmpty;

  /// Construit la mise en évidence depuis le résultat d'un geste : c'est ce
  /// dont disposent les écrans où le joueur compose son coup au doigt.
  static LastMove? fromSlides({
    required Board before,
    required Camp camp,
    required List<(Piece, Cell, Cell)> slides,
    List<Cell> pushTargets = const [],
    List<Cell> jumpPath = const [],
  }) {
    if (slides.isEmpty) return null;
    final from = <Cell>{};
    final to = <Cell>{};
    for (final (_, start, end) in slides) {
      if (start.onBoard) from.add(start);
      if (end.onBoard) to.add(end);
    }
    return LastMove(
      camp: camp,
      from: from,
      to: to,
      jumpPath: jumpPath,
      pushDirs: pushDirsOf(
        before,
        from.isEmpty ? null : from.first,
        to.isEmpty ? null : to.first,
        pushTargets,
      ),
    );
  }

  /// Construit la mise en évidence d'un coup, depuis la position d'avant.
  ///
  /// [pushTargets] sont les cases que le joueur a effectivement poussées.
  static LastMove of(
    Board before,
    Move move, {
    List<Cell> pushTargets = const [],
  }) {
    final mover = before.atCell(move.from);
    final camp = mover?.camp ?? Camp.blanc;

    final from = <Cell>{...?move.fromCells, move.from};
    final to = <Cell>{...move.movedCells.where((c) => c.onBoard)};

    return LastMove(
      camp: camp,
      from: from,
      to: to,
      jumpPath: move.kind == MoveKind.jump
          ? jumpPathOf(before, move.from, move.movedCells.first)
          : const [],
      pushDirs: _pushDirs(before, move, pushTargets),
    );
  }

  /// Directions de poussée, filtrées par le type de la pièce : le Soldat
  /// pousse en diagonale, le Garde en orthogonal. La garde vient de Kivy et
  /// protège des notations bancales.
  static Map<Cell, List<(int, int)>> _pushDirs(
    Board before,
    Move move,
    List<Cell> pushTargets,
  ) => pushDirsOf(before, move.from, move.movedCells.first, pushTargets);

  /// Même chose, à partir des seules cases : pour les coups construits au
  /// doigt, où l'on n'a pas d'objet `Move`.
  static Map<Cell, List<(int, int)>> pushDirsOf(
    Board before,
    Cell? start,
    Cell? arrival,
    List<Cell> pushTargets,
  ) {
    if (start == null || arrival == null) return const {};
    final piece = before.atCell(start);
    if (piece == null || !piece.type.isSquare || pushTargets.isEmpty) {
      return const {};
    }
    final valid = piece.type == PieceType.soldat
        ? const {(-1, -1), (1, -1), (-1, 1), (1, 1)}
        : const {(0, -1), (0, 1), (-1, 0), (1, 0)};

    final dirs = <(int, int)>[];
    for (final target in pushTargets) {
      final dc = (target.col - arrival.col).sign;
      final dr = (target.row - arrival.row).sign;
      if (valid.contains((dc, dr)) && !dirs.contains((dc, dr))) {
        dirs.add((dc, dr));
      }
    }
    return dirs.isEmpty ? const {} : {arrival: dirs};
  }
}

/// Chemin d'un multisaut, en le moins de sauts possible.
///
/// Renvoie les atterrissages intermédiaires, ou une liste vide si ce n'est pas
/// un multisaut. Recherche en largeur, comme `_reconstruct_jump_path`.
List<Cell> jumpPathOf(Board before, Cell start, Cell end) {
  final mover = before.atCell(start);
  if (mover == null || !mover.type.isRound) return const [];

  // Le sauteur ne se saute pas lui-même : on le retire des obstacles.
  final obstacles = before.clone()..setCell(start, null);

  final queue = Queue<List<Cell>>()..add([start]);
  final seen = <Cell>{start};

  while (queue.isNotEmpty) {
    final path = queue.removeFirst();
    final current = path.last;
    if (current == end) {
      // Deux cases = un saut simple : rien à montrer entre les deux.
      return path.length < 3 ? const [] : path.sublist(1, path.length - 1);
    }

    for (var dc = -1; dc <= 1; dc++) {
      for (var dr = -1; dr <= 1; dr++) {
        if (dc == 0 && dr == 0) continue;
        final over = Cell(current.col + dc, current.row + dr);
        final landing = Cell(current.col + 2 * dc, current.row + 2 * dr);
        if (!over.onBoard || !landing.onBoard) continue;

        // On ne saute que par-dessus une ronde, et on n'atterrit que sur une
        // case vide — sauf l'arrivée, qui peut être occupée le temps du calcul.
        final jumped = obstacles.atCell(over);
        if (jumped == null || !jumped.type.isRound) continue;
        if (landing != end && obstacles.atCell(landing) != null) continue;
        if (!seen.add(landing)) continue;

        queue.add([...path, landing]);
      }
    }
  }
  return const [];
}

/// Mise en évidence reconstruite depuis la seule notation — portage de
/// `_build_highlight_from_notation` et `_reconstruct_push_targets`.
///
/// C'est ce dont on dispose en relisant une partie enregistrée : il n'y a pas
/// d'objet coup, seulement le texte, la position d'avant et celle d'après.
///
/// [before] est la position d'avant le coup (le snapshot de l'avant-dernier
/// coup chez Kivy), [after] celle d'après — elle ne sert qu'à choisir la
/// couleur du cadre, prise sur la pièce qui occupe la case d'arrivée.
LastMove? lastMoveFromNotation(String notation, Board? before, Board after) {
  // La marque de fin de partie — `*` d'un gain à deux points, `#` d'un mat —
  // ne décrit pas le déplacement. Seule la fugue sans case nommable garde son
  // `*`, et [splitEndMark] le sait.
  final n = splitEndMark(notation).move;
  if (n.isEmpty) return null;

  final from = <Cell>{};
  final to = <Cell>{};

  // Fugue depuis une case nommée : `Mi7*`. La case d'arrivée est le ralliement
  // du camp qui fugue — hors du plateau de jeu, mais bien à l'écran, là où
  // l'Héritier se pose. L'encadrer aussi, c'est dire le coup en entier : il
  // part de là, il est maintenant ici. Le cadre d'arrivée manquait, et la
  // fugue était le seul coup du jeu à n'être montré qu'à moitié.
  //
  // Le camp ne peut pas se lire sur la position d'APRÈS — l'Héritier n'y est
  // plus — donc il se lit sur celle d'avant. Sans elle, on s'en tient au
  // départ plutôt que d'encadrer le mauvais ralliement.
  if (n.contains('*') && !n.contains('-')) {
    final start = notationToCell(n.replaceAll('*', '').trim());
    if (start == null) return _framed(after, from, to);
    from.add(start);
    final leaving = before?.atCell(start);
    if (leaving == null || !leaving.isHeir) return _framed(after, from, to);
    return LastMove(
      camp: leaving.camp,
      from: from,
      to: {rallyDisplayCell(leaving.camp)},
    );
  }

  // Manœuvre : seules les cases NOMMÉES sont encadrées, même quand c'est le
  // groupe entier qui bouge — Kivy ne développe pas le groupe ici.
  if (n.startsWith('(')) {
    final m = RegExp(r'^\((.*)\)-(.+)$').firstMatch(n);
    if (m != null) {
      final cells = parseCellsConcat(m.group(1)!);
      final dest = notationToCell(m.group(2)!);
      if (cells != null && cells.isNotEmpty && dest != null) {
        final master = cells.first;
        final dc = dest.col - master.col;
        final dr = dest.row - master.row;
        for (final cell in cells) {
          from.add(cell);
          to.add(Cell(cell.col + dc, cell.row + dr));
        }
      }
    }
    return _framed(after, from, to);
  }

  final chevron = n.indexOf('>');
  final movePart = chevron >= 0 ? n.substring(0, chevron) : n;
  final dash = movePart.indexOf('-');
  final startStr = dash >= 0 ? movePart.substring(0, dash) : movePart;
  final endStr = dash >= 0 ? movePart.substring(dash + 1) : '';

  final start = notationToCell(startStr);
  final end = endStr.isEmpty ? null : notationToCell(endStr);
  if (start != null) from.add(start);
  if (end != null) to.add(end);

  // Rebonds d'un multisaut : jamais sur une poussée, qui contient le chevron.
  final jumpPath =
      (end != null && chevron < 0 && start != null && before != null)
      ? jumpPathOf(before, start, end)
      : const <Cell>[];

  var pushDirs = const <Cell, List<(int, int)>>{};
  if (chevron >= 0 && end != null) {
    // Type de la pièce qui a poussé : dans la position d'avant en cas de
    // départ connu, sinon celle qui occupe la case d'arrivée maintenant.
    var pusher = (start != null && before != null)
        ? before.atCell(start)
        : null;
    pusher ??= after.atCell(end);
    if (pusher != null && pusher.type.isSquare) {
      final valid = pushDirsOfType(pusher.type).toSet();
      final active = <(int, int)>[];
      final targets = reconstructPushTargets(n, before);
      if (targets.isNotEmpty) {
        for (final target in targets) {
          final dir = (
            (target.col - end.col).sign,
            (target.row - end.row).sign,
          );
          if (valid.contains(dir) && !active.contains(dir)) active.add(dir);
        }
      } else if (before != null) {
        for (final (dc, dr) in valid) {
          if (Board.onBoard(end.col + dc, end.row + dr) &&
              before.at(end.col + dc, end.row + dr) != null) {
            active.add((dc, dr));
          }
        }
      }
      if (active.isNotEmpty) pushDirs = {end: active};
    }
  }

  return _framed(after, from, to, jumpPath: jumpPath, pushDirs: pushDirs);
}

/// Cases effectivement poussées, relues depuis la notation —
/// `_reconstruct_push_targets`.
List<Cell> reconstructPushTargets(String notation, Board? before) {
  // Même marque de fin à écarter : collée à la dernière case poussée, elle
  // faisait refuser toute la liste, et les points de poussée grossis du
  // dernier coup disparaissaient sur le coup qui clôt la partie.
  final n = splitEndMark(notation).move;
  final chevron = n.indexOf('>');
  if (chevron < 0) return const [];
  final movePart = n.substring(0, chevron);
  final afterPush = n.substring(chevron + 1).trim();
  final dash = movePart.indexOf('-');
  if (dash < 0) return const [];
  final end = notationToCell(movePart.substring(dash + 1));
  if (end == null) return const [];

  // Cases listées après le chevron : ce sont les cibles, telles quelles.
  if (afterPush.isNotEmpty) return parseCellsConcat(afterPush) ?? const [];

  // `Ré1-Do2>` sans précision : toutes les directions où il y avait quelque
  // chose juste avant le coup.
  if (before == null) return const [];
  final start = notationToCell(movePart.substring(0, dash));
  if (start == null) return const [];
  final pusher = before.atCell(start);
  if (pusher == null || !pusher.type.isSquare) return const [];
  return [
    for (final (dc, dr) in pushDirsOfType(pusher.type))
      if (Board.onBoard(end.col + dc, end.row + dr) &&
          before.at(end.col + dc, end.row + dr) != null)
        Cell(end.col + dc, end.row + dr),
  ];
}

/// Assemble la mise en évidence et choisit la couleur du cadre.
///
/// Kivy lit le camp sur la pièce qui occupe l'une des cases d'arrivée APRÈS
/// le coup, et prend le cadre blanc par défaut — donc le camp noir ici.
LastMove _framed(
  Board after,
  Set<Cell> from,
  Set<Cell> to, {
  List<Cell> jumpPath = const [],
  Map<Cell, List<(int, int)>> pushDirs = const {},
}) {
  var camp = Camp.noir;
  for (final cell in to) {
    if (!cell.onBoard) continue;
    final p = after.atCell(cell);
    if (p != null) {
      camp = p.camp;
      break;
    }
  }
  return LastMove(
    camp: camp,
    from: from,
    to: to,
    jumpPath: jumpPath,
    pushDirs: pushDirs,
  );
}
