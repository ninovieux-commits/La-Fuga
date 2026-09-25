/// Les menaces calculées directement doivent être EXACTEMENT celles que donne
/// le générateur de coups. C'est la force de jeu de Deep Grey qui en dépend :
/// une fugue manquée, et l'IA laisse gagner.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/engine/threats.dart';

/// Ce que le générateur de coups répond, en construisant tous les coups.
({bool canFugue, bool matBlanc, bool matNoir}) referenceThreats(
  Board board,
  Camp camp,
) {
  var canFugue = false, matBlanc = false, matNoir = false;
  for (final mv in generateMoves(board, camp)) {
    if (mv.fugue || mv.fugueBy == camp) canFugue = true;
    if (mv.matOn == Camp.blanc) matBlanc = true;
    if (mv.matOn == Camp.noir) matNoir = true;
  }
  return (canFugue: canFugue, matBlanc: matBlanc, matNoir: matNoir);
}

void main() {
  test('menaces directes == menaces du générateur, sur des parties tirées au sort', () {
    final rnd = Random(20260921);
    var positions = 0, fugues = 0, mats = 0;

    for (var game = 0; game < 400; game++) {
      var board = Board.initial();
      var camp = Camp.blanc;

      for (var ply = 0; ply < 40; ply++) {
        for (final side in Camp.values) {
          final expected = referenceThreats(board, side);
          final got = threatsOf(board, side);

          expect(
            got.canFugue,
            expected.canFugue,
            reason: 'fugue de ${side.wire}, partie $game coup $ply\n${board.render()}',
          );
          if (!expected.canFugue) {
            expect(
              got.matOnBlanc,
              expected.matBlanc,
              reason: 'mat sur Blanc par ${side.wire}, partie $game coup $ply\n${board.render()}',
            );
            expect(
              got.matOnNoir,
              expected.matNoir,
              reason: 'mat sur Noir par ${side.wire}, partie $game coup $ply\n${board.render()}',
            );
          }
          // `campCanFugue` passe désormais par la détection directe : il doit
          // répondre exactement comme la boucle sur les coups générés.
          expect(
            campCanFugue(board, side),
            expected.canFugue,
            reason: 'campCanFugue ${side.wire}, partie $game coup $ply',
          );
          if (expected.canFugue) fugues++;
          if (expected.matBlanc || expected.matNoir) mats++;
          positions++;
        }

        final moves = generateMoves(board, camp);
        if (moves.isEmpty) break;
        final mv = moves[rnd.nextInt(moves.length)];
        if (mv.fugue || mv.fugueBy != null || mv.matOn != null) break;
        board = mv.board;
        camp = camp.opposite;
      }
    }

    // La couverture compte autant que l'égalité : un test qui ne rencontre
    // jamais de fugue ne prouve rien.
    expect(positions, greaterThan(10000));
    expect(fugues, greaterThan(100));
    expect(mats, greaterThan(100));
    // ignore: avoid_print
    print('$positions positions, $fugues avec fugue possible, $mats avec mat possible');
  });
}
