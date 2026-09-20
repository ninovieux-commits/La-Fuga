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
      await tapVisible(tester, find.text('Analyse'));

      expect(find.byType(GameScreen), findsOneWidget);
      expect(
        find.text('∞'),
        findsNWidgets(2),
        reason: 'pas de chrono en analyse',
      );
      expect(find.text('Deep Grey'), findsNothing);
    });
  });

  group('Random Fuga en local', () {
    testWidgets('la position de départ change quand on l active', (
      tester,
    ) async {
      await bootApp(tester);
      await tapVisible(tester, find.text('Jouer en local'));
      await tapVisible(tester, find.text('Random Fuga'));
      await tapVisible(tester, find.text('Jouer'));

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
      await tapVisible(tester, find.text('Jouer'));

      final screen = tester.widget<GameScreen>(find.byType(GameScreen));
      expect(screen.randomCode, isNull);
      expect(screen.initialBoard, isNull);
    });
  });

  group('Lecteur nmc', () {
    testWidgets('un contenu collé s ouvre en lecture', (tester) async {
      await bootApp(tester);
      await tapVisible(tester, find.text('Lecteur nmc'));

      const meta = NmcMeta(
        date: '2026-09-20',
        player1: 'Nino',
        player2: 'Ana',
        blanc: 'Nino',
        objectif: 'partie',
        cadence: '5min',
        result: '1-0',
        method: 'fugue',
        points: '2',
      );
      await tester.enterText(
        find.byType(TextField),
        buildNmc(meta, const ['Do2-Do3']),
      );
      await tapVisible(tester, find.text('Lire'));

      expect(find.byType(ReplayScreen), findsOneWidget);
      expect(find.textContaining('Nino'), findsWidgets);
    });

    testWidgets('un contenu illisible est refusé', (tester) async {
      await bootApp(tester);
      await tapVisible(tester, find.text('Lecteur nmc'));

      await tester.enterText(find.byType(TextField), 'n importe quoi');
      await tapVisible(tester, find.text('Lire'));

      expect(find.byType(ReplayScreen), findsNothing);
      expect(find.textContaining('invalide'), findsOneWidget);
    });
  });

  testWidgets('le menu ne promet plus rien pour plus tard', (tester) async {
    await bootApp(tester);
    expect(find.textContaining('Bientôt'), findsNothing);
    expect(find.text('Soutenir les devs'), findsOneWidget);
  });
}
