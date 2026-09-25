// Coups choisis par Deep Grey sur une série de positions, avec un hasard figé.
// Sert à comparer deux versions du moteur : la liste doit être identique.
import 'dart:io';
import 'dart:math';

import 'package:lafuga/engine/ai/evaluation.dart';
import 'package:lafuga/engine/ai/search.dart';
import 'package:lafuga/engine/ai/weights.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';

void main(List<String> args) {
  final rnd = Random(4242);
  final w = DeepGreyWeights({
    'heir_adv': 1.13,
    'nurse_mat': 0.77,
    'square_push': 1.31,
    'heir_contact': 0.88,
  });
  final out = StringBuffer();

  for (var g = 0; g < 30; g++) {
    var b = Board.initial();
    var camp = Camp.blanc;
    for (var ply = 0; ply < 14; ply++) {
      final seen = <String, int>{b.ownPiecesKey(camp): 2};
      final d2 = chooseMove(
        b,
        camp,
        depth: 2,
        context: SearchContext(
          weights: w,
          cache: EvalCache(),
          seenPositions: seen,
          random: Random(1),
        ),
      );
      final top = chooseMoveTopN(
        b,
        camp,
        context: SearchContext(
          weights: w,
          cache: EvalCache(),
          seenPositions: seen,
          random: Random(1),
        ),
      );
      out.writeln(d2 == null ? '-' : notationOn(b, d2));
      out.writeln(top == null ? '-' : notationOn(b, top));

      final mvs = generateMoves(b, camp);
      if (mvs.isEmpty) break;
      final mv = mvs[rnd.nextInt(mvs.length)];
      if (mv.fugue || mv.fugueBy != null || mv.matOn != null) break;
      b = mv.board;
      camp = camp.opposite;
    }
  }
  File(args[0]).writeAsStringSync(out.toString());
}
