/// Les pièces capturées affichées sont exactement celles qui ont quitté le
/// plateau.
///
/// Le panneau d'un joueur montre les pièces que l'autre a perdues. Elles se
/// comptaient jusqu'ici au moment de la poussée, dans `_applyPush` — donc
/// seulement pour les coups joués au doigt. Un coup venu d'ailleurs — Deep
/// Grey, le réseau — passe par `applyGeneratedMove`, qui ne les comptait pas.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/game/move_controller.dart';

/// Toutes les pièces du plateau, en sac.
List<Piece> piecesOf(Board b) => [
  for (var c = 0; c < kCols; c++)
    for (var r = 0; r < kRows; r++)
      if (b.at(c, r) != null) b.at(c, r)!,
];

/// Ce qui a disparu entre deux plateaux, l'Héritier fugué mis à part.
List<Piece> missing(Board before, Board after) {
  final rest = piecesOf(after);
  final out = <Piece>[];
  for (final p in piecesOf(before)) {
    if (rest.remove(p)) continue;
    out.add(p);
  }
  return out;
}

int totalCaptured(MoveController g) =>
    g.captured[Camp.blanc]!.length + g.captured[Camp.noir]!.length;

/// Cherche un coup qui éjecte au moins une pièce, en jouant au hasard.
({MoveController game, Move move})? findEjectingMove() {
  var game = MoveController();
  var seed = 0;
  for (var ply = 0; ply < 200; ply++) {
    final moves = generateMoves(game.board, game.turn);
    if (moves.isEmpty) return null;
    final ejecting = moves.firstWhere(
      (m) => m.ejected > 0 && !m.fugue && m.matOn == null,
      orElse: () => moves.first,
    );
    if (ejecting.ejected > 0 && !ejecting.fugue && ejecting.matOn == null) {
      return (game: game, move: ejecting);
    }
    final quiet = moves
        .where((m) => m.ejected == 0 && !m.fugue && m.matOn == null)
        .toList();
    if (quiet.isEmpty) return null;
    seed = (seed * 31 + 17) % quiet.length;
    game.applyGeneratedMove(quiet[seed]);
    if (game.gameOver) {
      game = MoveController();
      seed++;
    }
  }
  return null;
}

/// Joue au hasard jusqu'à obtenir une partie qui a coûté des pièces, et rend
/// ses notations, une par ligne — le `moves_text` du serveur.
({String movesText, int pertes})? gameWithLosses() {
  final rnd = Random(4);
  for (var essai = 0; essai < 60; essai++) {
    final game = MoveController();
    final depart = game.board.clone();
    final lignes = <String>[];
    for (var ply = 0; ply < 50 && !game.gameOver; ply++) {
      final moves = generateMoves(game.board, game.turn);
      if (moves.isEmpty) break;
      final mv = moves[rnd.nextInt(moves.length)];
      lignes.add(notationOn(game.board, mv));
      game.applyGeneratedMove(mv);
    }
    final pertes = missing(depart, game.board).length;
    if (pertes >= 3 && lignes.length > 6) {
      return (movesText: lignes.join('\n'), pertes: pertes);
    }
  }
  return null;
}

/// Une partie de correspondance telle que le serveur la décrit.
Map<String, dynamic> corrJson(String movesText) => {
  'id': 'g1',
  'statut': 'en_cours',
  'ma_couleur': 'Blanc',
  'adversaire': 'Adversaire',
  'turn': 'Blanc',
  'moves_text': movesText,
  'my_turn': true,
  'coups': movesText,
};

void main() {
  test('un coup venu d ailleurs compte ses prises', () {
    final found = findEjectingMove();
    expect(found, isNotNull, reason: 'aucune éjection trouvée');
    final game = found!.game;
    final before = game.board.clone();
    final avant = totalCaptured(game);

    game.applyGeneratedMove(found.move);

    final parties = missing(before, game.board);
    expect(parties, isNotEmpty, reason: 'ce coup éjecte bien quelque chose');
    expect(
      totalCaptured(game) - avant,
      parties.length,
      reason: 'Deep Grey et le réseau doivent remplir les panneaux aussi',
    );
    for (final p in parties) {
      expect(
        game.captured[p.camp],
        contains(p),
        reason: 'la pièce perdue va au panneau de SON camp',
      );
    }
  });

  test('sur des parties entières, le tableau des prises ne dérive jamais', () {
    final rnd = Random(20260925);
    var ejections = 0, parties = 0;

    for (var partie = 0; partie < 60; partie++) {
      final game = MoveController();
      final depart = game.board.clone();
      parties++;

      for (var ply = 0; ply < 60 && !game.gameOver; ply++) {
        final moves = generateMoves(game.board, game.turn);
        if (moves.isEmpty) break;
        game.applyGeneratedMove(moves[rnd.nextInt(moves.length)]);

        // Les prises affichées doivent être EXACTEMENT les pièces absentes du
        // plateau, à l'Héritier fugué près.
        final absentes = missing(depart, game.board)
          ..removeWhere((p) => p.isHeir && game.fuguedHeirs.contains(p.camp));
        final montrees = [
          ...game.captured[Camp.blanc]!,
          ...game.captured[Camp.noir]!,
        ];
        expect(
          _bag(montrees),
          _bag(absentes),
          reason:
              'partie $partie, coup $ply :\n\${game.board.render()}'
              'affichées \$montrees, absentes \$absentes',
        );
        ejections += absentes.length;
      }
    }
    expect(parties, 60);
    expect(ejections, greaterThan(100), reason: 'assez d éjections vues');
  });

  test('annuler un coup rend les pièces qu il avait poussées dehors', () {
    // Un Soldat blanc qui se déplace tout droit active sa poussée diagonale.
    // La Nurse noire qu'il pousse n'a plus de case derrière elle : elle sort.
    final board = Board.empty();
    board.set(3, 1, Piece.blancSoldat);
    board.set(
      3,
      2,
      Piece.blancGarde,
    ); // voisine carrée, sinon le Soldat est figé
    board.set(1, 0, Piece.noirNurse);
    final game = MoveController(board: board, turn: Camp.blanc);

    game.tapCell(const Cell(3, 1));
    expect(game.selected, const Cell(3, 1));
    final moved = game.tapCell(const Cell(2, 1));
    expect(moved.effect, isNot(ControllerEffect.none), reason: 'il se déplace');

    final pushed = game.tapCell(const Cell(1, 0));
    expect(
      pushed.effect,
      isNot(ControllerEffect.none),
      reason: 'la poussée diagonale part',
    );
    expect(game.board.at(1, 0), isNull, reason: 'la Nurse a quitté le plateau');
    expect(totalCaptured(game), 1, reason: 'elle est comptée');

    expect(game.cancelCurrentMove(), isTrue);
    expect(
      totalCaptured(game),
      0,
      reason: 'un coup annulé ne laisse pas de prise au tableau',
    );
    expect(game.board.at(1, 0), Piece.noirNurse, reason: 'elle est revenue');

    // Et rejouer le même coup ne la compte pas deux fois.
    game.tapCell(const Cell(3, 1));
    game.tapCell(const Cell(2, 1));
    game.tapCell(const Cell(1, 0));
    expect(totalCaptured(game), 1);
  });

  test('en correspondance, les prises des coups déjà joués sont là', () {
    clearReplayCache();
    final partie = gameWithLosses();
    expect(partie, isNotNull, reason: 'aucune partie avec pertes trouvée');

    final game = CorrGame.fromJson(corrJson(partie!.movesText));
    final state = replay(game);
    final montrees = [
      ...state.captured[Camp.blanc]!,
      ...state.captured[Camp.noir]!,
    ];
    expect(
      montrees,
      hasLength(partie.pertes),
      reason: 'une partie reprise en route affiche ce qui a été pris',
    );

    // Et le contrôleur ouvert dessus les reçoit, sans les perdre à la
    // première annulation.
    final controller = MoveController(
      board: state.board,
      turn: state.turn,
      captured: state.captured,
    );
    expect(totalCaptured(controller), partie.pertes);
    controller.tapCell(const Cell(3, 0));
    controller.cancelCurrentMove();
    expect(
      totalCaptured(controller),
      partie.pertes,
      reason: 'annuler un coup ne doit pas effacer les prises d avant',
    );
  });

  test('en ligne, le coup reçu de l adversaire compte ses prises', () {
    final found = findEjectingMove();
    expect(found, isNotNull);
    final game = found!.game;
    final before = game.board.clone();
    final avant = totalCaptured(game);

    // Les deux gestes exacts d'`OnlineGame._onOpponentMove` : la notation
    // reçue est résolue en coup légal, puis appliquée.
    final notation = notationOn(game.board, found.move);
    final move = resolveNotation(game.board, game.turn, notation);
    expect(move, isNotNull, reason: 'la notation se résout');
    game.applyGeneratedMove(move!);

    final parties = missing(before, game.board);
    expect(parties, isNotEmpty);
    expect(
      totalCaptured(game) - avant,
      parties.length,
      reason: 'le panneau de l adversaire se remplit aussi en ligne',
    );
  });
}

/// Compte des pièces, sans tenir compte de l'ordre.
Map<Piece, int> _bag(List<Piece> pieces) {
  final out = <Piece, int>{};
  for (final p in pieces) {
    out[p] = (out[p] ?? 0) + 1;
  }
  return out;
}
