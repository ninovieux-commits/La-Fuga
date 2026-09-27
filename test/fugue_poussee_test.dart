/// La fugue obtenue EN POUSSANT, et ce que le `.nmc` en disait.
///
/// Nino : « Nmc devrait afficher fa6-fa7>fa8* normalement. Sinon il faut
/// modifier le système nmc (ainsi que le lecteur) pour que ce soit le cas. »
///
/// Le jeu écrivait « Fa4* » — la case de départ du POUSSEUR — sans sa case
/// d'arrivée ni ce qu'il poussait. Tout le coup était perdu : relue, la
/// partie effaçait le pousseur du plateau et ratait la fugue. Une partie
/// finie ainsi ne se rejouait donc pas jusqu'au bout.
///
/// Deux bouts à tenir : ne plus l'écrire, et savoir relire celles qui
/// l'ont déjà été.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/literal_replay.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/notation.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/game_archive.dart';
import 'package:lafuga/game/move_controller.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Une position où les Noirs peuvent pousser l'Héritier BLANC dans le
/// ralliement blanc : il fugue, donc il gagne, alors que ce sont les Noirs
/// qui jouent.
Board _positionDePoussee() {
  final b = Board.empty();
  b.set(3, 7, Piece.blancHeritier);
  b.set(2, 5, const Piece(PieceType.garde, Camp.noir));
  b.set(1, 5, const Piece(PieceType.garde, Camp.noir));
  b.set(0, 0, Piece.noirHeritier);
  return b;
}

/// Une fugue par poussée dont la reconstruction est AMBIGUË : le Garde noir
/// de Mi6 peut pousser plusieurs lignes, et la vieille notation « Mi6* » ne
/// dit pas lesquelles. Huit coups légaux, huit positions.
Board _positionAmbigue() {
  final b = Board.empty();
  b.set(3, 7, Piece.blancHeritier);
  b.set(2, 5, const Piece(PieceType.garde, Camp.noir));
  b.set(0, 0, Piece.noirHeritier);
  for (final c in const [Cell(2, 6), Cell(4, 6), Cell(3, 5)]) {
    b.set(c.col, c.row, const Piece(PieceType.soldat, Camp.blanc));
  }
  return b;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
  });

  group('Ce que le jeu écrit maintenant', () {
    /// Joue la poussée gagnante au doigt, comme un joueur : la pièce, sa
    /// case d'arrivée (le Garde active sa poussée en allant en DIAGONALE),
    /// puis la case à pousser.
    (MoveController, String) jouerLaPoussee() {
      final depart = _positionDePoussee();
      final gagnant = generateMoves(
        depart,
        Camp.noir,
      ).where((m) => m.fugueBy == Camp.blanc).toList();
      expect(gagnant, isNotEmpty, reason: 'aucune poussée gagnante');
      final coup = gagnant.first;

      final c = MoveController(board: depart.clone(), turn: Camp.noir);
      c.tapCell(coup.from);
      c.tapCell(coup.to);
      c.tapCell(const Cell(3, 7));
      expect(c.history, isNotEmpty, reason: 'aucun coup enregistré');
      return (c, c.history.last);
    }

    test('la poussée est écrite en toutes lettres', () {
      final depart = _positionDePoussee();
      final coup = generateMoves(
        depart,
        Camp.noir,
      ).firstWhere((m) => m.fugueBy == Camp.blanc);
      final (_, ecrit) = jouerLaPoussee();

      expect(
        ecrit,
        isNot('${cellToNotationOf(coup.from)}*'),
        reason: 'le coup est encore écrit « Départ* » : tout est perdu',
      );
      expect(ecrit, contains('-'), reason: 'la case d arrivée manque');
      expect(ecrit, contains('>'), reason: 'la poussée manque');
      expect(
        ecrit,
        startsWith(
          '${cellToNotationOf(coup.from)}-${cellToNotationOf(coup.to)}',
        ),
        reason: 'le déplacement du pousseur doit être écrit tel quel',
      );
    });

    test('les deux orthographes du .nmc, telles que Nino les décrit', () {
      // « Fa2-Fa3> »        : toutes les lignes poussables l ont été.
      // « Fa2-Fa3>Mi4Sol4 » : ces deux-là seulement.
      // Une fugue par poussée n a aucune raison de s écrire autrement.
      final b = _positionAmbigue();

      MoveController jouer(List<Cell> gestes) {
        final c = MoveController(board: b.clone(), turn: Camp.noir);
        for (final g in gestes) {
          c.tapCell(g);
        }
        return c;
      }

      // Mi6 -> Fa7 en diagonale (le Garde active ainsi sa poussée), puis on
      // pousse les QUATRE lignes qui partent de Fa7 : Mi7, Sol7, Fa6, et
      // Fa8 où est l'Héritier. En oublier une suffit à faire nommer les
      // autres — c'est ce que ce test a attrapé.
      final toutes = jouer(const [
        Cell(2, 5),
        Cell(3, 6),
        Cell(2, 6),
        Cell(4, 6),
        Cell(3, 5),
        Cell(3, 7),
      ]);
      expect(
        toutes.history.last,
        'Mi6-Fa7>',
        reason: 'tout poussé : rien ne doit suivre le chevron',
      );

      final deux = jouer(const [
        Cell(2, 5),
        Cell(3, 6),
        Cell(2, 6),
        Cell(3, 7),
      ]);
      expect(
        deux.history.last,
        'Mi6-Fa7>Mi7Fa8',
        reason: 'les lignes poussées doivent être nommées',
      );

      // Et les deux se relisent, marque de fin comprise.
      for (final c in [toutes, deux]) {
        final marque = withEndSuffix([c.history.last], 'fugue').single;
        expect(marque, endsWith('*'));
        final relu = applyNotationLiterally(b, marque);
        expect(relu.ok, isTrue, reason: 'illisible : $marque');
        expect(relu.fugued, {Camp.blanc}, reason: 'fugue ratée : $marque');
        expect(
          relu.board.positionKey(Camp.blanc),
          c.board.positionKey(Camp.blanc),
          reason: 'la position relue diffère de celle jouée : $marque',
        );
      }
    });

    test('et ce qui est écrit se rejoue à l identique', () {
      final depart = _positionDePoussee();
      final (c, ecrit) = jouerLaPoussee();

      // La marque de fin que l archive ajoute ne doit pas gêner la relecture.
      final marque = withEndSuffix([ecrit], 'fugue').single;
      final relu = applyNotationLiterally(depart, marque);
      expect(relu.ok, isTrue);
      expect(relu.fugued, {
        Camp.blanc,
      }, reason: 'la relecture ne voit pas la fugue');
      expect(
        relu.board.at(3, 7),
        isNull,
        reason: 'l Héritier blanc doit avoir quitté le plateau',
      );
      expect(
        relu.board.positionKey(Camp.noir),
        c.board.positionKey(Camp.noir),
        reason: 'la position relue diffère de celle jouée',
      );
    });
  });

  group('Les vieilles notations « Départ* »', () {
    test('le pousseur n est plus effacé, et la fugue est vue', () {
      final b = _positionDePoussee();
      final coup = generateMoves(
        b,
        Camp.noir,
      ).firstWhere((m) => m.fugueBy == Camp.blanc);
      final vieille = '${cellToNotationOf(coup.from)}*';

      final r = applyNotationLiterally(b, vieille);
      expect(r.ok, isTrue, reason: 'le coup n a pas été retrouvé');
      expect(r.fugued, {
        Camp.blanc,
      }, reason: 'c est l Héritier BLANC qui fugue, pas celui qui pousse');
      expect(
        r.board.at(3, 7),
        isNull,
        reason: 'l Héritier blanc doit avoir quitté le plateau',
      );
      // Le Garde noir qui poussait était purement et simplement supprimé.
      var gardes = 0;
      for (var c = 0; c < 7; c++) {
        for (var row = 0; row < 8; row++) {
          final p = r.board.at(c, row);
          if (p != null && p.type == PieceType.garde && p.camp == Camp.noir) {
            gardes++;
          }
        }
      }
      expect(gardes, 2, reason: 'un Garde noir a disparu du plateau');
    });

    test('l Héritier qui sort de lui-même s écrit toujours « Départ* »', () {
      // Le cas normal ne change pas : sa case d arrivée n a pas de nom.
      final b = Board.empty();
      b.set(3, 7, Piece.blancHeritier);
      final r = applyNotationLiterally(b, 'Fa8*');
      expect(r.ok, isTrue);
      expect(r.fugued, {Camp.blanc});
      expect(r.board.at(3, 7), isNull);
    });

    test('rien de fuguant depuis cette case : on ne touche à rien', () {
      final b = Board.empty();
      b.set(0, 0, const Piece(PieceType.soldat, Camp.blanc));
      b.set(3, 7, Piece.noirHeritier);
      final r = applyNotationLiterally(b, 'Do1*');
      expect(r.ok, isFalse);
      expect(r.fugued, isEmpty);
      expect(
        r.board.at(0, 0),
        isNotNull,
        reason: 'la pièce a été effacée alors que le coup est incompréhensible',
      );
    });

    test('à reconstructions multiples, la relecture reste la même', () {
      // Le cœur du sujet : la vieille notation ne dit pas quelles AUTRES
      // lignes ont été poussées en même temps. Ici huit coups légaux partent
      // de Mi6 et donnent huit positions différentes — toutes une fugue
      // blanche. Deux appareils qui relisent la partie doivent pourtant
      // trouver le même plateau, sinon la partie diverge pour toujours.
      final b = _positionAmbigue();
      final cands = generateMoves(
        b,
        Camp.noir,
      ).where((m) => m.fugue || m.fugueBy != null).toList();
      expect(
        {for (final m in cands) m.board.positionKey(Camp.blanc)}.length,
        greaterThan(1),
        reason: 'position sans ambiguïté : le test ne prouverait rien',
      );

      final cles = {
        for (var i = 0; i < 8; i++)
          applyNotationLiterally(b, 'Mi6*').board.positionKey(Camp.blanc),
      };
      expect(
        cles.length,
        1,
        reason: 'la relecture change d une fois à l autre',
      );

      // Et c est la plus SOBRE : celle qui déplace le moins de pièces.
      var moindre = 999;
      for (final m in cands) {
        var n = 0;
        for (var c = 0; c < 7; c++) {
          for (var r = 0; r < 8; r++) {
            if (b.at(c, r) != m.board.at(c, r)) n++;
          }
        }
        if (n < moindre) moindre = n;
      }
      final relu = applyNotationLiterally(b, 'Mi6*').board;
      var bouge = 0;
      for (var c = 0; c < 7; c++) {
        for (var r = 0; r < 8; r++) {
          if (b.at(c, r) != relu.at(c, r)) bouge++;
        }
      }
      expect(
        bouge,
        moindre,
        reason: 'la reconstruction retenue invente plus que nécessaire',
      );
      expect(
        applyNotationLiterally(b, 'Mi6*').fugued,
        {Camp.blanc},
        reason: 'le vainqueur, lui, ne souffre d aucune ambiguïté',
      );
    });
  });
}
