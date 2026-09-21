/// Deep Grey ne doit jamais laisser l'écran suspendu.
///
/// Une réflexion qui échoue, un isolate qui meurt, une réponse qui se perd :
/// dans tous les cas l'appelant doit recevoir une réponse. Sans cela l'écran
/// reste sur « réfléchit… » pour toujours, ce qui se voit comme un plantage.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/ai/deep_grey_isolate.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/piece.dart';

void main() {
  test('une réponse « pas de coup » se construit sans rien casser', () {
    final none = ThinkResult.none(7);
    expect(none.id, 7);
    expect(none.hasMove, isFalse);
    expect(none.board, isNull);
    expect(none.pushTargets, isEmpty);
  });

  test('réfléchir sur un moteur arrêté répond au lieu de tomber', () async {
    final engine = DeepGreyEngine();
    final result = await engine
        .think(board: Board.initial(), camp: Camp.blanc, deepMode: false)
        .timeout(const Duration(seconds: 20));
    expect(result.hasMove, isTrue, reason: 'le moteur démarre tout seul');
    engine.dispose();
  });

  test('après dispose, une demande répond encore', () async {
    final engine = DeepGreyEngine();
    await engine.start();
    engine.dispose();

    final result = await engine
        .think(board: Board.initial(), camp: Camp.blanc, deepMode: false)
        .timeout(const Duration(seconds: 20));
    expect(result, isNotNull);
    engine.dispose();
  });

  test('une position sans aucun coup répond « pas de coup »', () async {
    final engine = DeepGreyEngine();
    final result = await engine
        .think(board: Board.empty(), camp: Camp.blanc, deepMode: false)
        .timeout(const Duration(seconds: 20));
    expect(result.hasMove, isFalse);
    engine.dispose();
  });
}
