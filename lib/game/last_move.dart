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
import '../engine/move.dart';
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
