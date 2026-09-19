/// Ce que Deep Grey apprend : ses poids, son livre d'ouvertures, et la façon
/// dont l'isolate s'en sert.
library;

import 'dart:io';

import 'package:lafuga/engine/ai/deep_grey_isolate.dart';
import 'package:lafuga/engine/ai/opening_book.dart';
import 'package:lafuga/engine/ai/weights.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/state/ai_memory.dart';
import 'package:test/test.dart';

void main() {
  group('Mémoire sur disque', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('lafuga_ai'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('sans rien enregistré, l IA part des poids par défaut', () async {
      final memory = AiMemory(directory: tmp);

      expect((await memory.weights())['heir_safety'], 1.0);
      expect((await memory.book()).isEmpty, isTrue);
    });

    test('les poids appris survivent à la partie', () async {
      final learned = DeepGreyWeights().learn(Camp.blanc, Board.initial());
      await AiMemory(directory: tmp).saveWeights(learned);

      final reread = await AiMemory(directory: tmp).weights();
      expect(reread.values, learned.values);
      expect(
        File('${tmp.path}/${AiMemory.weightsFile}').existsSync(),
        isTrue,
        reason: 'même nom de fichier qu en Kivy',
      );
    });

    test('le livre survit aussi', () async {
      final book = OpeningBook();
      final first = notationOn(
        Board.initial(),
        generateMoves(Board.initial(), Camp.blanc).first,
      );
      book.recordWinningLine(
        initialBoard: Board.initial(),
        moves: [first],
        winner: Camp.blanc,
      );
      await AiMemory(directory: tmp).saveBook(book);

      final reread = await AiMemory(directory: tmp).book();
      expect(reread.lookup(Board.initial(), Camp.blanc), first);
      expect(File('${tmp.path}/${AiMemory.openingsFile}').existsSync(), isTrue);
    });

    test('un dossier inaccessible ne fait pas échouer la partie', () async {
      final memory = AiMemory(directory: Directory('/nulle/part'));

      await expectLater(memory.saveWeights(DeepGreyWeights()), completes);
      expect((await memory.weights())['heir_safety'], 1.0);
    });
  });

  group('Isolate et livre d ouvertures', () {
    late DeepGreyEngine engine;

    setUp(() async {
      engine = DeepGreyEngine();
      await engine.start();
    });

    tearDown(() => engine.dispose());

    test('un coup connu est joué sans réfléchir', () async {
      // Un coup sans danger, et sûrement pas celui que la recherche choisirait.
      final wanted = notationOn(
        Board.initial(),
        generateMoves(
          Board.initial(),
          Camp.blanc,
        ).lastWhere((m) => m.ejAlly == 0 && m.kind == MoveKind.move),
      );

      final result = await engine.think(
        board: Board.initial(),
        camp: Camp.blanc,
        deepMode: true,
        bookMove: bookNotation(wanted),
      );

      expect(result.notation, wanted);
      expect(
        result.elapsedMicros,
        lessThan(500000),
        reason: 'le livre évite la recherche',
      );
    });

    test('un coup du livre qui sacrifie nos pièces est refusé', () async {
      // Le garde-fou de Kivy : un coup mémorisé qui éjecte nos propres pièces
      // sans rien gagner n'est pas rejoué les yeux fermés.
      final sacrifice = generateMoves(
        Board.initial(),
        Camp.blanc,
      ).firstWhere((m) => m.ejAlly > 0 && !m.fugue && m.matOn == null);
      final notation = notationOn(Board.initial(), sacrifice);

      final result = await engine.think(
        board: Board.initial(),
        camp: Camp.blanc,
        deepMode: false,
        bookMove: bookNotation(notation),
      );

      expect(result.hasMove, isTrue);
      expect(result.notation, isNot(notation));
    });

    test('un coup du livre introuvable renvoie à la réflexion', () async {
      final result = await engine.think(
        board: Board.initial(),
        camp: Camp.blanc,
        deepMode: false,
        bookMove: 'Do9-Do9',
      );

      expect(result.hasMove, isTrue, reason: 'on joue quand même');
    });

    test('une troisième manœuvre consécutive est évitée', () async {
      final result = await engine.think(
        board: Board.initial(),
        camp: Camp.blanc,
        deepMode: false,
        avoidManeuver: true,
      );

      expect(result.hasMove, isTrue);
      expect(result.kind, isNot(MoveKind.maneuver.name));
    });
  });
}
