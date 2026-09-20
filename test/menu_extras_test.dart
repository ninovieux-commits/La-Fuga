/// Les entrées ajoutées au menu : analyse, Random Fuga, lecteur nmc.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/move_controller.dart';
import 'package:lafuga/game/nmc.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/main.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/game_screen.dart';
import 'package:lafuga/ui/screens/replay_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.load();
    await Translations.load('fr');
  });

  Future<void> bootApp(WidgetTester tester) async {
    await tester.pumpWidget(const FugaApp());
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Les entrées secondaires vivent dans le volet « Plus », comme en Kivy.
  Future<void> openPlus(WidgetTester tester, String entry) async {
    await tapVisible(tester, find.text('Plus'));
    await tapVisible(tester, find.text(entry));
  }

  /// Le lecteur nmc est au bout du menu de l'historique, comme en Kivy.
  Future<void> openReaderScreen(WidgetTester tester) async {
    await openPlus(tester, 'Historique');
    await tapVisible(tester, find.text('Lecteur nmc'));
  }

  group('Analyse', () {
    test('la répétition ne clôt pas une analyse', () {
      // En partie, revenir quatre fois sur la même position fait nulle ;
      // en analyse, on explore, donc rien ne se ferme.
      final game = MoveController(countRepetitions: false);
      final key = game.board.positionKey(Camp.blanc);

      expect(game.positionCounts[key], isNull);
      expect(game.gameOver, isFalse);
    });

    testWidgets('l analyse s ouvre sans chrono', (tester) async {
      await bootApp(tester);
      await openPlus(tester, 'Analyse');

      expect(find.byType(GameScreen), findsOneWidget);
      expect(
        find.text('∞'),
        findsNWidgets(2),
        reason: 'pas de chrono en analyse',
      );
      // Kivy offre, en analyse, de reprendre la position contre Deep Grey.
      expect(find.text('Deep Grey'), findsOneWidget);
    });
  });

  group('Random Fuga en local', () {
    testWidgets('la position de départ change quand on l active', (
      tester,
    ) async {
      await bootApp(tester);
      // L'interrupteur Random est sur le menu, comme en Kivy.
      await tapVisible(tester, find.text('Random'));
      await tapVisible(tester, find.text('Jouer en local'));

      final screen = tester.widget<GameScreen>(find.byType(GameScreen));
      expect(screen.randomCode, isNotNull);
      expect(screen.initialBoard, isNotNull);
      expect(
        screen.initialBoard!.key,
        isNot(Board.initial().key),
        reason: 'une position tirée au sort',
      );
    });

    testWidgets('sans l interrupteur, c est la position standard', (
      tester,
    ) async {
      await bootApp(tester);
      await tapVisible(tester, find.text('Jouer en local'));

      final screen = tester.widget<GameScreen>(find.byType(GameScreen));
      expect(screen.randomCode, isNull);
      expect(screen.initialBoard, isNull);
    });
  });

  group('Lecteur nmc', () {
    testWidgets('un contenu collé s ouvre en lecture', (tester) async {
      await bootApp(tester);
      await openReaderScreen(tester);

      const meta = NmcMeta(
        date: '2026-09-20',
        player1: 'Nino',
        player2: 'Ana',
        blanc: 'Nino',
        objectif: 'partie',
        cadence: '15',
        result: '1-0',
        method: 'fugue',
        points: '2',
      );
      await tester.enterText(
        find.byType(TextField).last,
        buildNmc(meta, const ['Do2-Do3']),
      );
      await tapVisible(tester, find.text('Lire'));

      expect(find.byType(ReplayScreen), findsOneWidget);
      expect(find.textContaining('Nino'), findsWidgets);
    });

    testWidgets('un contenu illisible est refusé', (tester) async {
      await bootApp(tester);
      await openReaderScreen(tester);

      await tester.enterText(find.byType(TextField).last, 'n importe quoi');
      await tapVisible(tester, find.text('Lire'));

      expect(find.byType(ReplayScreen), findsNothing);
      expect(find.textContaining('invalide'), findsOneWidget);
    });
  });

  group('Reprendre depuis le lecteur', () {
    /// Ouvre le lecteur sur une partie de deux coups.
    Future<void> openReader(WidgetTester tester) async {
      await bootApp(tester);
      await openReaderScreen(tester);

      const meta = NmcMeta(
        date: '2026-09-20',
        player1: 'Nino',
        player2: 'Ana',
        blanc: 'Nino',
        objectif: 'partie',
        cadence: '15',
        result: '1-0',
        method: 'fugue',
        points: '2',
      );
      await tester.enterText(
        find.byType(TextField).last,
        buildNmc(meta, const ['Do2-Do3', 'Do7-Do6']),
      );
      await tapVisible(tester, find.text('Lire'));
    }

    testWidgets('on part en analyse depuis la position affichée', (
      tester,
    ) async {
      // Le lecteur s'ouvre sur le premier coup, comme en Kivy : les Noirs
      // ont donc le trait.
      await openReader(tester);
      await tapVisible(tester, find.text('Analyser'));

      final screen = tester.widget<GameScreen>(find.byType(GameScreen));
      expect(screen.analysis, isTrue);
      expect(screen.aiCamp, isNull);
      expect(
        screen.initialTurn,
        Camp.noir,
        reason: 'après le premier coup blanc, les Noirs ont le trait',
      );
      expect(screen.initialBoard, isNotNull);
    });

    testWidgets('ou on reprend contre Deep Grey, qui prend l autre camp', (
      tester,
    ) async {
      await openReader(tester);

      await tapVisible(tester, find.text('Deep Grey'));
      // Kivy demande SON camp au joueur ; le trait, lui, ne bouge pas.
      // Pas de `pumpAndSettle` ici : c'est aux Noirs de jouer, donc Deep Grey
      // se met à réfléchir et son indicateur tourne sans fin.
      await tester.tap(find.text('Blancs'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final screen = tester.widget<GameScreen>(find.byType(GameScreen));
      expect(screen.analysis, isFalse);
      expect(
        screen.aiCamp,
        Camp.noir,
        reason: "j'ai choisi les Blancs, l'IA prend les Noirs",
      );
      expect(
        screen.initialTurn,
        Camp.noir,
        reason: 'le trait ne bouge pas : après le coup blanc, aux Noirs',
      );
    });
  });

  testWidgets('le menu ne promet plus rien pour plus tard', (tester) async {
    await bootApp(tester);
    expect(find.textContaining('Bientôt'), findsNothing);

    await tapVisible(tester, find.text('Plus'));
    expect(find.text('Soutenir les devs'), findsOneWidget);
  });
}
