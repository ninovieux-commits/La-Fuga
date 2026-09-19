/// Test de fidélité : le générateur de coups Dart doit produire EXACTEMENT
/// les mêmes coups que le moteur Python de l'application Kivy.
///
/// Les vecteurs de `test/fixtures/move_vectors.json` sont produits par
/// `tool/gen_vectors.py`, qui exécute le moteur Python extrait de `main.py`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:test/test.dart';

/// Reproduit `str(tuple)` de Python : `(3, 0)`.
String pyCell(Cell c) => '(${c.col}, ${c.row})';

/// Même signature que `signature()` dans `tool/gen_vectors.py`.
String signatureOf(Move m) => [
      m.board.key,
      switch (m.kind) {
        MoveKind.move => 'move',
        MoveKind.jump => 'jump',
        MoveKind.fugue => 'fugue',
        MoveKind.square => 'square',
        MoveKind.maneuver => 'maneuver',
        MoveKind.knight => 'knight',
      },
      m.fugue ? 'F' : '-',
      m.fugueBy?.wire ?? '-',
      m.matOn?.wire ?? '-',
      '${m.ejAlly}',
      '${m.ejOpp}',
      '${m.totalPushed}',
      pyCell(m.from),
      m.movedCells.map(pyCell).join(','),
    ].join('|');

void main() {
  group('Générateur de coups — fidélité au moteur Python', () {
    late List<dynamic> vectors;

    setUpAll(() {
      final f = File('test/fixtures/move_vectors.json');
      vectors = jsonDecode(f.readAsStringSync()) as List<dynamic>;
    });

    test('les vecteurs sont chargés', () {
      expect(vectors, isNotEmpty);
      expect(vectors.length, greaterThan(100));
    });

    test('chaque position produit exactement les mêmes coups', () {
      var checkedPositions = 0;
      var checkedMoves = 0;

      for (var i = 0; i < vectors.length; i++) {
        final v = vectors[i] as Map<String, dynamic>;
        final board = Board.fromJson(v['board'] as List<dynamic>);
        final camp = Camp.fromWire(v['camp'] as String);
        final expectedCount = v['count'] as int;
        final expectedSigs = (v['sigs'] as List<dynamic>).cast<String>();

        final moves = generateMoves(board, camp);
        final actualSigs = moves.map(signatureOf).toList()..sort();

        expect(moves.length, expectedCount,
            reason: 'position #$i (${camp.wire}) : nombre de coups différent\n'
                '${board.render()}');
        expect(actualSigs, expectedSigs,
            reason: 'position #$i (${camp.wire}) : coups différents\n'
                '${board.render()}');

        checkedPositions++;
        checkedMoves += moves.length;
      }

      // ignore: avoid_print
      print('$checkedPositions positions, $checkedMoves coups vérifiés '
          'contre le moteur Python');
    });
  });

  group('Position de départ', () {
    test('correspond à _setup_pieces', () {
      final b = Board.initial();
      expect(b.at(3, 0), Piece.blancHeritier, reason: 'Héritier blanc en fa1');
      expect(b.at(3, 1), Piece.blancNurse, reason: 'Nurse blanche en fa2');
      expect(b.at(3, 2), Piece.blancChevalier,
          reason: 'Chevalier blanc en fa3');
      expect(b.at(3, 7), Piece.noirHeritier, reason: 'Héritier noir en fa8');
      expect(b.at(3, 6), Piece.noirNurse, reason: 'Nurse noire en fa7');
      expect(b.at(3, 5), Piece.noirChevalier, reason: 'Chevalier noir en fa6');
      expect(b.at(0, 1), Piece.blancGarde, reason: 'Garde blanc en do2');
      expect(b.at(6, 1), Piece.blancSoldat, reason: 'Soldat blanc en si2');
      expect(b.at(0, 6), Piece.noirGarde, reason: 'Garde noir en do7');
      expect(b.at(6, 6), Piece.noirSoldat, reason: 'Soldat noir en si7');
    });

    test('compte 30 pièces, 15 par camp', () {
      final b = Board.initial();
      var blanc = 0, noir = 0;
      for (var c = 0; c < kCols; c++) {
        for (var r = 0; r < kRows; r++) {
          final p = b.at(c, r);
          if (p == null) continue;
          p.camp == Camp.blanc ? blanc++ : noir++;
        }
      }
      expect(blanc, 15);
      expect(noir, 15);
    });
  });

  group('Règles de poussée', () {
    test('Soldat : activée en orthogonal, pousse en diagonale', () {
      expect(pushActivated(PieceType.soldat, 1, 0), isTrue);
      expect(pushActivated(PieceType.soldat, 0, 1), isTrue);
      expect(pushActivated(PieceType.soldat, 1, 1), isFalse);
      expect(pushValid(PieceType.soldat, 1, 1), isTrue);
      expect(pushValid(PieceType.soldat, 1, 0), isFalse);
    });

    test('Garde : activée en diagonal, pousse en orthogonal', () {
      expect(pushActivated(PieceType.garde, 1, 1), isTrue);
      expect(pushActivated(PieceType.garde, 1, 0), isFalse);
      expect(pushValid(PieceType.garde, 0, 1), isTrue);
      expect(pushValid(PieceType.garde, 1, 1), isFalse);
    });

    test('le Chevalier bloque entièrement une ligne de poussée', () {
      final b = Board.empty();
      b.set(3, 3, Piece.blancGarde); // pousseur, après déplacement
      b.set(3, 4, Piece.noirNurse); // pièce poussée
      b.set(3, 5, Piece.noirChevalier); // mur
      final out = applyPushes(b, 3, 3, PieceType.garde, Camp.blanc,
          dirsToUse: const [(0, 1)]);
      expect(out.totalPushed, 0, reason: 'rien ne bouge');
      expect(b.at(3, 4), Piece.noirNurse, reason: 'la nurse reste en place');
      expect(b.at(3, 5), Piece.noirChevalier);
    });

    test('une pièce poussée hors du plateau est éjectée', () {
      final b = Board.empty();
      b.set(3, 6, Piece.blancGarde);
      b.set(3, 7, Piece.noirNurse); // au bord
      final out = applyPushes(b, 3, 6, PieceType.garde, Camp.blanc,
          dirsToUse: const [(0, 1)]);
      expect(out.ejOpp, 1);
      expect(out.ejAlly, 0);
      expect(b.at(3, 7), isNull, reason: 'la nurse a quitté le plateau');
    });

    test("l'Héritier éjecté hors de sa zone donne un mat", () {
      final b = Board.empty();
      b.set(0, 6, Piece.blancGarde);
      b.set(0, 7, Piece.noirHeritier); // colonne do : hors zone de ralliement
      final out = applyPushes(b, 0, 6, PieceType.garde, Camp.blanc,
          dirsToUse: const [(0, 1)]);
      expect(out.matOn, Camp.noir);
      expect(out.fugueBy, isNull);
    });

    test("l'Héritier poussé dans SA zone de ralliement fugue", () {
      final b = Board.empty();
      b.set(3, 6, Piece.noirGarde);
      b.set(3, 7, Piece.blancHeritier); // colonne fa, poussé vers row 8
      final out = applyPushes(b, 3, 6, PieceType.garde, Camp.noir,
          dirsToUse: const [(0, 1)]);
      expect(out.fugueBy, Camp.blanc, reason: 'Blanc fugue');
      expect(out.matOn, isNull);
      expect(out.ejOpp, 0);
    });
  });

  group('Immobilisation', () {
    test('une ronde isolée ne peut pas bouger', () {
      final b = Board.empty();
      b.set(3, 3, Piece.blancNurse); // seule au monde
      expect(b.isImmobilised(3, 3), isTrue);
      expect(generateMoves(b, Camp.blanc), isEmpty);
    });

    test('une ronde touchant une ronde adverse peut bouger', () {
      final b = Board.empty();
      b.set(3, 3, Piece.blancNurse);
      b.set(3, 4, Piece.noirNurse);
      expect(b.isImmobilised(3, 3), isFalse);
      expect(generateMoves(b, Camp.blanc), isNotEmpty);
    });

    test('le Chevalier ne compte pas comme voisin carré', () {
      final b = Board.empty();
      b.set(3, 3, Piece.blancSoldat);
      b.set(3, 4, Piece.blancChevalier);
      expect(b.hasSquareNeighbour(3, 3), isFalse);
      expect(b.isImmobilised(3, 3), isTrue);
    });

    test('le Chevalier bouge toujours, même seul', () {
      final b = Board.empty();
      b.set(3, 3, Piece.blancChevalier);
      expect(b.isImmobilised(3, 3), isFalse);
      expect(generateMoves(b, Camp.blanc).length, 8);
    });
  });

  group('Fins de partie', () {
    test('anySquareCanMove détecte la Trêve', () {
      final b = Board.empty();
      b.set(0, 0, Piece.blancSoldat); // isolée
      b.set(6, 7, Piece.noirGarde); // isolée
      expect(anySquareCanMove(b), isFalse);
      b.set(6, 6, Piece.noirSoldat); // voisine : débloque
      expect(anySquareCanMove(b), isTrue);
    });

    test('playerHasAnyMove détecte la Papatte', () {
      final b = Board.empty();
      b.set(0, 0, Piece.blancNurse); // ronde isolée : immobile
      expect(playerHasAnyMove(b, Camp.blanc), isFalse);
      b.set(0, 1, Piece.blancNurse); // deux rondes : elles se débloquent
      expect(playerHasAnyMove(b, Camp.blanc), isTrue);
    });

    test('campCanFugue voit la fugue en un coup', () {
      final b = Board.empty();
      b.set(3, 7, Piece.blancHeritier);
      b.set(3, 6, Piece.blancNurse); // voisine : l'Héritier peut bouger
      expect(campCanFugue(b, Camp.blanc), isTrue,
          reason: 'fa8 → ralliement row 8');
      expect(campCanFugue(b, Camp.noir), isFalse);
    });
  });
}
