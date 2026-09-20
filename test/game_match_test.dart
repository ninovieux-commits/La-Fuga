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

    // Kivy annonce la fin dans un popup : vainqueur et retour au menu, sans
    // « partie suivante » puisqu'il n'y a qu'une partie.
    expect(find.textContaining('Temps écoulé'), findsOneWidget);
    expect(find.text('Partie suivante'), findsNothing);
    expect(find.textContaining('Victoire de'), findsOneWidget);
    expect(find.text('Retour au menu'), findsWidgets);
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

    // La partie repart : plus de popup, et le bandeau ne propose plus le
    // retour au menu (réservé à la fin).
    expect(find.textContaining('Temps écoulé'), findsNothing);
    expect(find.text('Partie suivante'), findsNothing);
    expect(find.text('Retour au menu'), findsNothing);
  });

  group('Abandon et nulle par accord', () {
    testWidgets('abandonner donne deux points à l adversaire', (tester) async {
      await openQuickGame(tester, objectif: '5');
      await tester.pump();

      await tester.tap(find.byTooltip('Abandonner').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('2 points'), findsOneWidget);
      await tester.tap(find.text('Oui, abandonner'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Abandon'), findsOneWidget);
      expect(
        find.textContaining('Joueur 2 : 2'),
        findsOneWidget,
        reason: 'les Blancs abandonnent, Joueur 2 marque',
      );
    });

    testWidgets('la nulle demande l accord des DEUX camps', (tester) async {
      await openQuickGame(tester, objectif: '5');
      await tester.pump();

      // Un seul ½ allumé ne fait rien : Kivy attend l'autre.
      await tester.tap(find.byTooltip('Proposer nulle').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Partie nulle'), findsNothing);

      await tester.tap(find.byTooltip('Proposer nulle').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('nulle'), findsWidgets);
      expect(find.textContaining('Joueur 1 : 0'), findsOneWidget);
      expect(find.textContaining('Joueur 2 : 0'), findsOneWidget);
    });

    testWidgets('on ne négocie pas de nulle avec Deep Grey', (tester) async {
      await openQuickGame(tester, objectif: 'partie', aiCamp: Camp.noir);
      await tester.pump();

      expect(
        find.byTooltip('Proposer nulle'),
        findsNothing,
        reason: 'on ne négocie pas avec Deep Grey',
      );
      expect(
        find.byTooltip('Abandonner'),
        findsOneWidget,
        reason: 'seul le joueur humain peut abandonner',
      );
    });
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
