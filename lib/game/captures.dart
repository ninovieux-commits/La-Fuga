/// Ce qu'un coup a fait sortir du plateau.
///
/// Les panneaux de chaque joueur montrent les pièces que l'autre a perdues.
/// Elles se comptaient au moment de la poussée, dans le contrôleur — donc
/// seulement pour les coups joués au doigt. Un coup venu d'ailleurs — Deep
/// Grey, le réseau, un `.nmc` relu — n'arrive qu'avec son plateau résultant :
/// pour lui, la seule mesure possible est la différence entre les deux
/// positions. C'est celle-ci, et les deux chemins l'utilisent désormais.
library;

import '../engine/board.dart';
import '../engine/piece.dart';

/// Pièces qui quittent le plateau d'une position à l'autre — sans compter
/// l'Héritier qui fugue, qui n'est pas une prise mais une victoire.
///
/// Sert à la relecture, et à l'analyse quand elle repart d'une position
/// passée : les prises se recomptent alors depuis les positions traversées.
List<Piece> ejectedBetween(Board before, Board after, String notation) {
  final counts = <Piece, int>{};
  for (var c = 0; c < kCols; c++) {
    for (var r = 0; r < kRows; r++) {
      final p = after.at(c, r);
      if (p != null) counts[p] = (counts[p] ?? 0) + 1;
    }
  }
  final out = <Piece>[];
  for (var c = 0; c < kCols; c++) {
    for (var r = 0; r < kRows; r++) {
      final p = before.at(c, r);
      if (p == null) continue;
      final left = counts[p] ?? 0;
      if (left > 0) {
        counts[p] = left - 1;
      } else {
        out.add(p);
      }
    }
  }
  // Une fugue se note par un `*` : l'Héritier sort, mais ce n'est pas une
  // prise.
  if (notation.contains('*')) out.removeWhere((p) => p.isHeir);
  return out;
}
