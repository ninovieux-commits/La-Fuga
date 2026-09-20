/// Lecture d'une partie enregistrée : on navigue coup par coup.
///
/// Dart pur. Les positions sont calculées une fois à l'ouverture, puis la
/// navigation ne fait que changer d'index : reculer d'un coup doit être aussi
/// instantané qu'avancer.
library;

import '../engine/board.dart';
import '../engine/move.dart';
import '../engine/move_generator.dart';
import '../engine/piece.dart';
import '../engine/random_fuga.dart';
import 'nmc.dart';

/// Une position de la partie, avec le coup qui y a mené.
final class ReplayStep {
  const ReplayStep({
    required this.board,
    required this.turn,
    this.notation,
    this.move,
  });

  final Board board;

  /// Camp au trait dans cette position.
  final Camp turn;

  /// Coup qui a mené ici. `null` pour la position de départ.
  final String? notation;

  /// Le coup lui-même, pour mettre en évidence les cases touchées.
  final Move? move;

  /// Cases à encadrer : départ et arrivées du coup.
  Set<Cell> get highlightedCells {
    final m = move;
    if (m == null) return const {};
    return {m.from, ...m.movedCells}..removeWhere((c) => !c.onBoard);
  }
}

/// Vrai si ce contenu se lit comme une partie.
///
/// Kivy refuse un `.nmc` dont les coups ne se relisent pas ; on refuse en
/// plus un contenu sans en-tête NI coup, qui ne mène qu'à un lecteur vide.
bool isReadableNmc(String content) {
  final game = parseNmc(content);
  final hasHeader = game.meta.player1.isNotEmpty || game.meta.date.isNotEmpty;
  if (!hasHeader && game.moves.isEmpty) return false;

  // Un premier coup illisible : il n'y a rien à rejouer.
  final replay = ReplayController.fromNmc(content);
  return replay.brokenMoveNumber != 1;
}

/// Navigation dans une partie enregistrée.
class ReplayController {
  ReplayController._(this.meta, this.steps, this._brokenAt);

  /// En-tête de la partie.
  final NmcMeta meta;

  /// Toutes les positions, de la position de départ à la finale.
  final List<ReplayStep> steps;

  /// Index du premier coup qu'on n'a pas su rejouer, ou `null`.
  final int? _brokenAt;

  int _index = 0;

  /// Construit le lecteur en rejouant la partie.
  ///
  /// Si un coup ne se relit pas, on s'arrête là et on le signale : le lecteur
  /// montre ce qu'il sait et dit où il a buté, plutôt que d'afficher une
  /// position inventée.
  factory ReplayController.fromNmc(String content, {Board? initialBoard}) {
    final game = parseNmc(content);
    final start =
        initialBoard ??
        (game.meta.random == null
            ? Board.initial()
            // Un code illisible retombe sur la position standard : mieux vaut
            // une partie qu'on ne saura pas rejouer qu'un plantage.
            : buildRandomFugaBoard(game.meta.random!) ?? Board.initial());

    final steps = <ReplayStep>[ReplayStep(board: start, turn: Camp.blanc)];

    var board = start;
    var turn = Camp.blanc;
    int? broken;

    for (var i = 0; i < game.moves.length; i++) {
      final notation = game.moves[i];
      final move = resolveNotation(board, turn, notation);
      if (move == null) {
        broken = i;
        break;
      }
      board = move.board;
      steps.add(
        ReplayStep(
          board: board,
          turn: turn.opposite,
          notation: notation,
          move: move,
        ),
      );
      if (move.fugue || move.fugueBy != null || move.matOn != null) break;
      turn = turn.opposite;
    }

    return ReplayController._(game.meta, steps, broken);
  }

  /// Position actuellement affichée.
  ReplayStep get current => steps[_index];

  int get index => _index;

  /// Nombre de coups rejoués.
  int get moveCount => steps.length - 1;

  bool get atStart => _index == 0;
  bool get atEnd => _index == steps.length - 1;

  /// Vrai si la partie n'a pas pu être rejouée jusqu'au bout.
  bool get isTruncated => _brokenAt != null;

  /// Numéro du coup qui a bloqué la lecture, à partir de 1.
  int? get brokenMoveNumber => _brokenAt == null ? null : _brokenAt + 1;

  /// Recule d'un coup. Renvoie vrai si la position a changé.
  bool previous() {
    if (atStart) return false;
    _index--;
    return true;
  }

  /// Avance d'un coup.
  bool next() {
    if (atEnd) return false;
    _index++;
    return true;
  }

  bool toStart() {
    if (atStart) return false;
    _index = 0;
    return true;
  }

  bool toEnd() {
    if (atEnd) return false;
    _index = steps.length - 1;
    return true;
  }

  /// Va à une position précise. 0 = position de départ.
  bool goTo(int index) {
    if (index < 0 || index >= steps.length || index == _index) return false;
    _index = index;
    return true;
  }

  /// Les coups, par paires, pour l'affichage d'un bandeau d'historique.
  ///
  /// Chaque entrée porte le numéro du tour et les deux demi-coups.
  List<({int turn, String? blanc, String? noir})> get movePairs {
    final out = <({int turn, String? blanc, String? noir})>[];
    for (var i = 1; i < steps.length; i += 2) {
      out.add((
        turn: (i + 1) ~/ 2,
        blanc: steps[i].notation,
        noir: i + 1 < steps.length ? steps[i + 1].notation : null,
      ));
    }
    return out;
  }
}
