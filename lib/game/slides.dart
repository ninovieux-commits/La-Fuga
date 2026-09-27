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
import '../engine/literal_replay.dart';
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

/// Ce qui glisse pour le coup [notation], joué depuis [avant].
///
/// C'est LA fonction que les écrans appellent : elle prend les glissées
/// exactes de la relecture quand la notation est connue, et ne retombe sur
/// la comparaison de plateaux que faute de mieux — un saut de plusieurs
/// coups, ou une notation absente.
///
/// La comparaison ne peut pas tout voir : une poussée de pièces IDENTIQUES
/// ne laisse de trace qu'aux deux bouts de la chaîne, et l'appariement au
/// plus court fait alors glisser une seule pièce sur toute la longueur, ou
/// en croise deux. La relecture, elle, sait exactement qui est allé où.
///
/// [recule] défait le coup : chaque pièce repart d'où elle est arrivée.
List<(Piece, Cell, Cell)> glisseesDuCoup({
  required Board avant,
  required Board apres,
  required String notation,
  bool recule = false,
}) {
  final relu = notation.trim().isEmpty
      ? null
      : applyNotationLiterally(avant, notation);
  final droites = (relu != null && relu.slides.isNotEmpty)
      ? [
          for (final g in relu.slides)
            if (g.$2 != g.$3) g,
        ]
      : [
          ...slidesBetween(avant, apres),
          // L'Héritier qui fugue quitte le plateau : il n'a pas d'arrivée à
          // apparier, et sans cela le coup final ne montrait rien glisser.
          for (final camp in relu?.fugued ?? const <Camp>{})
            ...fugueSlide(avant, apres, camp),
        ];
  return recule ? reversedSlides(droites) : droites;
}

/// Le même lot de glissées, à l'envers : chaque pièce repart d'où elle est
/// arrivée.
///
/// Reculer d'un coup, c'est le DÉFAIRE. Sans cette inversion, la flèche
/// arrière rejouait le coup à l'endroit puis posait les pièces à leur place
/// d'avant, d'un coup sec.
List<(Piece, Cell, Cell)> reversedSlides(List<(Piece, Cell, Cell)> slides) => [
  for (final (piece, from, to) in slides.reversed) (piece, to, from),
];

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
