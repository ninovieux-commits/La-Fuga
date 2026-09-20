/// Ce que l'écran de partie en ligne propose — la colonne « en ligne » de la
/// table de `_update_action_buttons` / `_update_side_buttons` (main.py).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/clock.dart';
import 'package:lafuga/game/online_game.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:lafuga/ui/screens/online_game_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_game_test.dart' show FakeSocket, makeGame;

/// Prefs d'une appli déjà lancée une fois : ni choix de langue, ni tuto —
/// ils n'apparaissent qu'au tout premier démarrage.
const Map<String, Object> _launched = {'lang_chosen': true, 'tuto_seen': true};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(_launched);
    await Settings.load();
    await Translations.load('fr');
  });

  Future<OnlineGame> open(
    WidgetTester tester, {
    FakeSocket? socket,
    Camp myCamp = Camp.blanc,
  }) async {
    final game = makeGame(
      socket: socket ?? FakeSocket(),
      myCamp: myCamp,
      cadence: Cadence.quinze,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OnlineGameScreen(game: game, myPseudo: 'Nino'),
      ),
    );
    await tester.pump();
    return game;
  }

  testWidgets('le bandeau porte le chat, la pause et rien d autre', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('< >'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Analyser'), findsNothing);
    expect(find.text('Deep Grey'), findsNothing);
    expect(find.text('Rapide'), findsNothing);
    expect(
      find.text('Retour au menu'),
      findsNothing,
      reason: 'la partie est en cours',
    );
  });

  testWidgets('les gestes sont de mon côté seulement', (tester) async {
    await open(tester);

    expect(find.byTooltip('Proposer nulle'), findsOneWidget);
    expect(find.byTooltip('Abandonner'), findsOneWidget);
  });

  testWidgets('le mélo suit chaque nom, comme en Kivy', (tester) async {
    await open(tester);

    expect(find.text('Nino  (1500)'), findsOneWidget);
    expect(find.text('Adversaire  (1500)'), findsOneWidget);
  });

  testWidgets('le chat ouvre LA conversation, pas une boîte à part', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();

    // La même boîte que depuis le menu : l'écran de conversation, au nom de
    // l'adversaire.
    expect(find.byType(ConversationScreen), findsOneWidget);
    expect(find.text('Adversaire'), findsWidgets);
  });

  testWidgets('la pause en ligne ne propose pas de quitter', (tester) async {
    await open(tester);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();

    expect(find.text('Reprendre'), findsOneWidget);
    expect(find.text('Réglages'), findsOneWidget);
    expect(
      find.text('Annuler le match'),
      findsNothing,
      reason: 'en ligne, on abandonne par le X, pas par la pause',
    );
  });
}
