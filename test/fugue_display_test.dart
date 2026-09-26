/// L'Héritier qui a fugué reste visible, dans son ralliement.
///
/// Il disparaissait purement et simplement du plateau au moment même où il
/// gagnait la partie : le contrôleur notait la fugue dans un coin, mais rien
/// ne la dessinait, et la relecture d'un `.nmc` ne la voyait même pas.
///
/// La case d'affichage est TOUJOURS le milieu du ralliement. Le `.nmc` ne dit
/// pas par laquelle des trois cases l'Héritier est sorti — « Fa8* » donne son
/// départ, pas son arrivée — donc le milieu est le seul choix qui donne la
/// même image en direct et en relecture.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/literal_replay.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/last_move.dart';
import 'package:lafuga/game/move_controller.dart';
import 'package:lafuga/game/nmc.dart';
import 'package:lafuga/game/replay_controller.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/screens/game_screen.dart';
import 'package:lafuga/ui/screens/replay_screen.dart';
import 'package:lafuga/ui/widgets/board_geometry.dart';
import 'package:lafuga/ui/widgets/board_painter.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  group('Où l Héritier s affiche', () {
    test('le milieu est bien la médiane de la zone de ralliement', () {
      final cols = kRally.toList()..sort();
      expect(
        kRallyMiddle,
        cols[cols.length ~/ 2],
        reason: 'la colonne du milieu ne tombe plus dans le ralliement',
      );
      expect(cols.length.isOdd, isTrue, reason: 'sans milieu, pas de milieu');
    });

    test('chaque camp a sa rangée, et la colonne du milieu', () {
      expect(rallyDisplayCell(Camp.blanc), const Cell(kRallyMiddle, 8));
      expect(rallyDisplayCell(Camp.noir), const Cell(kRallyMiddle, -1));
      // Hors du plateau de jeu : c'est bien une case de ralliement.
      expect(rallyDisplayCell(Camp.blanc).onBoard, isFalse);
      expect(rallyDisplayCell(Camp.noir).onBoard, isFalse);
    });
  });

  group('La relecture littérale constate la fugue', () {
    test('« Fa8* » : l Héritier sort par son ralliement', () {
      final b = Board.empty();
      b.set(3, 7, Piece.blancHeritier);
      final r = applyNotationLiterally(b, 'Fa8*');
      expect(r.ok, isTrue);
      expect(r.board.at(3, 7), isNull);
      expect(
        r.fugued,
        {Camp.blanc},
        reason: 'la relecture ne voit pas la fugue : l Héritier disparaît',
      );
    });

    test('une autre pièce qui sort n est pas une fugue', () {
      final b = Board.empty();
      b.set(3, 7, const Piece(PieceType.nurse, Camp.blanc));
      final r = applyNotationLiterally(b, 'Fa8*');
      expect(r.ok, isTrue);
      expect(r.fugued, isEmpty, reason: 'seul un Héritier fugue');
    });

    test('un Héritier POUSSÉ dans son ralliement fugue aussi', () {
      // Rien dans la notation ne l annonce : « Fa6-Fa7>Fa8 » se lit comme une
      // poussée ordinaire. C est en regardant ce qui quitte le plateau qu on
      // le sait — et c est exactement ce que fait le contrôleur en partie.
      final b = Board.empty();
      b.set(3, 5, const Piece(PieceType.garde, Camp.noir));
      b.set(3, 7, Piece.blancHeritier);
      final r = applyNotationLiterally(b, 'Fa6-Fa7>Fa8');
      expect(r.ok, isTrue);
      expect(r.board.at(3, 7), isNull);
      expect(r.fugued, {
        Camp.blanc,
      }, reason: 'une fugue par poussée passe inaperçue en relecture');
    });

    test('poussé hors du plateau AILLEURS, il est éjecté et non fugué', () {
      // Vers la rangée de ralliement ADVERSE : ce n est pas son ralliement.
      final versAdverse = Board.empty();
      versAdverse.set(3, 2, const Piece(PieceType.garde, Camp.noir));
      versAdverse.set(3, 0, Piece.blancHeritier);
      expect(
        applyNotationLiterally(versAdverse, 'Fa3-Fa2>Fa1').fugued,
        isEmpty,
        reason: 'le ralliement adverse n est pas le sien',
      );

      // Par une colonne sans ralliement, sur sa propre rangée.
      final horsColonne = Board.empty();
      horsColonne.set(0, 5, const Piece(PieceType.garde, Camp.noir));
      horsColonne.set(0, 7, Piece.blancHeritier);
      expect(
        applyNotationLiterally(horsColonne, 'Do6-Do7>Do8').fugued,
        isEmpty,
        reason: 'le ralliement n existe que sur les colonnes centrales',
      );
    });
  });

  group('Le lecteur de .nmc', () {
    /// Une partie d un seul coup : l Héritier blanc fugue depuis Fa8.
    String nmcDeFugue() => buildNmc(
      const NmcMeta(
        date: '2026-09-26',
        player1: 'Nino',
        player2: 'Deep Grey',
        blanc: 'Nino',
        objectif: 'partie',
        cadence: 'zen',
        result: '1-0',
        method: 'fugue',
        points: '2',
      ),
      ['Fa8*'],
    );

    Board positionAvant() {
      final b = Board.empty();
      b.set(3, 7, Piece.blancHeritier);
      b.set(2, 7, const Piece(PieceType.nurse, Camp.blanc));
      b.set(0, 0, Piece.noirHeritier);
      return b;
    }

    test('la position finale porte l Héritier fugué', () {
      final replay = ReplayController.fromNmc(
        nmcDeFugue(),
        initialBoard: positionAvant(),
      );
      expect(replay.moveCount, 1, reason: 'le coup ne s est pas relu');
      replay.toEnd();
      expect(
        replay.current.fugued,
        {Camp.blanc},
        reason:
            'la position finale ne montre pas l Héritier dans son '
            'ralliement : il a disparu de la partie',
      );
      expect(replay.current.board.at(3, 7), isNull);
    });

    test('le dernier coup reste encadré sur cette position', () {
      final replay = ReplayController.fromNmc(
        nmcDeFugue(),
        initialBoard: positionAvant(),
      );
      replay.toEnd();
      final last = replay.current.lastMove;
      expect(last, isNotNull);
      expect(
        last!.framedCells,
        contains(const Cell(3, 7)),
        reason: 'la case de départ de la fugue n est pas encadrée',
      );
    });

    test('reculer d un coup le remet sur le plateau', () {
      final replay = ReplayController.fromNmc(
        nmcDeFugue(),
        initialBoard: positionAvant(),
      );
      replay.toStart();
      expect(
        replay.current.fugued,
        isEmpty,
        reason: 'avant son coup, l Héritier n a pas encore fugué',
      );
      expect(replay.current.board.at(3, 7), isNotNull);
    });
  });

  group('Le plateau le dessine', () {
    const taille = Size(350, 500);

    /// Peint la couche des pièces et compte, case par case, les pixels
    /// réellement posés.
    ///
    /// Tout se passe dans `runAsync` : sous l horloge simulée des tests,
    /// `toImage` ne rend jamais sa main et le test reste suspendu pour
    /// toujours — ce qui s est produit en écrivant celui-ci.
    final geometry = BoardGeometry(size: taille, flipped: true);

    Future<List<int>> pixelsDe(
      WidgetTester tester, {
      required Set<Camp> fugued,
      required List<Rect> zones,
      LastMove? lastMove,
    }) async {
      final compte = <int>[];
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final board = Board.empty();
        // Une pièce SUR le plateau : sans elle, un peintre qui ne peindrait
        // rien du tout passerait pour un ralliement vide.
        board.set(0, 0, Piece.noirHeritier);
        BoardPiecesPainter(
          geometry: geometry,
          palette: paletteOf(kDefaultTheme),
          board: board,
          fuguedHeirs: fugued,
          lastMove: lastMove,
        ).paint(canvas, taille);

        final image = await recorder.endRecording().toImage(
          taille.width.toInt(),
          taille.height.toInt(),
        );
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;

        for (final zone in zones) {
          var n = 0;
          for (var y = zone.top.ceil(); y < zone.bottom.floor(); y++) {
            for (var x = zone.left.ceil(); x < zone.right.floor(); x++) {
              if (x < 0 || y < 0 || x >= image.width || y >= image.height) {
                continue;
              }
              // Canal alpha : un pixel posé, quelle que soit sa couleur.
              if (data.getUint8((y * image.width + x) * 4 + 3) != 0) n++;
            }
          }
          compte.add(n);
        }
      });
      return compte;
    }

    testWidgets('l Héritier est peint au MILIEU du ralliement', (tester) async {
      final colonnes = kRally.toList()..sort();
      final compte = await pixelsDe(
        tester,
        fugued: {Camp.blanc},
        zones: [for (final c in colonnes) geometry.cellRect(c, 8)],
      );
      final milieu = colonnes.indexOf(kRallyMiddle);
      expect(
        compte[milieu],
        greaterThan(0),
        reason:
            'rien n est peint au milieu du ralliement blanc : '
            'l Héritier disparaît au moment où il gagne',
      );
      // Et nulle part ailleurs : la règle est « toujours au milieu », pas
      // « quelque part dans le ralliement ».
      for (var i = 0; i < colonnes.length; i++) {
        if (i == milieu) continue;
        expect(
          compte[i],
          0,
          reason:
              'l Héritier est peint hors du milieu '
              '(colonne ${colonnes[i]})',
        );
      }
    });

    testWidgets('sans fugue, le ralliement reste vide', (tester) async {
      final compte = await pixelsDe(
        tester,
        fugued: const {},
        zones: [for (final c in kRally) geometry.cellRect(c, 8)],
      );
      expect(
        compte.every((n) => n == 0),
        isTrue,
        reason: 'une pièce est peinte dans un ralliement sans fugue',
      );
    });

    testWidgets('chaque camp dans SON ralliement', (tester) async {
      final compte = await pixelsDe(
        tester,
        fugued: {Camp.noir},
        zones: [
          geometry.cellRect(kRallyMiddle, -1),
          geometry.cellRect(kRallyMiddle, 8),
        ],
      );
      expect(
        compte[0],
        greaterThan(0),
        reason: 'l Héritier noir n est pas peint dans son ralliement',
      );
      expect(
        compte[1],
        0,
        reason: 'il est peint dans le ralliement du mauvais camp',
      );
    });

    testWidgets('le cadre du dernier coup entoure vraiment le ralliement', (
      tester,
    ) async {
      // On compte ce que le cadre AJOUTE sur la case, l Héritier étant peint
      // dans les deux images. Viser un coin ne marchait pas : l anticrénelage
      // du cercle y laisse deux ou trois pixels, et un seuil à zéro s y
      // cassait.
      //
      // Sans cette mesure, « la case d arrivée est encadrée » ne serait qu une
      // affirmation sur un ensemble de cases, pas sur ce qui est peint — et le
      // peintre écartait justement toute case hors du plateau de jeu.
      final avant = Board.empty();
      avant.set(3, 7, Piece.blancHeritier);
      final apres = applyNotationLiterally(avant, 'Fa8*').board;
      final last = lastMoveFromNotation('Fa8*', avant, apres)!;
      final zone = [geometry.cellRect(kRallyMiddle, 8)];

      final sansCadre = await pixelsDe(
        tester,
        fugued: {Camp.blanc},
        zones: zone,
      );
      final avecCadre = await pixelsDe(
        tester,
        fugued: {Camp.blanc},
        zones: zone,
        lastMove: last,
      );

      expect(
        sansCadre.first,
        greaterThan(0),
        reason: 'l Héritier n est pas peint : la mesure ne prouve rien',
      );
      // Le cadre fait le tour de la case : au bas mot un périmètre de trait.
      final perimetre = (geometry.cellSize * 4 * 2).round();
      expect(
        avecCadre.first - sansCadre.first,
        greaterThan(perimetre),
        reason:
            'le cadre du dernier coup n est pas peint autour du ralliement '
            '(${avecCadre.first} contre ${sansCadre.first} pixels) : '
            'la fugue reste montrée à moitié',
      );
    });
  });

  group('En partie', () {
    test('une fugue jouée pour de vrai est retenue', () {
      final board = Board.empty();
      board.set(3, 7, Piece.blancHeritier);
      board.set(2, 7, const Piece(PieceType.nurse, Camp.blanc));
      board.set(0, 0, Piece.noirHeritier);
      final game = MoveController(board: board);

      // Le coup légal qui fait sortir l Héritier par son ralliement.
      final fugue = generateMoves(game.board, Camp.blanc).firstWhere(
        (m) => m.to.row == 8 && kRally.contains(m.to.col),
        orElse: () =>
            throw StateError('aucune fugue possible : test sans objet'),
      );
      game.applyGeneratedMove(fugue);

      expect(
        game.fuguedHeirs,
        {Camp.blanc},
        reason: 'la partie ne retient pas la fugue qu elle vient de voir',
      );
      expect(game.gameOver, isTrue);
    });

    test('la glissée du doigt finit là où l Héritier s affichera', () {
      // Sinon la pièce se pose sur sa colonne de sortie puis saute d une case
      // pour rejoindre le milieu, juste au moment où la partie s achève.
      //
      // Le coup est joué au DOIGT : un coup construit ailleurs (IA, réseau)
      // n a jamais de glissée de sortie, parce que `_slidesBetween` ne compare
      // que les rangées jouables et qu une pièce qui quitte le plateau n y a
      // pas d arrivée. Kivy a la même limite (`_build_slides_from_diff`) : je
      // ne lui ajoute pas une animation qu il n a pas.
      final board = Board.empty();
      board.set(2, 7, Piece.blancHeritier);
      board.set(3, 7, const Piece(PieceType.nurse, Camp.blanc));
      board.set(0, 0, Piece.noirHeritier);
      final game = MoveController(board: board);

      final fugue = generateMoves(game.board, Camp.blanc).firstWhere(
        (m) =>
            m.from == const Cell(2, 7) &&
            m.to.row == 8 &&
            m.to.col != kRallyMiddle,
        orElse: () => throw StateError(
          'aucune fugue hors du milieu : le test ne prouve rien',
        ),
      );

      game.tapCell(fugue.from);
      final result = game.tapCell(fugue.to);

      expect(game.fuguedHeirs, {
        Camp.blanc,
      }, reason: 'la fugue n a pas eu lieu');
      final arrivees = [for (final (_, _, to) in result.slides) to];
      expect(
        arrivees,
        contains(rallyDisplayCell(Camp.blanc)),
        reason: 'la glissée ne vise pas la case où l Héritier se posera',
      );
      expect(
        arrivees,
        isNot(contains(fugue.to)),
        reason: 'elle vise encore la colonne de sortie : la pièce sautera',
      );
    });

    test('une partie reprise reçoit la fugue déjà faite', () {
      // Analyse, correspondance, reconnexion : le plateau vient d ailleurs, et
      // sans cette graine l Héritier ne serait nulle part.
      final game = MoveController(board: Board.empty(), fugued: {Camp.noir});
      expect(game.fuguedHeirs, {Camp.noir});
    });
  });

  group('Le dernier coup encadre AUSSI le ralliement', () {
    Board avantFugueBlanche() {
      final b = Board.empty();
      b.set(3, 7, Piece.blancHeritier);
      b.set(2, 7, const Piece(PieceType.nurse, Camp.blanc));
      return b;
    }

    test('l arrivée est le ralliement du camp qui fugue', () {
      final avant = avantFugueBlanche();
      final apres = applyNotationLiterally(avant, 'Fa8*').board;
      final last = lastMoveFromNotation('Fa8*', avant, apres);
      expect(last, isNotNull);
      expect(
        last!.to,
        {rallyDisplayCell(Camp.blanc)},
        reason:
            'la fugue était le seul coup montré à moitié : le départ '
            'encadré, l arrivée nulle part',
      );
      expect(last.from, {const Cell(3, 7)});
      expect(
        last.camp,
        Camp.blanc,
        reason:
            'le camp ne peut pas se lire sur la position d après, '
            'l Héritier n y est plus : cadre de la mauvaise couleur',
      );
    });

    test('sans la position d avant, on s en tient au départ', () {
      // Mieux vaut un cadre en moins qu un cadre autour du mauvais ralliement.
      final last = lastMoveFromNotation('Fa8*', null, Board.empty());
      expect(last!.from, {const Cell(3, 7)});
      expect(last.to, isEmpty);
    });

    test('une pièce qui n est pas un Héritier n encadre pas le ralliement', () {
      final avant = Board.empty();
      avant.set(3, 7, const Piece(PieceType.nurse, Camp.blanc));
      final last = lastMoveFromNotation('Fa8*', avant, Board.empty());
      expect(
        last!.to,
        isEmpty,
        reason: 'seul un Héritier rejoint un ralliement',
      );
    });
  });

  group('La sortie glisse dans tous les modes', () {
    /// Position d où l Héritier blanc peut fuguer, avec sa Nurse pour l aider.
    MoveController partiePrete({required int colonneHeritier}) {
      final b = Board.empty();
      b.set(colonneHeritier, 7, Piece.blancHeritier);
      b.set(
        colonneHeritier == 2 ? 3 : 2,
        7,
        const Piece(PieceType.nurse, Camp.blanc),
      );
      b.set(0, 0, Piece.noirHeritier);
      return MoveController(board: b);
    }

    test('un coup construit ailleurs fait glisser l Héritier aussi', () {
      // Deep Grey, l adversaire en ligne, une correspondance : le coup arrive
      // déjà fait. `_slidesBetween` ne voyait qu un départ sans arrivée et ne
      // produisait aucune glissée — l Héritier disparaissait d un coup sec sur
      // le coup le plus important de la partie.
      final game = partiePrete(colonneHeritier: 2);
      final fugue = generateMoves(game.board, Camp.blanc).firstWhere(
        (m) => m.from == const Cell(2, 7) && m.to.row == 8,
        orElse: () => throw StateError('aucune fugue jouable'),
      );
      final result = game.applyGeneratedMove(fugue);

      expect(game.fuguedHeirs, {
        Camp.blanc,
      }, reason: 'pas de fugue : test vain');
      expect(
        result.slides,
        contains((
          Piece.blancHeritier,
          const Cell(2, 7),
          rallyDisplayCell(Camp.blanc),
        )),
        reason: 'l Héritier ne glisse pas jusqu à son ralliement',
      );
    });

    test('poussé dans son ralliement, il glisse depuis sa case', () {
      // Un Garde n active sa poussée qu en se déplaçant EN DIAGONALE, et
      // pousse ensuite orthogonalement. Celui-ci va donc de (2,5) à (3,6) en
      // diagonale, puis pousse l Héritier de (3,7) vers son ralliement. Son
      // voisin carré est là parce qu une carrée isolée est immobile.
      final b = Board.empty();
      b.set(3, 7, Piece.blancHeritier);
      b.set(2, 5, const Piece(PieceType.garde, Camp.noir));
      b.set(1, 5, const Piece(PieceType.garde, Camp.noir));
      b.set(0, 0, Piece.noirHeritier);
      final game = MoveController(board: b, turn: Camp.noir);

      final poussee = generateMoves(game.board, Camp.noir).where((m) {
        final essai = MoveController(board: b.clone(), turn: Camp.noir);
        essai.applyGeneratedMove(m);
        return essai.fuguedHeirs.contains(Camp.blanc);
      }).toList();
      if (poussee.isEmpty) {
        // Pas de poussée gagnante depuis cette position : le test ne doit pas
        // se taire pour autant.
        fail(
          'aucune poussée n envoie l Héritier au ralliement : test à revoir',
        );
      }

      final result = game.applyGeneratedMove(poussee.first);
      expect(
        [
          for (final (piece, _, to) in result.slides)
            if (piece.isHeir) to,
        ],
        contains(rallyDisplayCell(Camp.blanc)),
        reason: 'un Héritier poussé dehors ne glisse pas jusqu à sa zone',
      );
    });
  });

  group('À la fin d une partie jouée', () {
    testWidgets('le plateau garde la position finale, l Héritier et le cadre', (
      tester,
    ) async {
      // Position d où l Héritier blanc peut fuguer tout de suite. La Nurse est
      // là parce qu une pièce ronde ne bouge qu en touchant une autre ronde.
      final depart = Board.empty();
      depart.set(3, 7, Piece.blancHeritier);
      depart.set(2, 7, const Piece(PieceType.nurse, Camp.blanc));
      depart.set(0, 0, Piece.noirHeritier);

      await tester.pumpWidget(
        MaterialApp(home: GameScreen(aiCamp: null, initialBoard: depart)),
      );
      await tester.pumpAndSettle();

      final view = tester.widget<GameBoardView>(find.byType(GameBoardView));
      final fugue = generateMoves(view.board, Camp.blanc).firstWhere(
        (m) => m.to.row == 8 && kRally.contains(m.to.col),
        orElse: () =>
            throw StateError('aucune fugue jouable : le test ne prouve rien'),
      );

      view.onTapCell(fugue.from);
      await tester.pump();
      view.onTapCell(fugue.to);
      await tester.pumpAndSettle();

      final apres = tester.widget<GameBoardView>(find.byType(GameBoardView));
      expect(
        apres.fuguedHeirs,
        {Camp.blanc},
        reason: 'la partie est gagnée et l Héritier n est plus nulle part',
      );
      expect(
        apres.board.atCell(fugue.from),
        isNull,
        reason: 'la position affichée n est pas celle d après le coup final',
      );
      expect(
        apres.lastMove?.framedCells,
        contains(fugue.from),
        reason: 'le coup final n est pas mis en évidence',
      );
    });
  });

  group('Le lecteur affiche ce que la relecture a constaté', () {
    testWidgets('l écran de relecture passe la fugue au plateau', (
      tester,
    ) async {
      final nmc = buildNmc(
        const NmcMeta(
          date: '2026-09-26',
          player1: 'Nino',
          player2: 'Copine',
          blanc: 'Nino',
          objectif: 'partie',
          cadence: 'zen',
          result: '1-0',
          method: 'fugue',
          points: '2',
        ),
        ['Fa8*'],
      );
      // L écran part de la position standard : Fa8 y porte l Héritier NOIR,
      // c est donc lui qui fugue. Le camp est lu sur le plateau plutôt
      // qu écrit en dur, pour que le test dise pourquoi il attend celui-là.
      final camp = Board.initial().at(3, 7)!.camp;
      expect(Board.initial().at(3, 7)!.isHeir, isTrue, reason: 'fixture');

      await tester.pumpWidget(MaterialApp(home: ReplayScreen(nmc: nmc)));
      await tester.pumpAndSettle();

      final view = tester.widget<GameBoardView>(find.byType(GameBoardView));
      expect(
        view.fuguedHeirs,
        {camp},
        reason: "l historique n affiche pas l Héritier dans son ralliement",
      );
    });
  });
}
