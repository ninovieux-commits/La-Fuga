/// Mise en évidence du dernier coup : cadres, multisaut, poussées.
library;

import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/last_move.dart';
import 'package:test/test.dart';

void main() {
  group('Coup simple', () {
    test('le départ et l arrivée sont encadrés, au camp du joueur', () {
      final board = Board.initial();
      final move = generateMoves(
        board,
        Camp.blanc,
      ).firstWhere((m) => m.kind == MoveKind.move);

      final hl = LastMove.of(board, move);

      expect(hl.camp, Camp.blanc, reason: 'le cadre suit le camp qui a joué');
      expect(hl.from, {move.from});
      expect(hl.to, {move.movedCells.first});
      expect(hl.framedCells, hasLength(2));
      expect(hl.jumpPath, isEmpty);
      expect(hl.pushDirs, isEmpty);
    });
  });

  group('Multisaut', () {
    test('les atterrissages intermédiaires sont retrouvés', () {
      // Trois rondes alignées : la sauteuse franchit les deux autres.
      final board = Board.empty()
        ..set(0, 0, const Piece(PieceType.nurse, Camp.blanc))
        ..set(1, 0, const Piece(PieceType.nurse, Camp.blanc))
        ..set(3, 0, const Piece(PieceType.nurse, Camp.blanc));

      final path = jumpPathOf(board, const Cell(0, 0), const Cell(4, 0));

      expect(path, [const Cell(2, 0)], reason: 'un seul rebond au milieu');
    });

    test('un saut unique ne montre rien entre les deux cases', () {
      final board = Board.empty()
        ..set(0, 0, const Piece(PieceType.nurse, Camp.blanc))
        ..set(1, 0, const Piece(PieceType.nurse, Camp.blanc));

      expect(jumpPathOf(board, const Cell(0, 0), const Cell(2, 0)), isEmpty);
    });

    test('une carrée ne saute pas : pas de chemin', () {
      final board = Board.empty()
        ..set(0, 0, const Piece(PieceType.soldat, Camp.blanc))
        ..set(1, 0, const Piece(PieceType.nurse, Camp.blanc));

      expect(jumpPathOf(board, const Cell(0, 0), const Cell(2, 0)), isEmpty);
    });
  });

  group('Poussée', () {
    test('les directions poussées sont retenues, filtrées par le type', () {
      final board = Board.initial();
      final pushes = generateMoves(
        board,
        Camp.blanc,
      ).where((m) => pushTargetsOf(board, m).isNotEmpty);
      final move = pushes.first;
      final targets = pushTargetsOf(board, move);

      final hl = LastMove.of(board, move, pushTargets: targets);

      expect(hl.pushDirs, isNotEmpty);
      final arrival = move.movedCells.first;
      expect(hl.pushDirs.keys.single, arrival);

      // Un Soldat pousse en diagonale, un Garde en orthogonal.
      final piece = board.atCell(move.from)!;
      for (final (dc, dr) in hl.pushDirs[arrival]!) {
        final diagonal = dc != 0 && dr != 0;
        expect(
          diagonal,
          piece.type == PieceType.soldat,
          reason: '${piece.type.wire} pousse dans le mauvais sens',
        );
      }
    });

    test('sans poussée, rien n est marqué', () {
      final board = Board.initial();
      final move = generateMoves(
        board,
        Camp.blanc,
      ).firstWhere((m) => m.kind == MoveKind.move);

      expect(LastMove.of(board, move).pushDirs, isEmpty);
    });
  });

  group('Manœuvre', () {
    test('toutes les pièces du groupe sont encadrées', () {
      // Deux carrées côte à côte, au large : de quoi manœuvrer.
      final board = Board.empty()
        ..set(2, 3, const Piece(PieceType.soldat, Camp.blanc))
        ..set(3, 3, const Piece(PieceType.garde, Camp.blanc));
      final move = generateMoves(
        board,
        Camp.blanc,
      ).firstWhere((m) => m.kind == MoveKind.maneuver);

      final hl = LastMove.of(board, move);

      expect(hl.from.length, greaterThan(1), reason: 'le groupe entier');
      expect(hl.to.length, hl.from.length);
    });
  });
}
