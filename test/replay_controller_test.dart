/// Lecteur de parties : navigation, bornes, et parties illisibles.
library;

import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/nmc.dart';
import 'package:lafuga/game/replay_controller.dart';
import 'package:test/test.dart';

const _meta = NmcMeta(
  date: '2026-09-19',
  player1: 'Nino',
  player2: 'Deep Grey',
  blanc: 'Nino',
  objectif: 'partie',
  cadence: '5min',
  result: '1-0',
  method: 'fugue',
  points: '2',
);

/// Fabrique une partie de [count] coups légaux depuis la position de départ.
String gameOf(int count, {NmcMeta meta = _meta}) {
  var board = Board.initial();
  var camp = Camp.blanc;
  final moves = <String>[];

  for (var i = 0; i < count; i++) {
    final legal = generateMoves(
      board,
      camp,
    ).where((m) => !m.fugue && m.matOn == null && m.fugueBy == null).toList();
    final mv = legal[i % legal.length];
    moves.add(notationOn(board, mv));
    board = mv.board;
    camp = camp.opposite;
  }
  return buildNmc(meta, moves);
}

void main() {
  group('Ouverture', () {
    test("l'en-tête est relu", () {
      final r = ReplayController.fromNmc(gameOf(4));
      expect(r.meta.player1, 'Nino');
      expect(r.meta.player2, 'Deep Grey');
      expect(r.meta.result, '1-0');
    });

    test('on commence à la position de départ', () {
      final r = ReplayController.fromNmc(gameOf(4));
      expect(r.index, 0);
      expect(r.atStart, isTrue);
      expect(r.current.board.key, Board.initial().key);
      expect(r.current.turn, Camp.blanc);
      expect(r.current.notation, isNull, reason: 'aucun coup n a mené ici');
    });

    test('toutes les positions sont calculées à l ouverture', () {
      final r = ReplayController.fromNmc(gameOf(6));
      expect(r.moveCount, 6);
      expect(r.steps.length, 7, reason: 'départ + six coups');
    });

    test('une partie vide n a qu une position', () {
      final r = ReplayController.fromNmc(buildNmc(_meta, []));
      expect(r.moveCount, 0);
      expect(r.atStart, isTrue);
      expect(r.atEnd, isTrue);
    });

    test('une partie Random Fuga part de SA position', () {
      const meta = NmcMeta(
        date: '2026-09-19',
        player1: 'A',
        player2: 'B',
        blanc: 'A',
        objectif: 'partie',
        cadence: 'illimité',
        result: '½-½',
        method: 'nulle',
        points: '0',
        random: '.03-09',
      );
      final r = ReplayController.fromNmc(buildNmc(meta, []));
      expect(r.current.board.key, isNot(Board.initial().key));
    });
  });

  group('Navigation', () {
    test('avancer et reculer retrouvent les mêmes positions', () {
      final r = ReplayController.fromNmc(gameOf(4));
      final keys = [for (final s in r.steps) s.board.key];

      for (var i = 1; i <= 4; i++) {
        expect(r.next(), isTrue);
        expect(r.current.board.key, keys[i]);
      }
      for (var i = 3; i >= 0; i--) {
        expect(r.previous(), isTrue);
        expect(r.current.board.key, keys[i]);
      }
    });

    test('on ne dépasse pas les bornes', () {
      final r = ReplayController.fromNmc(gameOf(2));
      expect(r.previous(), isFalse, reason: 'déjà au début');
      r.toEnd();
      expect(r.next(), isFalse, reason: 'déjà à la fin');
    });

    test('début et fin sautent directement', () {
      final r = ReplayController.fromNmc(gameOf(5));
      expect(r.toEnd(), isTrue);
      expect(r.atEnd, isTrue);
      expect(r.index, 5);
      expect(r.toStart(), isTrue);
      expect(r.index, 0);
      expect(r.toStart(), isFalse, reason: 'rien n a changé');
    });

    test('on peut viser une position précise', () {
      final r = ReplayController.fromNmc(gameOf(5));
      expect(r.goTo(3), isTrue);
      expect(r.index, 3);
      expect(r.goTo(3), isFalse, reason: 'déjà là');
      expect(r.goTo(-1), isFalse);
      expect(r.goTo(99), isFalse);
      expect(r.index, 3, reason: 'une cible invalide ne bouge rien');
    });

    test('le trait alterne à chaque coup', () {
      final r = ReplayController.fromNmc(gameOf(4));
      expect(r.current.turn, Camp.blanc);
      r.next();
      expect(r.current.turn, Camp.noir);
      r.next();
      expect(r.current.turn, Camp.blanc);
    });
  });

  group('Mise en évidence', () {
    test('la position de départ n a rien à encadrer', () {
      final r = ReplayController.fromNmc(gameOf(2));
      expect(r.current.highlightedCells, isEmpty);
    });

    test('un coup encadre son départ et son arrivée', () {
      final r = ReplayController.fromNmc(gameOf(2));
      r.next();
      final cells = r.current.highlightedCells;
      expect(cells, isNotEmpty);
      for (final c in cells) {
        expect(c.onBoard, isTrue, reason: 'on n encadre pas hors plateau');
      }
    });
  });

  group('Partie illisible', () {
    test('la lecture s arrête au coup fautif et le signale', () {
      // Case de départ vide : rien à déplacer, même à la lettre.
      final content = buildNmc(_meta, ['Fa3-Fa4', 'Do4-Do5', 'Fa4-Fa5']);
      final r = ReplayController.fromNmc(content);

      expect(r.isTruncated, isTrue);
      expect(r.brokenMoveNumber, 2, reason: 'le deuxième coup est impossible');
      expect(r.moveCount, 1, reason: 'seul le premier coup a été rejoué');
    });

    test('un coup hors règles est tout de même rejoué', () {
      // Comme Kivy, qui applique la notation sans vérifier sa légalité.
      final content = buildNmc(_meta, ['Fa3-Fa4', 'Si8-Si7']);
      final r = ReplayController.fromNmc(content);

      expect(r.isTruncated, isFalse);
      expect(r.moveCount, 2);
    });

    test('une partie entièrement lisible ne signale rien', () {
      final r = ReplayController.fromNmc(gameOf(4));
      expect(r.isTruncated, isFalse);
      expect(r.brokenMoveNumber, isNull);
    });
  });

  group('Contenu lisible', () {
    test('une vraie partie est acceptée', () {
      expect(isReadableNmc(gameOf(4)), isTrue);
    });

    test('un en-tête seul suffit : la partie n a pas encore de coup', () {
      expect(isReadableNmc(buildNmc(_meta, [])), isTrue);
    });

    test('du texte quelconque est refusé', () {
      expect(isReadableNmc('n importe quoi'), isFalse);
      expect(isReadableNmc(''), isFalse);
    });

    test('un premier coup impossible est refusé', () {
      expect(isReadableNmc(buildNmc(_meta, ['Do4-Do5'])), isFalse);
    });
  });

  group('Bandeau des coups', () {
    test('les coups sont groupés par tour', () {
      final r = ReplayController.fromNmc(gameOf(5));
      final pairs = r.movePairs;

      expect(pairs.length, 3, reason: '5 demi-coups = 3 tours');
      expect(pairs[0].turn, 1);
      expect(pairs[0].blanc, isNotNull);
      expect(pairs[0].noir, isNotNull);
      expect(pairs[2].noir, isNull, reason: 'le dernier tour est incomplet');
    });

    test('une partie vide n a aucun tour', () {
      final r = ReplayController.fromNmc(buildNmc(_meta, []));
      expect(r.movePairs, isEmpty);
    });
  });
}
