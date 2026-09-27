/// Ce qui glisse d'une position à l'autre.
///
/// Rejouer un coup — le sien, celui de l'adversaire, celui qu'on revoit avec
/// les flèches — c'est toujours la même question : quelles pièces ont bougé,
/// et d'où vers où ? Le contrôleur de coups le savait pour ses propres coups ;
/// les écrans qui affichent une position VENUE D'AILLEURS (une partie de
/// correspondance rechargée, un `.nmc` qu'on parcourt) n'avaient rien, et
/// sautaient donc d'une position à l'autre sans rien animer.
library;

import '../engine/board.dart';
import '../engine/piece.dart';

/// Les pièces qui ont bougé entre deux positions, appariées au plus court.
///
/// Une pièce qui QUITTE le plateau n'a pas d'arrivée : elle ne glisse pas
/// d'elle-même. C'est à l'appelant d'ajouter sa sortie s'il en connaît la
/// destination — un Héritier qui fugue rejoint le milieu de son ralliement.
List<(Piece, Cell, Cell)> slidesBetween(Board before, Board after) {
  final departs = <(Piece, Cell)>[];
  final arrivees = <(Piece, Cell)>[];
  for (var c = 0; c < kCols; c++) {
    for (var r = 0; r < kRows; r++) {
      final b = before.at(c, r);
      final a = after.at(c, r);
      if (b == a) continue;
      if (b != null) departs.add((b, Cell(c, r)));
      if (a != null) arrivees.add((a, Cell(c, r)));
    }
  }

  final glissees = <(Piece, Cell, Cell)>[];
  final prises = <int>{};
  for (final (piece, depuis) in departs) {
    var meilleur = -1;
    var distance = 1 << 30;
    for (var i = 0; i < arrivees.length; i++) {
      if (prises.contains(i)) continue;
      final (autre, vers) = arrivees[i];
      if (autre.type != piece.type || autre.camp != piece.camp) continue;
      final d = (vers.col - depuis.col).abs() + (vers.row - depuis.row).abs();
      if (d < distance) {
        distance = d;
        meilleur = i;
      }
    }
    if (meilleur >= 0) {
      prises.add(meilleur);
      glissees.add((piece, depuis, arrivees[meilleur].$2));
    }
  }
  return glissees;
}

/// La glissée de sortie d'un Héritier qui a rejoint son ralliement entre les
/// deux positions, ou rien.
///
/// Sa case de départ est le seul endroit où il était avant et où il n'est plus
/// après. On la cherche plutôt que de la déduire du coup, parce qu'il peut
/// aussi bien avoir marché que s'être fait pousser.
List<(Piece, Cell, Cell)> fugueSlide(Board before, Board after, Camp camp) {
  for (var c = 0; c < kCols; c++) {
    for (var r = 0; r < kRows; r++) {
      final p = before.at(c, r);
      if (p == null || !p.isHeir || p.camp != camp) continue;
      if (after.at(c, r) == p) continue;
      return [(p, Cell(c, r), rallyDisplayCell(camp))];
    }
  }
  return const [];
}
