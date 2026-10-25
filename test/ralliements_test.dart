/// Les zones de ralliement, choisies position par position.
///
/// Nino : « en personnalisé, ce serait bien qu'il y ait écrit "modifier" sur
/// les zones de ralliement. Quand on clique dessus, ça encadre les 7 zones
/// possibles et on peut choisir entre 0 et 7 cases possibles pour le
/// ralliement (si 0 cases, fugue impossible (logique)). […] S'il n'y a pas
/// ces deux lignes dans un code .fug, alors il s'agit de la position
/// originale. »
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/fug.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/game/move_controller.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/position_composer_screen.dart';
import 'package:lafuga/ui/widgets/board_geometry.dart';
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
  tearDown(resetScale);

  group('Le masque', () {
    test('celui d origine est les trois du milieu', () {
      expect(Ralliements.standard.colonnes(Camp.blanc), [2, 3, 4]);
      expect(Ralliements.standard.colonnes(Camp.noir), [2, 3, 4]);
      expect(Ralliements.standard.estStandard, isTrue);
    });

    test('le milieu est la MÉDIANE, pas la colonne 3', () {
      // C est là que s affiche un Héritier qui a fugué : le .nmc ne dit pas
      // par quelle case il est sorti, il faut donc une case et une seule.
      const deuxAGauche = Ralliements(blanc: 1 | 2, noir: 1 | 2);
      expect(deuxAGauche.milieu(Camp.blanc), 1);
      expect(Ralliements.standard.milieu(Camp.blanc), 3);
      expect(const Ralliements(blanc: 0, noir: 0).milieu(Camp.blanc), isNull);
    });

    test('une zone vide ferme la fugue de ce camp', () {
      const sansBlanc = Ralliements(blanc: 0, noir: 1 << 3);
      expect(sansBlanc.estFerme(Camp.blanc), isTrue);
      expect(sansBlanc.estFerme(Camp.noir), isFalse);
    });

    test('basculer met, puis retire', () {
      var r = Ralliements.standard;
      expect(r.contient(Camp.blanc, 0), isFalse);
      r = r.bascule(Camp.blanc, 0);
      expect(r.contient(Camp.blanc, 0), isTrue);
      r = r.bascule(Camp.blanc, 0);
      expect(r.contient(Camp.blanc, 0), isFalse);
      expect(
        r,
        Ralliements.standard,
        reason: 'on est revenu au point de départ',
      );
    });
  });

  group('Le format .fug', () {
    /// Une position jouable quelconque, écrite en huit rangées.
    const rangees = [
      'sgshgsg',
      'gnnnnns',
      '-------',
      '-------',
      '-------',
      '-------',
      'GNNNNNS',
      'SGSHGSG',
    ];
    String code(String tete) => '$tete\n${rangees.join('\n')}';

    test('sans les deux lignes, ce sont les zones d origine', () {
      final lu = fugLire(code('B'));
      expect(lu.erreur, isNull);
      expect(lu.position!.board.rall, Ralliements.standard);
    });

    test('avec les deux lignes, ce sont celles-là', () {
      final lu = fugLire(code('rr-----\n--r-r--\nB'));
      expect(lu.erreur, isNull);
      final rall = lu.position!.board.rall;
      expect(rall.colonnes(Camp.blanc), [0, 1]);
      expect(rall.colonnes(Camp.noir), [2, 4]);
    });

    test('une zone peut être vide des deux côtés', () {
      final lu = fugLire(code('-------\n-------\nN'));
      expect(lu.erreur, isNull);
      expect(lu.position!.board.rall.estFerme(Camp.blanc), isTrue);
      expect(lu.position!.board.rall.estFerme(Camp.noir), isTrue);
    });

    test('une seule ligne de ralliement est refusée : elles vont par deux', () {
      final lu = fugLire(code('rr-----\nB'));
      expect(lu.erreur, FugErreur.ralliement);
    });

    test('un .fug ordinaire s écrit comme avant, sans les deux lignes', () {
      final ecrit = fugEcrire(Board.initial(), Camp.blanc);
      expect(ecrit.split('\n').first, 'B');
      expect(ecrit.split('\n'), hasLength(kRows + 1));
    });

    test('et l aller-retour garde les zones choisies', () {
      const choisies = Ralliements(blanc: 1 | 2, noir: 1 << 6);
      final avant = Board.initial().avecRalliements(choisies);
      final ecrit = fugEcrire(avant, Camp.noir);
      expect(ecrit.split('\n').first, 'rr-----');
      expect(ecrit.split('\n')[1], '------r');
      expect(ecrit.split('\n')[2], 'N');

      final relu = fugLire(ecrit);
      expect(relu.erreur, isNull);
      expect(relu.position!.board.rall, choisies);
    });

    test('plusieurs Chevaliers ne sont plus refusés', () {
      final r = [...rangees];
      r[1] = 'cc-----';
      final lu = fugLire('B\n${r.join('\n')}');
      expect(lu.erreur, isNull);
      expect(fugRefus(lu.position!.board), isNull);
    });
  });

  group('La fugue suit les zones choisies', () {
    /// Un Héritier blanc en fa8, prêt à sortir, et de quoi le faire bouger.
    Board plateau(Ralliements rall) {
      final b = Board.empty(rall: rall);
      b.set(3, 7, Piece.blancHeritier);
      b.set(3, 6, Piece.blancNurse);
      b.set(0, 0, Piece.noirHeritier);
      b.set(1, 0, Piece.noirNurse);
      return b;
    }

    test('sur les zones d origine, il sort par le milieu', () {
      final coups = generateMoves(plateau(Ralliements.standard), Camp.blanc);
      expect(
        coups.any((m) => m.fugue),
        isTrue,
        reason: 'fa est dans --rrr-- : la fugue existe',
      );
    });

    test('une zone déplacée déplace la fugue', () {
      // Les Blancs ne rallient plus qu en do et ré : fa8 n y mène plus.
      const aGauche = Ralliements(blanc: 1 | 2, noir: 1 << 3);
      final coups = generateMoves(plateau(aGauche), Camp.blanc);
      expect(
        coups.any((m) => m.fugue),
        isFalse,
        reason:
            'l Héritier est en fa : il ne peut pas rallier do ou ré d un pas',
      );
    });

    test('une zone vide interdit la fugue, et rien d autre', () {
      const fermee = Ralliements(blanc: 0, noir: 1 << 3);
      final b = plateau(fermee);
      final coups = generateMoves(b, Camp.blanc);
      expect(coups.any((m) => m.fugue), isFalse);
      expect(
        coups,
        isNotEmpty,
        reason: 'on ne peut plus fuguer, mais on joue encore',
      );
      expect(b.isFugueDest(3, 8, Piece.blancHeritier), isFalse);
    });

    test('et sur une zone choisie, elle redevient possible', () {
      const surFa = Ralliements(blanc: 1 << 3, noir: 1 << 3);
      final b = plateau(surFa);
      expect(b.isFugueDest(3, 8, Piece.blancHeritier), isTrue);
      expect(b.isFugueDest(2, 8, Piece.blancHeritier), isFalse);
    });
  });

  group('L Héritier se pose où il va vraiment', () {
    // Nino : « l'héritier pourrait simplement apparaître sur la case du
    // ralliement où il va / est poussé. »

    test('en partie, c est la case exacte : on la connaît', () {
      final b = Board.empty();
      b.set(2, 7, Piece.blancHeritier);
      b.set(3, 7, Piece.blancNurse);
      b.set(0, 0, Piece.noirHeritier);
      final jeu = MoveController(board: b);

      // Une sortie par do♯… pardon : par la colonne 2, qui n est pas le
      // milieu de la zone.
      jeu.tapCell(const Cell(2, 7));
      jeu.tapCell(const Cell(2, 8));

      expect(jeu.fuguedHeirs, {Camp.blanc});
      expect(
        jeu.casesDeFugue[Camp.blanc],
        const Cell(2, 8),
        reason: 'il se pose là où il est sorti, pas au milieu de la bande',
      );
    });

    test('en relecture, la déduction retrouve la même case', () {
      // Le `.nmc` écrit « Mi7* » : il dit d où l Héritier part, pas où il
      // arrive. On préfère donc la case de la zone la plus PROCHE de sa
      // colonne de départ — avec `--rrr--`, il n y en a jamais qu une à un
      // pas de lui, et la relecture montre ce que la partie a montré.
      final b = Board.empty();
      // Colonne de départ (rangée 7) → colonne d arrivée déduite.
      // do et si sont à DEUX pas de la zone : aucun pas ne les y mène, et un
      // Héritier ne peut donc pas y fuguer. La médiane reste alors comme
      // valeur de repli, et personne ne la voit jamais.
      const attendu = {0: 3, 1: 2, 2: 2, 3: 3, 4: 4, 5: 4, 6: 3};
      for (final e in attendu.entries) {
        expect(
          b.caseDeFugueAffichee(Camp.blanc, depuis: Cell(e.key, 7)).col,
          e.value,
          reason: 'parti de la colonne ${e.key}',
        );
      }
    });

    test('sans savoir d où il part, on retombe sur la médiane', () {
      final b = Board.empty();
      expect(b.caseDeFugueAffichee(Camp.noir), const Cell(3, -1));
    });

    test('sur une zone choisie, la case exacte suit', () {
      final b = Board.empty(
        rall: const Ralliements(blanc: 1 | (1 << 6), noir: 1 << 3),
      );
      expect(
        b.caseDeFugueAffichee(Camp.blanc, depuis: const Cell(0, 7)).col,
        0,
      );
      expect(
        b.caseDeFugueAffichee(Camp.blanc, depuis: const Cell(6, 7)).col,
        6,
      );
    });
  });

  group('Le composeur', () {
    Future<void> ouvrir(WidgetTester tester) async {
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      setScaleSize(const Size(393, 851));
      await tester.pumpWidget(
        const MaterialApp(home: PositionComposerScreen()),
      );
      await tester.pumpAndSettle();
    }

    GameBoardView vue(WidgetTester tester) =>
        tester.widget<GameBoardView>(find.byType(GameBoardView));

    testWidgets('« Modifier » est écrit sur les zones', (tester) async {
      await ouvrir(tester);
      expect(vue(tester).motRalliement, T('Modifier'));
      expect(
        vue(tester).ralliementEnEdition,
        isNull,
        reason: 'on n y touche pas tant qu on n a pas appuyé',
      );
    });

    testWidgets('appuyer ouvre le choix, et le plateau le referme', (
      tester,
    ) async {
      await ouvrir(tester);
      vue(tester).onTapCell(const Cell(3, 8));
      await tester.pumpAndSettle();
      expect(vue(tester).ralliementEnEdition, Camp.blanc);

      vue(tester).onTapCell(const Cell(0, 0));
      await tester.pumpAndSettle();
      expect(vue(tester).ralliementEnEdition, isNull);
    });

    testWidgets('ensuite, chaque appui met ou retire une case', (tester) async {
      await ouvrir(tester);
      vue(tester).onTapCell(const Cell(3, 8));
      await tester.pumpAndSettle();

      // On retire les trois d origine, on en met une en do.
      for (final c in [2, 3, 4, 0]) {
        vue(tester).onTapCell(Cell(c, 8));
        await tester.pumpAndSettle();
      }
      expect(vue(tester).board.rall.colonnes(Camp.blanc), [0]);
      expect(
        vue(tester).board.rall.colonnes(Camp.noir),
        [2, 3, 4],
        reason: 'on n a touché qu à la zone des Blancs',
      );
    });

    testWidgets('une zone vidée se ROUVRE : sinon elle serait perdue', (
      tester,
    ) async {
      // Sans case de ralliement, il n y a plus rien à toucher sur la rangée :
      // il faut qu elle réponde quand même, sans quoi on ne pourrait jamais
      // revenir sur une zone qu on a vidée.
      await ouvrir(tester);
      vue(tester).onTapCell(const Cell(3, 8));
      await tester.pumpAndSettle();
      for (final c in [2, 3, 4]) {
        vue(tester).onTapCell(Cell(c, 8));
        await tester.pumpAndSettle();
      }
      expect(vue(tester).board.rall.estFerme(Camp.blanc), isTrue);

      // On referme, puis on rouvre en touchant une case qui ne rallie pas.
      vue(tester).onTapCell(const Cell(0, 0));
      await tester.pumpAndSettle();
      expect(vue(tester).ralliementEnEdition, isNull);

      vue(tester).onTapCell(const Cell(5, 8));
      await tester.pumpAndSettle();
      expect(
        vue(tester).ralliementEnEdition,
        Camp.blanc,
        reason:
            'la rangée vide ne répond plus : la zone est perdue pour de bon',
      );
      vue(tester).onTapCell(const Cell(5, 8));
      await tester.pumpAndSettle();
      expect(vue(tester).board.rall.colonnes(Camp.blanc), [5]);
    });

    testWidgets('et la rangée entière répond au doigt dans le composeur', (
      tester,
    ) async {
      await ouvrir(tester);
      final g = BoardGeometry(
        size: const Size(350, 500),
        flipped: true,
        ralliementsTouchables: true,
      );
      for (var c = 0; c < kCols; c++) {
        expect(g.pixelToCell(g.cellCenter(c, 8)), Cell(c, 8));
        expect(g.pixelToCell(g.cellCenter(c, -1)), Cell(c, -1));
      }
    });

    testWidgets('on peut tout retirer : zéro case est un choix', (
      tester,
    ) async {
      await ouvrir(tester);
      vue(tester).onTapCell(const Cell(3, -1));
      await tester.pumpAndSettle();
      for (final c in [2, 3, 4]) {
        vue(tester).onTapCell(Cell(c, -1));
        await tester.pumpAndSettle();
      }
      expect(vue(tester).board.rall.estFerme(Camp.noir), isTrue);
    });
  });

  group('La géométrie', () {
    const taille = Size(350, 500);

    test('une zone trouée se peint en plusieurs morceaux', () {
      final g = BoardGeometry(
        size: taille,
        flipped: true,
        rall: const Ralliements(blanc: 1 | (1 << 2) | (1 << 4), noir: 1 << 3),
      );
      expect(
        g.rallyRects(8),
        hasLength(3),
        reason: 'do, mi et sol : trois morceaux séparés, pas un rectangle',
      );
      expect(g.rallyRects(-1), hasLength(1));
    });

    test('un doigt ne touche une case hors plateau que si elle rallie', () {
      final g = BoardGeometry(
        size: taille,
        flipped: true,
        rall: const Ralliements(blanc: 1 << 3, noir: 1 << 3),
      );
      final dansLaZone = g.cellCenter(3, 8);
      final aCote = g.cellCenter(0, 8);
      expect(g.pixelToCell(dansLaZone), const Cell(3, 8));
      expect(g.pixelToCell(aCote), isNull);
    });

    test('sauf quand on choisit la zone : la rangée s ouvre en entier', () {
      final g = BoardGeometry(
        size: taille,
        flipped: true,
        rall: const Ralliements(blanc: 1 << 3, noir: 1 << 3),
        rangeeOuverte: Camp.blanc,
      );
      expect(g.pixelToCell(g.cellCenter(0, 8)), const Cell(0, 8));
      expect(
        g.pixelToCell(g.cellCenter(0, -1)),
        isNull,
        reason: 'seule la rangée ouverte s ouvre',
      );
    });
  });
}
