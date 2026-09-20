/// Ce que l'écran de jeu propose, mode par mode.
///
/// Kivy n'a qu'un écran de jeu ; ce sont `_update_action_buttons` et
/// `_update_side_buttons` qui décident, selon le mode, quelles touches
/// apparaissent. Ce test fige la table entière — c'est là que se cachaient
/// les options « présentes ici, absentes là ».
///
/// | touche        | local | vs IA | analyse |
/// |---------------|-------|-------|---------|
/// | `< >`         |   ✔   |   ✔   |    ✔    |
/// | pause         | `\| \|` | `\| \|` |  `<<`   |
/// | Retour menu   | à la fin | à la fin |  ✗   |
/// | Rapide/Profond|   ✗   |   ✔   |    ✗    |
/// | Deep Grey     |   ✗   |   ✗   |    ✔    |
/// | Analyser      |   ✗   |   ✗   |    ✗    |
/// | Chat          |   ✗   |   ✗   |    ✗    |
/// | ↶ ½ X         | 2 côtés | côté humain, sans ½ | aucun |
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/clock.dart';
import 'package:lafuga/game/game_archive.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/ai_memory.dart';
import 'package:lafuga/state/local_games.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/game_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.load();
    await Translations.load('fr');
    tmp = Directory.systemTemp.createTempSync('lafuga_modes');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> open(
    WidgetTester tester, {
    Camp? aiCamp,
    bool analysis = false,
    bool analysisFromCorr = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          cadence: Cadence.zen,
          aiCamp: aiCamp,
          analysis: analysis,
          analysisFromCorr: analysisFromCorr,
          archive: GameArchive(local: LocalGamesStore(directory: tmp)),
          memory: AiMemory(directory: tmp),
        ),
      ),
    );
    await tester.pump();
  }

  group('Partie locale', () {
    testWidgets('bandeau : retourner et pause, rien de plus', (tester) async {
      await open(tester);

      expect(find.text('< >'), findsOneWidget);
      expect(find.text('| |'), findsOneWidget);
      expect(find.text('<<'), findsNothing);
      expect(find.text('Retour au menu'), findsNothing);
      expect(find.text('Rapide'), findsNothing);
      expect(find.text('Profond'), findsNothing);
      expect(find.text('Deep Grey'), findsNothing);
      expect(find.text('Analyser'), findsNothing);
      expect(find.text('Chat'), findsNothing);
    });

    testWidgets('les deux joueurs ont ↶ ½ X', (tester) async {
      await open(tester);

      expect(find.byTooltip('Proposer nulle'), findsNWidgets(2));
      expect(find.byTooltip('Abandonner'), findsNWidgets(2));
    });
  });

  group('Contre Deep Grey', () {
    testWidgets('le mode de réflexion se change, et lui seul', (tester) async {
      await open(tester, aiCamp: Camp.noir);

      expect(find.text('Rapide'), findsOneWidget);
      expect(find.text('Analyser'), findsNothing);
      expect(find.text('Chat'), findsNothing);
      expect(
        find.text('Deep Grey'),
        findsOneWidget,
        reason: 'le nom du joueur',
      );

      await tester.tap(find.text('Rapide'));
      await tester.pump();
      expect(find.text('Profond'), findsOneWidget);
    });

    testWidgets('pas de nulle, et rien du côté de l IA', (tester) async {
      await open(tester, aiCamp: Camp.noir);

      expect(
        find.byTooltip('Proposer nulle'),
        findsNothing,
        reason: 'on ne négocie pas de nulle avec Deep Grey',
      );
      expect(
        find.byTooltip('Abandonner'),
        findsOneWidget,
        reason: 'seul le joueur humain abandonne',
      );
    });
  });

  group('Analyse', () {
    testWidgets('la pause devient un retour, Deep Grey apparaît', (
      tester,
    ) async {
      await open(tester, analysis: true);

      expect(find.text('<<'), findsOneWidget);
      expect(find.text('| |'), findsNothing);
      expect(find.text('Deep Grey'), findsOneWidget);
      expect(find.text('Analyser'), findsNothing, reason: 'on y est déjà');
      expect(find.text('Rapide'), findsNothing);
    });

    testWidgets('aucun geste de partie', (tester) async {
      await open(tester, analysis: true);

      expect(find.byTooltip('Proposer nulle'), findsNothing);
      expect(find.byTooltip('Abandonner'), findsNothing);
      expect(find.byTooltip('Annuler'), findsNothing);
    });

    testWidgets('venue d une correspondance, Deep Grey est interdit', (
      tester,
    ) async {
      await open(tester, analysis: true, analysisFromCorr: true);

      expect(
        find.text('Deep Grey'),
        findsNothing,
        reason: "l'IA soufflerait le coup d'une partie en cours",
      );
      expect(find.text('<<'), findsOneWidget);
    });
  });
}
