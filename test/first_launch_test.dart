/// Tout premier lancement : la langue, puis le tuto — la séquence de
/// démarrage de Kivy (`show_first_launch_language`, puis l'écran du tuto).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/main.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/tuto_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> boot(WidgetTester tester, Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    await Settings.load();
    await Translations.load('fr');
    await tester.pumpWidget(const FugaApp());
    await tester.pumpAndSettle();
  }

  testWidgets('au premier lancement, on choisit la langue puis le tuto part', (
    tester,
  ) async {
    await boot(tester, const {});

    // Titre bilingue : on ne sait pas encore quelle langue parle le joueur.
    expect(find.text('Langue / Language'), findsOneWidget);
    expect(find.text('Français'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);

    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();

    expect(find.byType(TutoScreen), findsOneWidget, reason: 'le tuto enchaîne');
    expect(Settings.instance.languageChosen, isTrue);
    expect(Settings.instance.tutorialSeen, isTrue);
  });

  testWidgets('aux lancements suivants, on arrive droit au menu', (
    tester,
  ) async {
    await boot(tester, const {'lang_chosen': true, 'tuto_seen': true});

    expect(find.text('Langue / Language'), findsNothing);
    expect(find.byType(TutoScreen), findsNothing);
    expect(find.text('Jouer contre Deep Grey'), findsOneWidget);
  });

  testWidgets('la langue choisie est celle de tous les écrans', (tester) async {
    await boot(tester, const {});

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(Settings.instance.language, 'en');
  });
}
