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
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/game_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prefs d'une appli déjà lancée une fois : ni choix de langue, ni tuto —
/// ils n'apparaissent qu'au tout premier démarrage.
const Map<String, Object> _launched = {'lang_chosen': true, 'tuto_seen': true};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues(_launched);
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
    // Une seconde par défaut : c'est la façon la plus courte de terminer une
    // partie sans la jouer. Les tests qui ouvrent des popups demandent plus
    // long — deux popups qui s'ouvrent et se ferment prennent du temps, et
    // le chrono expirerait au milieu, verdict par-dessus la confirmation.
    Cadence cadence = const Cadence(1, '1s'),
  }) async {
    // Un téléphone, et pas la surface d'essai par défaut : à 800 de large,
    // les polices valent le double (elles suivent la largeur) et les popups
    // en débordent. On mesurerait une mise en page qui n'existe sur aucun
    // appareil.
    setScaleSize(const Size(393, 851));
    addTearDown(resetScale);
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          cadence: cadence,
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

  /// Le drapeau, puis « Proposer nulle », puis « Oui » : les trois gestes
  /// que Nino a demandés à la place du ½.
  Future<void> proposerNulle(
    WidgetTester tester, {
    required bool dernier,
  }) async {
    final drapeau = find.byTooltip('Abandonner ou proposer la nulle ?');
    await tester.tap(dernier ? drapeau.last : drapeau.first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FugaButton, 'Proposer nulle'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FugaButton, 'Oui'));
    await tester.pumpAndSettle();
  }

  group('Abandon et nulle par accord', () {
    testWidgets('abandonner donne deux points à l adversaire', (tester) async {
      await openQuickGame(
        tester,
        objectif: '5',
        cadence: const Cadence(15, '15'),
      );
      await tester.pump();

      await tester.tap(
        find.byTooltip('Abandonner ou proposer la nulle ?').last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FugaButton, 'Abandonner'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 points'), findsOneWidget);
      await tester.tap(find.widgetWithText(FugaButton, 'Oui'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Abandon'), findsOneWidget);
      expect(
        find.textContaining('Joueur 2 : 2'),
        findsOneWidget,
        reason: 'les Blancs abandonnent, Joueur 2 marque',
      );
    });

    testWidgets('la nulle demande l accord des DEUX camps', (tester) async {
      await openQuickGame(
        tester,
        objectif: '5',
        cadence: const Cadence(15, '15'),
      );
      await tester.pump();

      // Une seule nulle proposée ne fait rien : Kivy attend l'autre.
      await proposerNulle(tester, dernier: true);
      expect(find.textContaining('Partie nulle'), findsNothing);
      await proposerNulle(tester, dernier: false);

      expect(find.textContaining('nulle'), findsWidgets);
      expect(find.textContaining('Joueur 1 : 0'), findsOneWidget);
      expect(find.textContaining('Joueur 2 : 0'), findsOneWidget);
    });

    testWidgets('on ne négocie pas de nulle avec Deep Grey', (tester) async {
      await openQuickGame(tester, objectif: 'partie', aiCamp: Camp.noir);
      await tester.pump();

      expect(
        find.byTooltip('Abandonner ou proposer la nulle ?'),
        findsOneWidget,
        reason: 'seul le joueur humain a un drapeau',
      );
      await tester.tap(find.byTooltip('Abandonner ou proposer la nulle ?'));
      await tester.pumpAndSettle();
      expect(
        find.text('Proposer nulle'),
        findsNothing,
        reason: 'on ne négocie pas avec Deep Grey',
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
