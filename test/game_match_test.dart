/// Match à l'écran : le score s'affiche, la partie suivante s'enchaîne, et
/// les couleurs changent de main.
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
    tmp = Directory.systemTemp.createTempSync('lafuga_match');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// Ouvre une partie dont le chrono expire en deux secondes : c'est la façon
  /// la plus courte de terminer une partie sans la jouer.
  Future<void> openQuickGame(
    WidgetTester tester, {
    required String objectif,
    Camp? aiCamp,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          cadence: const Cadence(1, '1s'),
          aiCamp: aiCamp,
          objectif: objectif,
          archive: GameArchive(local: LocalGamesStore(directory: tmp)),
          memory: AiMemory(directory: tmp),
        ),
      ),
    );
  }

  Future<void> runOutTheClock(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('en partie unique, on ne propose pas de suite', (tester) async {
    await openQuickGame(tester, objectif: 'partie');
    await runOutTheClock(tester);

    expect(find.textContaining('Temps écoulé'), findsOneWidget);
    expect(find.text('Partie suivante'), findsNothing);
    expect(find.text('Nouvelle partie'), findsOneWidget);
  });

  testWidgets('en match, le score s affiche et la suite est proposée', (
    tester,
  ) async {
    await openQuickGame(tester, objectif: '5');
    await runOutTheClock(tester);

    // Le temps écoulé vaut 2 points, pour Joueur 2 (les Blancs ont perdu).
    expect(find.textContaining('Joueur 1 : 0'), findsOneWidget);
    expect(find.textContaining('Joueur 2 : 2'), findsOneWidget);
    expect(find.text('Partie suivante'), findsOneWidget);
  });

  testWidgets('la partie suivante repart, chrono neuf', (tester) async {
    await openQuickGame(tester, objectif: '5');
    await runOutTheClock(tester);

    await tester.tap(find.text('Partie suivante'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Temps écoulé'), findsNothing);
    expect(find.text('Partie suivante'), findsNothing);
    expect(find.text('Nouvelle partie'), findsOneWidget);
  });

  testWidgets('contre Deep Grey, les couleurs changent de main', (
    tester,
  ) async {
    await openQuickGame(tester, objectif: '5', aiCamp: Camp.noir);
    await runOutTheClock(tester);

    await tester.tap(find.text('Partie suivante'));
    // Pas de pumpAndSettle : Deep Grey réfléchit, et son indicateur tourne
    // tant qu'il n'a pas répondu.
    await tester.pump();

    // Deep Grey a pris les Blancs : c'est donc à LUI de jouer d'entrée.
    expect(
      find.byType(CircularProgressIndicator),
      findsOneWidget,
      reason: 'Deep Grey joue le premier coup de la partie suivante',
    );
    expect(find.text('Deep Grey'), findsOneWidget);
  });
}
