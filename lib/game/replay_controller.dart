/// Lecture d'une partie enregistrée : on navigue coup par coup.
///
/// Dart pur. Les positions sont calculées une fois à l'ouverture, puis la
/// navigation ne fait que changer d'index : reculer d'un coup doit être aussi
/// instantané qu'avancer.
library;

import '../engine/board.dart';
import '../engine/move.dart';
import '../engine/literal_replay.dart';
import '../engine/move_generator.dart';
import '../engine/piece.dart';
import '../engine/random_fuga.dart';
import 'last_move.dart';
import 'nmc.dart';

/// Une position de la partie, avec le coup qui y a mené.
final class ReplayStep {
  const ReplayStep({
    required this.board,
    required this.turn,
    this.notation,
    this.move,
    this.boardBefore,
    this.captured = const {},
  });

  final Board board;

  /// Camp au trait dans cette position.
  final Camp turn;

  /// Coup qui a mené ici. `null` pour la position de départ.
  final String? notation;

  /// Le coup lui-même, pour mettre en évidence les cases touchées.
  final Move? move;

  /// Position d'avant ce coup, quand il y en a un.
  final Board? boardBefore;

  /// Pièces éjectées depuis le début, par camp d'appartenance : de quoi
  /// remplir les panneaux comme en partie.
  final Map<Camp, List<Piece>> captured;

  /// Cases à encadrer : départ et arrivées du coup.
  Set<Cell> get highlightedCells {
    final m = move;
    if (m == null) return const {};
    return {m.from, ...m.movedCells}..removeWhere((c) => !c.onBoard);
  }

  /// Mise en évidence du coup qui a mené ici, comme en partie.
  LastMove? get lastMove {
    final m = move;
    final before = boardBefore;
    if (m == null || before == null) return null;
    return LastMove.of(before, m, pushTargets: pushTargetsOf(before, m));
  }
}

/// Pièces qui quittent le plateau sur ce coup — sans compter l'Héritier qui
/// fugue, qui n'est pas une prise mais une victoire.
List<Piece> _ejectedBy(Board before, Move move) {
  final out = <Piece>[];
  final after = <Piece, int>{};
  for (var c = 0; c < kCols; c++) {
    for (var r = 0; r < kRows; r++) {
      final p = move.board.at(c, r);
      if (p != null) after[p] = (after[p] ?? 0) + 1;
    }
  }
  final counts = Map.of(after);
  for (var c = 0; c < kCols; c++) {
    for (var r = 0; r < kRows; r++) {
      final p = before.at(c, r);
      if (p == null) continue;
      final left = counts[p] ?? 0;
      if (left > 0) {
        counts[p] = left - 1;
      } else {
        out.add(p);
      }
    }
  }
  // L'Héritier qui fugue sort aussi du plateau : on ne le compte pas.
  if (move.fugue || move.fugueBy != null) {
    out.removeWhere((p) => p.isHeir);
  }
  return out;
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

    final lost = <Camp, List<Piece>>{Camp.blanc: [], Camp.noir: []};
    final steps = <ReplayStep>[
      ReplayStep(
        board: start,
        turn: Camp.blanc,
        captured: {Camp.blanc: const [], Camp.noir: const []},
      ),
    ];

    var board = start;
    var turn = Camp.blanc;
    int? broken;

    for (var i = 0; i < game.moves.length; i++) {
      final notation = game.moves[i];
      final move = resolveNotation(board, turn, notation);
      if (move == null) {
        // Comme Kivy, on tente d'appliquer la notation à la lettre avant
        // d'abandonner : sa relecture ne confronte pas les coups aux règles.
        final literal = applyNotationLiterally(board, notation);
        if (literal == null) {
          broken = i;
          break;
        }
        board = literal.board;
        turn = turn.opposite;
        steps.add(
          ReplayStep(
            board: board,
            turn: turn,
            notation: notation,
            captured: {
              Camp.blanc: List.of(lost[Camp.blanc]!),
              Camp.noir: List.of(lost[Camp.noir]!),
            },
          ),
        );
        continue;
      }
      for (final piece in _ejectedBy(board, move)) {
        lost[piece.camp]!.add(piece);
      }
      steps.add(
        ReplayStep(
          board: move.board,
          turn: turn.opposite,
          notation: notation,
          move: move,
          boardBefore: board,
          captured: {
            Camp.blanc: List.of(lost[Camp.blanc]!),
            Camp.noir: List.of(lost[Camp.noir]!),
          },
        ),
      );
      board = move.board;
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
