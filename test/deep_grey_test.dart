/// Deep Grey : l'IA doit choisir des coups sensés, et surtout ne jamais
/// bloquer le thread appelant — c'est le gel du chrono qu'on corrige.
library;

import 'package:lafuga/engine/ai/deep_grey_isolate.dart';
import 'package:lafuga/engine/ai/evaluation.dart';
import 'package:lafuga/engine/ai/search.dart';
import 'package:lafuga/engine/ai/weights.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:test/test.dart';

void main() {
  group('Choix de coup', () {
    test('joue la fugue quand elle est disponible', () {
      final b = Board.empty();
      b.set(3, 7, Piece.blancHeritier); // fa8, à une case du ralliement
      b.set(3, 6, Piece.blancNurse); // voisine : débloque l'Héritier
      b.set(0, 0, Piece.noirNurse);
      b.set(0, 1, Piece.noirNurse);

      final mv = chooseMove(b, Camp.blanc, depth: 2);
      expect(mv, isNotNull);
      expect(
        mv!.fugue,
        isTrue,
        reason: 'la victoire immédiate passe avant tout',
      );
    });

    test('ne se laisse pas fuguer quand il peut l éviter', () {
      final b = Board.initial();
      final mv = chooseMove(b, Camp.blanc, depth: 2);
      expect(mv, isNotNull);
      expect(
        mv!.fugueBy,
        isNot(Camp.noir),
        reason: 'ne jamais offrir la fugue à l adversaire',
      );
    });

    test("n'éjecte pas ses propres pièces sans gagner", () {
      final b = Board.initial();
      final mv = chooseMove(b, Camp.blanc, depth: 2)!;
      if (mv.ejAlly > 0) {
        expect(
          mv.fugue || mv.fugueBy == Camp.blanc || mv.matOn == Camp.noir,
          isTrue,
          reason: 'auto-éjection tolérée seulement si le coup gagne',
        );
      }
    });

    test('retourne null sans coup possible', () {
      final b = Board.empty();
      b.set(0, 0, Piece.blancNurse); // isolée : immobile
      expect(chooseMove(b, Camp.blanc, depth: 2), isNull);
    });

    test('le coup choisi est toujours un coup légal', () {
      var b = Board.initial();
      var camp = Camp.blanc;
      for (var ply = 0; ply < 12; ply++) {
        final mv = chooseMove(b, camp, depth: 2);
        if (mv == null) break;
        final legal = generateMoves(b, camp);
        expect(
          legal.map((m) => m.board.key),
          contains(mv.board.key),
          reason: 'demi-coup $ply',
        );
        if (mv.fugue || mv.matOn != null || mv.fugueBy != null) break;
        b = mv.board;
        camp = camp.opposite;
      }
    });

    test('le mode profond choisit aussi un coup légal', () {
      final b = Board.initial();
      final mv = chooseMoveTopN(b, Camp.blanc, topN: 5);
      expect(mv, isNotNull);
      expect(
        generateMoves(b, Camp.blanc).map((m) => m.board.key),
        contains(mv!.board.key),
      );
    });
  });

  group('Pénalité de répétition', () {
    test('ne pénalise rien avant la 3e occurrence', () {
      final b = Board.initial();
      final key = b.ownPiecesKey(Camp.blanc);
      expect(repetitionPenalty(b, Camp.blanc, {key: 0}), 0);
      expect(repetitionPenalty(b, Camp.blanc, {key: 1}), 0);
    });

    test('croît en carré à partir de la 3e', () {
      final b = Board.initial();
      final key = b.ownPiecesKey(Camp.blanc);
      expect(repetitionPenalty(b, Camp.blanc, {key: 2}), -150);
      expect(repetitionPenalty(b, Camp.blanc, {key: 3}), -600);
      expect(repetitionPenalty(b, Camp.blanc, {key: 4}), -1350);
    });
  });

  group('Poids appris', () {
    test('valeur par défaut 1.0 pour toute catégorie', () {
      final w = DeepGreyWeights();
      for (final cat in kWeightCategories) {
        expect(w[cat], 1.0, reason: cat);
      }
      expect(w['categorie_inconnue'], 1.0);
    });

    test("l'apprentissage reste dans [0.60, 1.40]", () {
      var w = DeepGreyWeights();
      final board = Board.initial();
      // Beaucoup de parties : les poids doivent saturer, jamais déborder.
      for (var i = 0; i < 200; i++) {
        w = w.learn(Camp.blanc, board);
      }
      for (final cat in kWeightCategories) {
        expect(w[cat], greaterThanOrEqualTo(kWeightMin), reason: cat);
        expect(w[cat], lessThanOrEqualTo(kWeightMax), reason: cat);
      }
    });

    test('un poids bouge d au plus 0.03 par partie', () {
      final before = DeepGreyWeights();
      final after = before.learn(Camp.blanc, Board.initial());
      for (final cat in kWeightCategories) {
        expect(
          (after[cat] - before[cat]).abs(),
          lessThanOrEqualTo(kWeightStep + 1e-9),
          reason: cat,
        );
      }
    });

    test('aller-retour JSON', () {
      final w = DeepGreyWeights().learn(Camp.noir, Board.initial());
      final back = DeepGreyWeights.fromJsonString(w.toJsonString());
      for (final cat in kWeightCategories) {
        expect(back[cat], closeTo(w[cat], 1e-9), reason: cat);
      }
    });

    test('un JSON corrompu retombe sur les valeurs par défaut', () {
      final w = DeepGreyWeights.fromJsonString('pas du json');
      expect(w['heir_adv'], 1.0);
    });
  });

  group('Évaluation', () {
    test('le cache renvoie la même valeur', () {
      final b = Board.initial();
      final cache = EvalCache();
      final w = DeepGreyWeights();
      final first = evaluate(b, Camp.blanc, weights: w, cache: cache);
      final second = evaluate(b, Camp.blanc, weights: w, cache: cache);
      expect(second, first);
      expect(cache.length, greaterThan(0));
      cache.clear();
      expect(cache.length, 0);
    });

    test('la menace de fugue adverse domine le score', () {
      final safe = Board.initial();
      final threatened = Board.empty();
      threatened.set(3, 0, Piece.noirHeritier); // à une case de SON ralliement
      threatened.set(3, 1, Piece.noirNurse);
      threatened.set(6, 7, Piece.blancNurse);
      threatened.set(6, 6, Piece.blancNurse);

      final w = DeepGreyWeights();
      final scoreSafe = evaluate(safe, Camp.blanc, weights: w);
      final scoreThreat = evaluate(threatened, Camp.blanc, weights: w);
      expect(
        scoreThreat,
        lessThan(scoreSafe),
        reason: 'se faire fuguer est le pire',
      );
    });

    test('la hiérarchie des coups décisifs est respectée', () {
      final b = Board.empty();
      b.set(3, 7, Piece.blancHeritier);
      b.set(3, 6, Piece.blancNurse);
      final fugueMove = generateMoves(b, Camp.blanc).firstWhere((m) => m.fugue);
      expect(moveBonus(fugueMove, Camp.blanc), 200000);
    });
  });

  group('Isolate', () {
    late DeepGreyEngine engine;

    setUp(() async {
      engine = DeepGreyEngine();
      await engine.start();
    });

    tearDown(() => engine.dispose());

    test('calcule un coup hors du thread appelant', () async {
      final result = await engine.think(
        board: Board.initial(),
        camp: Camp.blanc,
        deepMode: false,
      );
      expect(result.hasMove, isTrue);
      expect(result.notation, isNotEmpty);
      expect(result.board, isNotNull);
      expect(result.elapsedMicros, greaterThan(0));
    });

    test("le thread appelant reste libre pendant la réflexion", () async {
      // On lance une réflexion en mode profond (le plus coûteux) et on compte
      // les tours de boucle d'événements pendant ce temps. Si l'isolate ne
      // faisait pas son travail, le thread appelant serait bloqué et le
      // compteur resterait à zéro — c'est exactement le gel du chrono.
      var ticks = 0;
      var running = true;
      Future<void> tick() async {
        while (running) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          ticks++;
        }
      }

      final ticker = tick();
      final result = await engine.think(
        board: Board.initial(),
        camp: Camp.blanc,
        deepMode: true,
        moveNumber: 20, // hors phase d'ouverture : vraie recherche complète
      );
      running = false;
      await ticker;

      expect(result.hasMove, isTrue);
      expect(
        ticks,
        greaterThan(0),
        reason: 'le thread appelant doit continuer à tourner',
      );
    });

    test('plusieurs réflexions successives sur le même isolate', () async {
      for (var i = 0; i < 3; i++) {
        final r = await engine.think(
          board: Board.initial(),
          camp: i.isEven ? Camp.blanc : Camp.noir,
          deepMode: false,
        );
        expect(r.hasMove, isTrue, reason: 'réflexion $i');
      }
    });

    test('une position sans coup renvoie un résultat vide', () async {
      final b = Board.empty();
      b.set(0, 0, Piece.blancNurse);
      final r = await engine.think(board: b, camp: Camp.blanc, deepMode: false);
      expect(r.hasMove, isFalse);
      expect(r.notation, isNull);
    });
  });
}
