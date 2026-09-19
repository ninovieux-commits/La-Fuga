/// Retrouver un coup à partir de sa notation.
///
/// C'est ce dont dépend le mode en ligne : un coup arrive en texte, et il faut
/// le rejouer exactement. Le test le plus parlant est l'aller-retour — toute
/// notation produite doit se relire en le même coup.
library;

import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/notation.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:test/test.dart';

void main() {
  group('Aller-retour notation → coup', () {
    test('depuis la position de départ, chaque coup se relit', () {
      final board = Board.initial();
      for (final camp in Camp.values) {
        final moves = generateMoves(board, camp);
        expect(moves, isNotEmpty);

        var checked = 0;
        for (final mv in moves) {
          final notation = notationOn(board, mv);
          final resolved = resolveNotation(board, camp, notation);
          expect(
            resolved,
            isNotNull,
            reason: '« $notation » (${camp.wire}) introuvable',
          );
          expect(
            resolved!.board.key,
            mv.board.key,
            reason: '« $notation » retrouve un AUTRE coup',
          );
          checked++;
        }
        expect(checked, moves.length);
      }
    });

    test('au fil d une partie jouée par l IA', () {
      var board = Board.initial();
      var camp = Camp.blanc;

      for (var ply = 0; ply < 10; ply++) {
        final moves = generateMoves(board, camp);
        if (moves.isEmpty) break;
        final mv = moves[ply % moves.length];
        final notation = notationOn(board, mv);

        final resolved = resolveNotation(board, camp, notation);
        expect(resolved, isNotNull, reason: 'demi-coup $ply : « $notation »');
        expect(resolved!.board.key, mv.board.key);

        if (mv.fugue || mv.matOn != null || mv.fugueBy != null) break;
        board = mv.board;
        camp = camp.opposite;
      }
    });
  });

  group('Robustesse', () {
    test('le suffixe de mat est ignoré', () {
      final board = Board.initial();
      final mv = generateMoves(board, Camp.blanc).first;
      final notation = notationOfMove(mv);
      expect(
        resolveNotation(board, Camp.blanc, '$notation#')?.board.key,
        mv.board.key,
      );
    });

    test('les espaces autour ne gênent pas', () {
      final board = Board.initial();
      final mv = generateMoves(board, Camp.blanc).first;
      final notation = notationOfMove(mv);
      expect(
        resolveNotation(board, Camp.blanc, '  $notation  ')?.board.key,
        mv.board.key,
      );
    });

    test('une notation qui ne correspond à rien est refusée', () {
      final board = Board.initial();
      // Un coup reçu du réseau peut être corrompu : mieux vaut le refuser
      // que jouer autre chose.
      expect(resolveNotation(board, Camp.blanc, 'Si8-Si7'), isNull);
      expect(resolveNotation(board, Camp.blanc, 'n importe quoi'), isNull);
      expect(resolveNotation(board, Camp.blanc, ''), isNull);
    });

    test('un coup du mauvais camp est refusé', () {
      final board = Board.initial();
      final noirMove = generateMoves(board, Camp.noir).first;
      final notation = notationOfMove(noirMove);
      expect(
        resolveNotation(board, Camp.blanc, notation),
        isNull,
        reason: 'ce coup appartient aux Noirs',
      );
    });
  });

  group('Cases poussées', () {
    test('sans poussée, aucune case', () {
      final board = Board.initial();
      final simple = generateMoves(
        board,
        Camp.blanc,
      ).firstWhere((m) => m.pushDirsUsed.isEmpty);
      expect(pushTargetsOf(board, simple), isEmpty);
    });

    test('une poussée désigne la première case occupée de sa direction', () {
      final b = Board.empty();
      b.set(3, 2, Piece.blancGarde);
      b.set(3, 1, Piece.blancSoldat);
      b.set(4, 4, Piece.noirNurse);
      b.set(0, 0, Piece.noirGarde);
      b.set(0, 1, Piece.noirSoldat);

      final push = generateMoves(
        b,
        Camp.blanc,
      ).firstWhere((m) => m.pushDirsUsed.isNotEmpty);
      final targets = pushTargetsOf(b, push);
      expect(targets, isNotEmpty);
      for (final t in targets) {
        expect(t.onBoard, isTrue);
      }
    });
  });
}
