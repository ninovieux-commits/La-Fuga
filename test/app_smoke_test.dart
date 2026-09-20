/// Test de fumée : l'application démarre, le menu s'affiche comme celui de
/// Kivy, et on atteint le plateau. C'est le filet minimal contre un écran
/// noir au lancement.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/main.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/game_screen.dart';
import 'package:lafuga/ui/screens/login_screen.dart';
import 'package:lafuga/ui/screens/menu_screen.dart';
import 'package:lafuga/ui/screens/settings_screen.dart';
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

  /// Amène un élément à l'écran avant de le toucher.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('le menu a les entrées du menu de Kivy', (tester) async {
    await bootApp(tester);

    expect(find.byType(MenuScreen), findsOneWidget);
    for (final label in [
      'Jouer en local',
      'Jouer en ligne',
      'Messages',
      'Jouer contre Deep Grey',
      'Plus',
      'Parties par correspondance',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Random'), findsOneWidget, reason: 'interrupteur Random');
    expect(find.text('Compte'), findsOneWidget, reason: 'déconnecté');
  });

  testWidgets('les trois cadences de Kivy sont proposées', (tester) async {
    await bootApp(tester);

    expect(find.text('5 min'), findsOneWidget);
    expect(find.text('15 min'), findsOneWidget);
    expect(find.text('30 min'), findsOneWidget);
  });

  testWidgets('« Plus » ouvre le reste, comme en Kivy', (tester) async {
    await bootApp(tester);
    await tapVisible(tester, find.text('Plus'));

    for (final label in [
      'Tuto',
      'Historique',
      'Analyse',
      'Réglages',
      'Soutenir les devs',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets("le logo raconte l'histoire du jeu", (tester) async {
    await bootApp(tester);

    // Le logo du thème, sous le titre : c'est lui qui ouvre l'histoire.
    await tapVisible(
      tester,
      find.ancestor(
        of: find.byType(Image).at(1),
        matching: find.byType(GestureDetector),
      ),
    );

    expect(find.textContaining('Deux frères'), findsOneWidget);
  });

  testWidgets('les réglages s ouvrent sur les sélecteurs de Kivy', (
    tester,
  ) async {
    await bootApp(tester);
    await tapVisible(tester, find.text('Plus'));
    await tapVisible(tester, find.text('Réglages'));

    expect(find.byType(SettingsScreen), findsOneWidget);
    // Le thème et la langue se font défiler, ils ne se listent pas.
    expect(find.text('Français'), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('Piano'), findsOneWidget);
    expect(find.text('Appliquer ce thème'), findsOneWidget);
    expect(find.text('Fermer'), findsOneWidget);
  });

  testWidgets('on lance une partie contre Deep Grey et le plateau apparaît', (
    tester,
  ) async {
    await bootApp(tester);

    await tapVisible(tester, find.text('Jouer contre Deep Grey'));
    expect(find.text('Choisissez votre couleur'), findsOneWidget);

    await tapVisible(tester, find.text('Jouer avec les Blancs'));

    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('Deep Grey'), findsOneWidget, reason: 'bandeau adverse');
    expect(
      find.text('∞'),
      findsNWidgets(2),
      reason: 'une partie contre Deep Grey est sans chrono',
    );
  });

  testWidgets('une partie locale part tout de suite, à la cadence du menu', (
    tester,
  ) async {
    await bootApp(tester);

    await tapVisible(tester, find.text('Jouer en local'));

    expect(find.byType(GameScreen), findsOneWidget);
    final screen = tester.widget<GameScreen>(find.byType(GameScreen));
    expect(screen.aiCamp, isNull);
    expect(screen.cadence.wire, '15', reason: 'cadence par défaut du menu');
    // Les panneaux portent les noms des joueurs, comme en Kivy.
    expect(find.text('Joueur 1'), findsOneWidget);
    expect(find.text('Joueur 2'), findsOneWidget);
  });

  testWidgets('le jeu en ligne demande de se connecter', (tester) async {
    await bootApp(tester);

    await tapVisible(tester, find.text('Jouer en ligne'));

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets("l'écran de connexion bascule vers l'inscription", (
    tester,
  ) async {
    await bootApp(tester);
    await tapVisible(tester, find.text('Jouer en ligne'));

    expect(
      find.text('Email (optionnel)'),
      findsNothing,
      reason: 'le champ e-mail ne sert qu à l inscription',
    );

    await tapVisible(tester, find.text('Inscription').last);
    expect(find.text('Email (optionnel)'), findsOneWidget);
  });

  testWidgets('les messages demandent aussi un compte', (tester) async {
    await bootApp(tester);

    await tapVisible(tester, find.text('Messages'));

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
