/// Fin de partie à l'écran : le verdict s'affiche et la partie est archivée.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/game/clock.dart';
import 'package:lafuga/game/game_archive.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/local_games.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/game_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late LocalGamesStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.load();
    await Translations.load('fr');
    tmp = Directory.systemTemp.createTempSync('lafuga_game');
    store = LocalGamesStore(directory: tmp);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('le temps écoulé termine et archive la partie', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          cadence: const Cadence(1, '1s'),
          aiCamp: null,
          archive: GameArchive(local: store),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('Temps écoulé'), findsOneWidget);
    expect(find.textContaining('Noir gagne'), findsOneWidget);

    // L'archivage est asynchrone : on lui laisse le temps d'écrire.
    await tester.runAsync(() async {
      for (var i = 0; i < 20 && (await store.list()).isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });

    final games = await tester.runAsync(store.list) ?? const [];
    expect(games, hasLength(1), reason: 'la partie perdue au temps est rangée');
    expect(games.single.meta.method, 'temps');
    expect(games.single.meta.result, '0-1', reason: 'Joueur 2 gagne');
    expect(games.single.meta.cadence, '1s');
  });
}
