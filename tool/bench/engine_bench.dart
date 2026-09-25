// Mesure des points chauds du moteur, en meilleur-de-5 pour lisser le bruit.
// ignore_for_file: avoid_print
// Lancer : dart run tool/bench/engine_bench.dart
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/ai/evaluation.dart';
import 'package:lafuga/engine/ai/search.dart';
import 'package:lafuga/engine/ai/weights.dart';
import 'package:lafuga/engine/threats.dart';

double us(void Function() f, int n) {
  for (var i = 0; i < n ~/ 5 + 1; i++) {
    f();
  }
  var best = double.infinity;
  for (var pass = 0; pass < 5; pass++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < n; i++) {
      f();
    }
    final v = sw.elapsedMicroseconds / n;
    if (v < best) best = v;
  }
  return best;
}

String ms(double micros) => '${(micros / 1000).toStringAsFixed(1)} ms';

void main() {
  var mid = Board.initial();
  var camp = Camp.blanc;
  for (var i = 0; i < 12; i++) {
    final mvs = generateMoves(mid, camp);
    mid = mvs[(i * 37) % mvs.length].board;
    camp = camp.opposite;
  }
  final w = DeepGreyWeights();

  print(
    'clone              ${us(() => mid.clone(), 200000).toStringAsFixed(3)} us',
  );
  print(
    'key (froid)        ${us(() {
      final c = mid.clone();
      c.set(0, 0, null);
      c.key;
    }, 100000).toStringAsFixed(3)} us',
  );
  print(
    'generateMoves      ${us(() => generateMoves(mid, Camp.blanc), 3000).toStringAsFixed(1)} us',
  );
  print(
    'positionalStrategy ${us(() => positionalStrategy(mid, Camp.blanc, w), 30000).toStringAsFixed(1)} us',
  );
  print(
    'threatsOf (2 camps)${us(() {
      threatsOf(mid, Camp.blanc);
      threatsOf(mid, Camp.noir);
    }, 30000).toStringAsFixed(1)} us',
  );
  print(
    'evaluate (froid)   ${us(() => evaluate(mid, Camp.blanc, weights: w), 5000).toStringAsFixed(1)} us',
  );
  print(
    'chooseMove d2      ${ms(us(() => chooseMove(mid, Camp.blanc, depth: 2), 6))}',
  );
  print(
    'chooseMoveTopN     ${ms(us(() => chooseMoveTopN(mid, Camp.blanc), 4))}',
  );
  final cache = EvalCache();
  chooseMoveTopN(mid, Camp.blanc, context: SearchContext(cache: cache));
  print('  positions en cache ${cache.length}');
  print(
    '  (initiale)       ${ms(us(() => chooseMoveTopN(Board.initial(), Camp.blanc, moveNumber: 20), 4))}',
  );
}
