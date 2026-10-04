/// La dernière chance n'appartient qu'aux Noirs.
///
/// Nino : « Quand je fugue avec les noirs et que les blancs peuvent fuguer
/// aussi, mon adversaire reçoit match nul. Ça ne devrait marcher que pour les
/// noirs. »
///
/// Les Blancs jouent les premiers. Quand ils fuguent, les Noirs ont joué un
/// coup de moins : on leur accorde une dernière chance, et s'ils peuvent
/// fuguer à leur tour, la partie est nulle. C'est la seule compensation du
/// trait. Quand ce sont les Noirs qui fuguent, les deux camps ont joué autant
/// de coups — les Blancs n'ont aucune réplique à réclamer.
///
/// La règle était appliquée dans les deux sens, donc une fugue des Noirs
/// devenait nulle dès que les Blancs pouvaient fuguer. Elle leur volait leur
/// victoire.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/move_controller.dart';

/// Les deux Héritiers à une case de leur ralliement : qui fugue gagne, ou
/// fait nulle, selon la couleur.
Board _lesDeuxAuBord() {
  final b = Board.empty();
  b.set(3, 7, const Piece(PieceType.heritier, Camp.blanc));
  b.set(3, 0, const Piece(PieceType.heritier, Camp.noir));
  // Une ronde isolée est immobile : sans voisine, l'Héritier ne fugue pas.
  b.set(2, 7, const Piece(PieceType.nurse, Camp.blanc));
  b.set(2, 0, const Piece(PieceType.nurse, Camp.noir));
  return b;
}

/// Joue la fugue du camp au trait, par le coup généré.
ControllerResult _fugue(MoveController jeu) {
  final coup = generateMoves(jeu.board, jeu.turn).firstWhere((m) => m.fugue);
  return jeu.applyGeneratedMove(coup);
}

void main() {
  group('Les deux camps peuvent fuguer', () {
    test('la position est bien celle-là', () {
      final b = _lesDeuxAuBord();
      expect(campCanFugue(b, Camp.blanc), isTrue);
      expect(campCanFugue(b, Camp.noir), isTrue);
    });

    test('Blanc fugue : NULLE, les Noirs ont droit à leur réplique', () {
      final jeu = MoveController(board: _lesDeuxAuBord());
      final r = _fugue(jeu);
      expect(r.effect, ControllerEffect.gameOver);
      expect(r.endReason, 'nulle');
      expect(r.loser, isNull);
    });

    test('Noir fugue : les NOIRS GAGNENT, pas de réplique à donner', () {
      final jeu = MoveController(board: _lesDeuxAuBord(), turn: Camp.noir);
      final r = _fugue(jeu);
      expect(r.effect, ControllerEffect.gameOver);
      expect(
        r.endReason,
        'fugue',
        reason: 'c était annoncé nulle : la victoire des Noirs leur échappait',
      );
      expect(r.loser, Camp.blanc);
    });
  });

  group('Et quand un seul peut fuguer, rien ne change', () {
    test('Blanc fugue, les Noirs ne peuvent pas suivre : Blanc gagne', () {
      final b = Board.empty()
        ..set(3, 7, const Piece(PieceType.heritier, Camp.blanc))
        ..set(2, 7, const Piece(PieceType.nurse, Camp.blanc))
        ..set(3, 4, const Piece(PieceType.heritier, Camp.noir))
        ..set(2, 4, const Piece(PieceType.nurse, Camp.noir));
      final jeu = MoveController(board: b);
      final r = _fugue(jeu);
      expect(r.endReason, 'fugue');
      expect(r.loser, Camp.noir);
    });

    test('Noir fugue, les Blancs sont loin : Noir gagne', () {
      final b = Board.empty()
        ..set(3, 3, const Piece(PieceType.heritier, Camp.blanc))
        ..set(2, 3, const Piece(PieceType.nurse, Camp.blanc))
        ..set(3, 0, const Piece(PieceType.heritier, Camp.noir))
        ..set(2, 0, const Piece(PieceType.nurse, Camp.noir));
      final jeu = MoveController(board: b, turn: Camp.noir);
      final r = _fugue(jeu);
      expect(r.endReason, 'fugue');
      expect(r.loser, Camp.blanc);
    });
  });

  group('Au doigt comme par le réseau, le verdict est le même', () {
    // Les deux chemins portaient chacun leur copie de la règle. Ils
    // pouvaient diverger sans que rien ne le dise — et les deux téléphones
    // d'une partie n'empruntent justement pas le même.
    test('Noir fugue en tapant : les Noirs gagnent aussi', () {
      final jeu = MoveController(board: _lesDeuxAuBord(), turn: Camp.noir)
        ..tapCell(const Cell(3, 0));
      final r = jeu.tapCell(Cell(3, Camp.noir.rallyRow));
      expect(r.effect, ControllerEffect.gameOver);
      expect(r.endReason, 'fugue');
      expect(r.loser, Camp.blanc);
    });

    test('Blanc fugue en tapant : nulle, comme par le réseau', () {
      final jeu = MoveController(board: _lesDeuxAuBord())
        ..tapCell(const Cell(3, 7));
      final r = jeu.tapCell(Cell(3, Camp.blanc.rallyRow));
      expect(r.effect, ControllerEffect.gameOver);
      expect(r.endReason, 'nulle');
      expect(r.loser, isNull);
    });
  });
}
