/// Le plateau se redessine quand il change — même quand c'est le MÊME objet.
///
/// Un plateau est muté en place. Le peintre précédent et le nouveau pointent
/// donc souvent sur le même objet, et toute comparaison faite après coup dit
/// « rien n'a changé ». C'est ce qui empêchait une poussée de s'afficher tant
/// que le coup n'était pas validé — visible surtout dans le tutoriel.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/widgets/board_geometry.dart';
import 'package:lafuga/ui/widgets/board_painter.dart';

void main() {
  final geometry = BoardGeometry(size: const Size(360, 480), flipped: true);

  BoardPiecesPainter painterFor(Board board) => BoardPiecesPainter(
    geometry: geometry,
    palette: paletteOf(kDefaultTheme),
    board: board,
  );

  test('un plateau muté en place redemande un dessin', () {
    final board = Board.initial();
    final before = painterFor(board);

    // Ce que fait une poussée : les pièces bougent sur le MÊME plateau.
    board.set(0, 0, null);
    board.set(0, 2, Piece.blancSoldat);
    final after = painterFor(board);

    expect(identical(before.board, after.board), isTrue, reason: 'même objet');
    expect(after.shouldRepaint(before), isTrue);
  });

  test('un plateau inchangé ne redemande rien', () {
    final board = Board.initial();
    final before = painterFor(board);
    final after = painterFor(board);
    expect(after.shouldRepaint(before), isFalse);
  });

  test('deux plateaux distincts de même contenu ne redemandent rien', () {
    final a = Board.initial();
    final b = Board.initial();
    expect(painterFor(b).shouldRepaint(painterFor(a)), isFalse);
  });
}
