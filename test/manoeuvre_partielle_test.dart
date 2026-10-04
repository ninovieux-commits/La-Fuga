/// Bouger DEUX carrés sur trois, et que l'adversaire le voie.
///
/// Nino : « les déplacements de groupe (plusieurs carrés bougent en même
/// temps) ne sont pas transmis à l'adversaire, chacun voit que c'est à
/// l'autre de jouer. »
///
/// Le générateur ne déplace que des groupes CONNEXES ENTIERS
/// (`board.groupOf`). Le joueur, lui, compose sa sélection carré par carré et
/// peut n'en bouger qu'une partie. Ce coup-là n'était produit par personne :
/// arrivé chez l'adversaire, `resolveNotation` ne trouvait rien et
/// `_onOpponentMove` l'ignorait en silence. Le plateau adverse ne bougeait
/// pas, son tour ne basculait pas, et les deux joueurs attendaient l'autre.
///
/// Kivy applique la notation telle quelle (`_apply_maneuver`, main.py) : il
/// lit les cases, calcule l'écart depuis la maîtresse, déplace, et c'est
/// tout. On fait pareil — en vérifiant la géométrie, pour que ce soit le coup
/// exact et pas une relecture approximative.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/move_controller.dart';

const _sol = Piece(PieceType.soldat, Camp.blanc);

/// Trois carrés blancs alignés, de la place devant, et les deux Héritiers.
Board _troisCarres() {
  final b = Board.empty();
  b.set(2, 2, _sol);
  b.set(3, 2, _sol);
  b.set(4, 2, _sol);
  b.set(2, 7, const Piece(PieceType.heritier, Camp.blanc));
  b.set(5, 7, const Piece(PieceType.heritier, Camp.noir));
  return b;
}

void main() {
  group('Une manœuvre partielle traverse le réseau', () {
    test('le joueur bouge deux carrés sur trois, et ça s écrit', () {
      final depart = _troisCarres();
      expect(
        depart.groupOf(2, 2).length,
        3,
        reason: 'le moteur voit bien un groupe de trois',
      );

      final jeu = MoveController(board: depart.clone())
        ..tapCell(const Cell(3, 2))
        ..tapCell(const Cell(2, 2));
      expect(jeu.groupSelection, {const Cell(2, 2)});

      jeu.tapCell(const Cell(3, 3));
      final valide = jeu.tapCell(const Cell(3, 3));
      expect(valide.notation, '(Fa3Mi3)-Fa4');
    });

    test('et l adversaire retrouve EXACTEMENT le même plateau', () {
      final depart = _troisCarres();
      final jeu = MoveController(board: depart.clone())
        ..tapCell(const Cell(3, 2))
        ..tapCell(const Cell(2, 2))
        ..tapCell(const Cell(3, 3));
      final notation = jeu.tapCell(const Cell(3, 3)).notation!;

      final relu = resolveNotation(depart, Camp.blanc, notation);
      expect(
        relu,
        isNotNull,
        reason: 'sans cela l adversaire ignore le coup et la partie se fige',
      );
      expect(relu!.board.key, jeu.board.key);
      expect(relu.kind, MoveKind.maneuver);
      // Le troisième carré n'a pas bougé.
      expect(depart.at(4, 2), isNotNull);
      expect(relu.board.at(4, 2), isNotNull);
    });

    test('le groupe entier passait déjà, et passe toujours', () {
      final depart = _troisCarres();
      final jeu = MoveController(board: depart.clone())
        ..tapCell(const Cell(3, 2))
        ..tapCell(const Cell(2, 2))
        ..tapCell(const Cell(4, 2))
        ..tapCell(const Cell(3, 3));
      final notation = jeu.tapCell(const Cell(3, 3)).notation!;
      final relu = resolveNotation(depart, Camp.blanc, notation);
      expect(relu?.board.key, jeu.board.key);
    });
  });

  group('Mais on n accepte pas n importe quoi', () {
    final depart = _troisCarres();

    test('une case vide ne se déplace pas', () {
      expect(resolveNotation(depart, Camp.blanc, '(La3Si3)-La4'), isNull);
    });

    test('ni une pièce du camp d en face', () {
      // La3 est un carré NOIR : les Blancs ne l'emmènent pas avec eux.
      final b = _troisCarres()
        ..set(5, 2, const Piece(PieceType.soldat, Camp.noir));
      expect(resolveNotation(b, Camp.blanc, '(Mi3La3)-Mi4'), isNull);
    });

    test('deux carrés NON adjacents du même groupe, eux, passent', () {
      // Mi3 et Sol3 encadrent Fa3 sans se toucher. Le joueur peut les
      // sélectionner tous les deux : c'est un coup, pas une erreur.
      final b = _troisCarres();
      final relu = resolveNotation(b, Camp.blanc, '(Mi3Sol3)-Mi4');
      expect(relu, isNotNull);
      expect(relu!.board.at(3, 2), isNotNull, reason: 'Fa3 reste en place');
    });

    test('ni une ronde, qui n est pas une carrée', () {
      expect(resolveNotation(depart, Camp.blanc, '(Mi8Fa3)-Mi7'), isNull);
    });

    test('ni un saut de plusieurs cases', () {
      // « Quand plusieurs pièces se déplacent, c'est forcément d'une seule
      // case. Si une pièce se déplace de plusieurs cases, c'est toujours un
      // multisaut et ça ne concerne qu'une seule pièce. »
      expect(resolveNotation(depart, Camp.blanc, '(Fa3Mi3)-Fa6'), isNull);
    });

    test('ni un déplacement vers une case occupée par un tiers', () {
      final b = _troisCarres()
        ..set(3, 3, const Piece(PieceType.soldat, Camp.noir));
      expect(resolveNotation(b, Camp.blanc, '(Fa3Mi3)-Fa4'), isNull);
    });

    test('ni une sortie de plateau', () {
      final b = Board.empty()
        ..set(0, 0, _sol)
        ..set(1, 0, _sol)
        ..set(2, 7, const Piece(PieceType.heritier, Camp.blanc))
        ..set(5, 7, const Piece(PieceType.heritier, Camp.noir));
      expect(resolveNotation(b, Camp.blanc, '(Do1Ré1)-Si1'), isNull);
    });

    test('ni deux fois la même case', () {
      expect(resolveNotation(depart, Camp.blanc, '(Fa3Fa3)-Fa4'), isNull);
    });
  });
}
