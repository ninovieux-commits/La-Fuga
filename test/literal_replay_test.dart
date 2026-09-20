/// La relecture littérale — `_apply_notation` (main.py).
///
/// Kivy ne relit JAMAIS une partie enregistrée en cherchant le coup légal qui
/// correspondrait à la notation : il déplace les pièces comme le texte le dit.
/// Ces tests fixent ce contrat, parce que c'est lui qui garantit que deux
/// appareils reconstruisent la même position à partir du même `.nmc`.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/literal_replay.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';

void main() {
  group('Application littérale', () {
    test('un déplacement simple déplace la pièce nommée', () {
      final r = applyNotationLiterally(Board.initial(), 'Do2-Do3');
      expect(r.ok, isTrue);
      expect(r.board.at(0, 1), isNull);
      expect(r.board.at(0, 2)?.type, PieceType.garde);
    });

    test('une case de départ vide ne s applique pas', () {
      final r = applyNotationLiterally(Board.initial(), 'Do4-Do5');
      expect(r.ok, isFalse);
      expect(r.board.key, Board.initial().key, reason: 'plateau intact');
    });

    test('la légalité n entre pas en ligne de compte', () {
      // Coup noir au tour des Blancs, et saut impossible : Kivy l applique
      // quand même. C est ce qui lui permet d afficher une partie que le
      // générateur ne saurait pas retrouver.
      final r = applyNotationLiterally(Board.initial(), 'Si8-Si7');
      expect(r.ok, isTrue);
      expect(r.board.at(6, 7), isNull);
      expect(r.board.at(6, 6)?.type, PieceType.garde);
    });

    test('un chevron nu pousse TOUT ce qui touche la case d arrivée', () {
      // Position fabriquée : un Garde blanc en do4, entouré de deux pièces
      // sur ses directions orthogonales.
      final b = Board.empty();
      b.set(0, 2, Piece.blancGarde); // do3, la pièce qui va pousser
      b.set(0, 4, Piece.noirSoldat); // do5, au-dessus de l arrivée
      b.set(1, 3, Piece.noirSoldat); // ré4, à droite de l arrivée

      final r = applyNotationLiterally(b, 'Do3-Do4>');
      expect(r.ok, isTrue);
      expect(
        r.board.at(0, 3)?.type,
        PieceType.garde,
        reason: 'le Garde arrive',
      );
      expect(r.board.at(0, 5)?.camp, Camp.noir, reason: 'do5 poussé en do6');
      expect(r.board.at(2, 3)?.camp, Camp.noir, reason: 'ré4 poussé en mi4');
    });

    test('les cases nommées après le chevron sont les seules poussées', () {
      final b = Board.empty();
      b.set(0, 2, Piece.blancGarde);
      b.set(0, 4, Piece.noirSoldat);
      b.set(1, 3, Piece.noirSoldat);

      final r = applyNotationLiterally(b, 'Do3-Do4>Do5');
      expect(r.ok, isTrue);
      expect(r.board.at(0, 5)?.camp, Camp.noir, reason: 'do5 poussé');
      expect(r.board.at(1, 3)?.camp, Camp.noir, reason: 'ré4 n a pas bougé');
    });

    test('une pièce poussée hors du plateau disparaît', () {
      final b = Board.empty();
      b.set(0, 5, Piece.blancGarde);
      b.set(0, 7, Piece.noirSoldat); // do8, sur le bord

      final r = applyNotationLiterally(b, 'Do6-Do7>');
      expect(r.ok, isTrue);
      expect(r.board.at(0, 7), isNull, reason: 'éjecté');
    });

    test('le Chevalier bloque toute la ligne de poussée', () {
      final b = Board.empty();
      b.set(0, 2, Piece.blancGarde);
      b.set(0, 4, Piece.noirChevalier);

      final r = applyNotationLiterally(b, 'Do3-Do4>Do5');
      expect(r.ok, isTrue);
      expect(
        r.board.at(0, 4)?.type,
        PieceType.chevalier,
        reason: 'le Chevalier est inamovible',
      );
    });

    test('une manœuvre à une seule case nommée emmène tout le groupe', () {
      final b = Board.empty();
      b.set(0, 0, Piece.blancSoldat);
      b.set(1, 0, Piece.blancGarde); // voisin : même groupe de carrées

      final r = applyNotationLiterally(b, '(Do1)-Do2');
      expect(r.ok, isTrue);
      expect(r.board.at(0, 1)?.type, PieceType.soldat);
      expect(r.board.at(1, 1)?.type, PieceType.garde, reason: 'suit le groupe');
      expect(r.board.at(0, 0), isNull);
      expect(r.board.at(1, 0), isNull);
    });

    test('la marque de mat ne fait pas partie du coup', () {
      final r = applyNotationLiterally(Board.initial(), 'Do2-Do3#');
      expect(r.ok, isTrue);
      expect(r.board.at(0, 2)?.type, PieceType.garde);
    });

    test('une fugue vide la case de départ', () {
      final b = Board.empty();
      b.set(3, 7, Piece.blancHeritier);
      final r = applyNotationLiterally(b, 'Fa8*');
      expect(r.ok, isTrue);
      expect(r.board.at(3, 7), isNull);
    });
  });

  group('Ce qui est joué ici se relit ici', () {
    test('tout coup légal se relit à la lettre sur le même plateau', () {
      // Le contrat le plus fort de tout le portage : pour un coup que le
      // moteur a produit, la relecture littérale de sa notation doit rendre
      // EXACTEMENT le même plateau. Sinon une partie jouée dans l appli
      // deviendrait fausse en la rouvrant.
      //
      // On ne se contente pas de la position de départ : on descend au hasard
      // dans l arbre, pour croiser poussées, sauts, manœuvres et fugues.
      final random = Random(20260920);
      var positions = 0;
      var checked = 0;

      for (var game = 0; game < 40; game++) {
        var board = Board.initial();
        var camp = Camp.blanc;

        for (var ply = 0; ply < 24; ply++) {
          final moves = generateMoves(board, camp);
          if (moves.isEmpty) break;
          positions++;

          for (final move in moves) {
            final notation = notationOn(board, move);
            final literal = applyNotationLiterally(board, notation);
            expect(literal.ok, isTrue, reason: '$notation sur ${board.key}');
            expect(
              literal.board.key,
              move.board.key,
              reason: '$notation sur ${board.key}',
            );
            checked++;
          }

          final played = moves[random.nextInt(moves.length)];
          if (played.fugue || played.fugueBy != null || played.matOn != null) {
            break;
          }
          board = played.board;
          camp = camp.opposite;
        }
      }

      expect(positions, greaterThan(300));
      expect(checked, greaterThan(10000));
      // ignore: avoid_print
      print('$checked notations relues à la lettre sur $positions positions');
    });
  });
}
