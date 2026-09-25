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

  test('un isolate qui meurt est remplacé au coup suivant', () async {
    final engine = DeepGreyEngine();
    await engine.start();
    final first = await engine
        .think(board: Board.initial(), camp: Camp.blanc, deepMode: false)
        .timeout(const Duration(seconds: 20));
    expect(first.hasMove, isTrue);

    // Panne : l'isolate disparaît en pleine partie.
    engine.debugKill();
    // Laisser arriver l'avis de décès.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(engine.isRunning, isFalse, reason: 'le moteur sait qu il est mort');

    // Le coup suivant doit repartir sur un isolate neuf, et VRAIMENT jouer.
    final second = await engine
        .think(board: Board.initial(), camp: Camp.blanc, deepMode: false)
        .timeout(const Duration(seconds: 20));
    expect(
      second.hasMove,
      isTrue,
      reason: 'Deep Grey rejoue après une panne au lieu de rester muet',
    );
    engine.dispose();
  });

  test('deux demandes simultanées ne lancent qu un isolate', () async {
    final engine = DeepGreyEngine();
    final both = await Future.wait([
      engine.think(board: Board.initial(), camp: Camp.blanc, deepMode: false),
      engine.think(board: Board.initial(), camp: Camp.noir, deepMode: false),
    ]).timeout(const Duration(seconds: 30));
    expect(both[0].hasMove, isTrue);
    expect(both[1].hasMove, isTrue);
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
