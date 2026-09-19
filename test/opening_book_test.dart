/// Livre d'ouvertures : ce que Deep Grey retient des parties qu'il perd.
library;

import 'package:lafuga/engine/ai/opening_book.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:test/test.dart';

/// Une suite de coups légaux depuis la position de départ.
List<String> legalLine(int count) {
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
  return moves;
}

void main() {
  group('Notation rangée', () {
    test('la marque de fin est retirée', () {
      expect(bookNotation('Do1-Do2#'), 'Do1-Do2');
      expect(bookNotation('Mi7*'), 'Mi7');
      expect(bookNotation('  Fa2-Fa3  '), 'Fa2-Fa3');
    });
  });

  group('Enregistrement', () {
    test('seuls les coups du gagnant sont retenus', () {
      final line = legalLine(4);
      final book = OpeningBook();

      expect(
        book.recordWinningLine(
          initialBoard: Board.initial(),
          moves: line,
          winner: Camp.blanc,
        ),
        isTrue,
      );

      // Deux coups blancs sur quatre demi-coups.
      expect(book.positionCount, 2);
      expect(book.lookup(Board.initial(), Camp.blanc), line[0]);
      expect(
        book.lookup(Board.initial(), Camp.noir),
        isNull,
        reason: 'le perdant n apprend rien à personne',
      );
    });

    test('un coup revu compte double', () {
      final line = legalLine(2);
      final book = OpeningBook();
      for (var i = 0; i < 2; i++) {
        book.recordWinningLine(
          initialBoard: Board.initial(),
          moves: line,
          winner: Camp.blanc,
        );
      }

      expect(book.countOf(Board.initial(), Camp.blanc, line[0]), 2);
    });

    test('le coup le plus souvent gagnant l emporte', () {
      final a = legalLine(1);
      final b = [
        notationOn(
          Board.initial(),
          generateMoves(Board.initial(), Camp.blanc)[1],
        ),
      ];
      final book = OpeningBook();

      book.recordWinningLine(
        initialBoard: Board.initial(),
        moves: b,
        winner: Camp.blanc,
      );
      for (var i = 0; i < 2; i++) {
        book.recordWinningLine(
          initialBoard: Board.initial(),
          moves: a,
          winner: Camp.blanc,
        );
      }

      expect(book.lookup(Board.initial(), Camp.blanc), a[0]);
    });

    test('un coup illisible arrête l enregistrement', () {
      final book = OpeningBook();
      final line = legalLine(1);

      book.recordWinningLine(
        initialBoard: Board.initial(),
        moves: [...line, 'Si8-Si7', ...legalLine(1)],
        winner: Camp.blanc,
      );

      expect(book.positionCount, 1, reason: 'seul le premier coup a été lu');
    });

    test('une partie sans coup ne change rien', () {
      final book = OpeningBook();
      expect(
        book.recordWinningLine(
          initialBoard: Board.initial(),
          moves: const [],
          winner: Camp.blanc,
        ),
        isFalse,
      );
      expect(book.isEmpty, isTrue);
    });
  });

  group('Consultation', () {
    test('une position inconnue ne renvoie rien', () {
      expect(OpeningBook().lookup(Board.initial(), Camp.blanc), isNull);
    });

    test('on peut exiger plusieurs victoires avant de faire confiance', () {
      final book = OpeningBook();
      final line = legalLine(1);
      book.recordWinningLine(
        initialBoard: Board.initial(),
        moves: line,
        winner: Camp.blanc,
      );

      expect(book.lookup(Board.initial(), Camp.blanc, minCount: 1), line[0]);
      expect(book.lookup(Board.initial(), Camp.blanc, minCount: 2), isNull);
    });
  });

  group('Persistance', () {
    test('le livre se relit tel quel', () {
      final book = OpeningBook();
      final line = legalLine(3);
      book.recordWinningLine(
        initialBoard: Board.initial(),
        moves: line,
        winner: Camp.noir,
      );

      final reread = OpeningBook.fromJsonString(book.toJsonString());
      expect(reread.positionCount, book.positionCount);
      expect(reread.lookup(Board.initial(), Camp.blanc), isNull);
    });

    test('un fichier illisible repart de zéro', () {
      expect(OpeningBook.fromJsonString('{pas du json').isEmpty, isTrue);
      expect(OpeningBook.fromJsonString('[]').isEmpty, isTrue);
    });
  });
}
