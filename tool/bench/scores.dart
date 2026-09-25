import 'dart:io';
import 'dart:math';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/ai/evaluation.dart';
import 'package:lafuga/engine/ai/weights.dart';

void main(List<String> args) {
  final rnd = Random(7);
  final w = DeepGreyWeights({
    'heir_adv': 1.13,
    'nurse_mat': 0.77,
    'square_push': 1.31,
  });
  final out = StringBuffer();
  for (var g = 0; g < 200; g++) {
    var b = Board.initial();
    var camp = Camp.blanc;
    for (var ply = 0; ply < 25; ply++) {
      out.writeln(positionalStrategy(b, Camp.blanc, w).toStringAsFixed(12));
      out.writeln(positionalStrategy(b, Camp.noir, w).toStringAsFixed(12));
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
