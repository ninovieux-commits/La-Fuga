/// Test de fumée : l'application démarre, le menu s'affiche, et on atteint
/// le plateau. C'est le filet minimal contre un écran noir au lancement.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/main.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/game_screen.dart';
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

  testWidgets('le menu affiche ses entrées principales', (tester) async {
    await bootApp(tester);

    expect(find.byType(MenuScreen), findsOneWidget);
    expect(find.text('Jouer contre Deep Grey'), findsOneWidget);
    expect(find.text('Jouer en local'), findsOneWidget);
    expect(find.text('Réglages'), findsOneWidget);
  });

  testWidgets("le logo raconte l'histoire du jeu", (tester) async {
    await bootApp(tester);

    await tapVisible(tester, find.text("L'histoire de La Fuga").last);

    expect(find.textContaining('Deux frères'), findsOneWidget);
  });

  testWidgets('les réglages s ouvrent et listent thèmes et langues', (
    tester,
  ) async {
    await bootApp(tester);

    await tapVisible(tester, find.text('Réglages'));

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Deep Grey'), findsWidgets, reason: 'un thème du jeu');
    expect(find.text('Français'), findsOneWidget);
  });

  testWidgets('on lance une partie contre Deep Grey et le plateau apparaît', (
    tester,
  ) async {
    await bootApp(tester);

    await tapVisible(tester, find.text('Jouer contre Deep Grey'));
    expect(find.text('Choisissez votre couleur'), findsOneWidget);

    await tapVisible(tester, find.text('Jouer'));

    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('Deep Grey'), findsOneWidget, reason: 'bandeau adverse');
    expect(find.text('∞'), findsNWidgets(2), reason: 'deux chronos illimités');
  });

  testWidgets('une partie locale oppose deux joueurs humains', (tester) async {
    await bootApp(tester);

    await tapVisible(tester, find.text('Jouer en local'));
    expect(
      find.text('Choisissez votre couleur'),
      findsNothing,
      reason: 'sans objet quand les deux joueurs sont humains',
    );

    await tapVisible(tester, find.text('Jouer'));

    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('Deep Grey'), findsNothing);
    expect(find.text('Blanc'), findsOneWidget);
    expect(find.text('Noir'), findsOneWidget);
  });
}
