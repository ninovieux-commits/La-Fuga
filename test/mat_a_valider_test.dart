/// Le mat attend la validation du coup ; la fugue, non.
///
/// Nino : « Quand on fait mat (sur soi-même comme sur l'adversaire), il
/// devrait falloir valider son coup. C'est bien qu'il se valide seul en cas
/// de fugue, car rien de meilleur n'est possible, mais pas quand on mate. »
///
/// Le mat se jouait tout seul dès que l'Héritier sortait du plateau : la
/// partie était finie avant qu'on ait retouché sa pièce, et la touche
/// d'annulation ne servait plus à rien.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/move_controller.dart';

/// Un Garde noir en Ré3 va en Fa2 — une diagonale, ce qui active sa
/// poussée — et pousse vers le bas l'Héritier blanc de Fa1 : celui-ci sort
/// par la rangée −1, qui n'est pas SON ralliement. C'est un mat.
Board _positionDeMat() {
  final b = Board.empty();
  b.set(3, 0, Piece.blancHeritier);
  b.set(2, 2, const Piece(PieceType.garde, Camp.noir));
  // Une carrée ne bouge pas sans voisine carrée : il lui faut une compagne.
  b.set(1, 2, const Piece(PieceType.garde, Camp.noir));
  b.set(0, 7, Piece.noirHeritier);
  return b;
}

/// Le même mat, mais sur SON PROPRE Héritier : le Garde blanc pousse
/// l'Héritier blanc dehors. Nino le veut aussi validable.
Board _positionDeMatSurSoi() {
  final b = Board.empty();
  b.set(3, 0, Piece.blancHeritier);
  b.set(2, 2, const Piece(PieceType.garde, Camp.blanc));
  b.set(1, 2, const Piece(PieceType.garde, Camp.blanc));
  b.set(0, 7, Piece.noirHeritier);
  return b;
}

const _garde = Cell(2, 2);
const _arrivee = Cell(3, 1);
const _heritier = Cell(3, 0);

void main() {
  /// Pousse l'Héritier dehors, sans valider.
  MoveController pousser(Board depart, Camp trait) {
    final c = MoveController(board: depart, turn: trait);
    c.tapCell(_garde);
    c.tapCell(_arrivee);
    c.tapCell(_heritier);
    return c;
  }

  test('l Héritier sort, mais la partie n est pas finie', () {
    final c = pousser(_positionDeMat(), Camp.noir);

    expect(c.board.atCell(_heritier), isNull, reason: 'il est bien sorti');
    expect(c.captured[Camp.blanc], hasLength(1));
    expect(c.gameOver, isFalse, reason: 'le coup n est pas encore validé');
    expect(c.history, isEmpty, reason: 'rien ne s écrit avant la validation');
    expect(c.turn, Camp.noir, reason: 'la main n a pas changé');
  });

  test('retoucher la pièce valide le mat', () {
    final c = pousser(_positionDeMat(), Camp.noir);
    final r = c.tapCell(_arrivee);

    expect(r.effect, ControllerEffect.gameOver);
    expect(r.endReason, 'mat');
    expect(r.loser, Camp.blanc);
    expect(c.history, hasLength(1), reason: 'le coup de mat est enregistré');
  });

  test('on peut encore annuler : l Héritier revient', () {
    final c = pousser(_positionDeMat(), Camp.noir);

    expect(c.cancelCurrentMove(), isTrue);
    expect(c.board.atCell(_heritier), Piece.blancHeritier);
    expect(c.captured[Camp.blanc], isEmpty, reason: 'il quitte les prises');
    expect(c.gameOver, isFalse);
    expect(c.turn, Camp.noir, reason: 'c est toujours à nous de jouer');
  });

  test('mater son PROPRE Héritier se valide aussi', () {
    final c = pousser(_positionDeMatSurSoi(), Camp.blanc);
    expect(c.gameOver, isFalse);

    final r = c.tapCell(_arrivee);
    expect(r.endReason, 'mat');
    expect(r.loser, Camp.blanc, reason: 'on s est maté soi-même');
  });

  test('une fois l Héritier dehors, pousser encore ne fait plus rien', () {
    final c = pousser(_positionDeMat(), Camp.noir);
    final avant = c.board.toString();

    // Les trois autres directions orthogonales du Garde.
    for (final d in const [Cell(2, 1), Cell(4, 1), Cell(3, 2)]) {
      expect(c.tapCell(d).effect, ControllerEffect.none);
    }
    expect(c.board.toString(), avant, reason: 'le plateau n a pas bougé');
    expect(c.gameOver, isFalse, reason: 'seule la validation termine');
  });
}
