/// Composeur de thèmes : cinq axes indépendants, et ce qu'on applique est
/// bien ce qu'on a choisi.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/screens/theme_composer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.load();
    await Translations.load('fr');
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ThemeComposerScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('les cinq axes sont proposés', (tester) async {
    await open(tester);

    for (final (_, label) in kThemeAxisLabels) {
      // Les derniers axes sont plus bas : on les amène à l'écran.
      await tester.scrollUntilVisible(
        find.text(label),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(label), findsOneWidget, reason: 'axe « $label »');
    }
    expect(find.text('Appliquer'), findsOneWidget);
  });

  testWidgets('choisir un thème sur un axe ne touche pas les autres', (
    tester,
  ) async {
    await open(tester);

    // Le premier axe affiché est « Général » : on y prend le deuxième thème
    // de la liste, visible sans défiler.
    final second = kThemes.keys.elementAt(1);
    await tester.tap(find.text(kThemeLabels[second]!).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();

    final axes = Settings.instance.themeAxes;
    expect(axes.general, second);
    expect(axes.pieces, 'original', reason: 'les autres axes ne bougent pas');
    expect(axes.board, 'original');
  });

  testWidgets('la composition est retenue telle quelle', (tester) async {
    await Settings.instance.setTheme(
      const ThemeAxes(
        general: 'dragon',
        pieces: 'medieval',
        logo: 'ocean',
        menu: 'volcan',
        board: 'fleur',
      ).toString(),
    );
    await open(tester);
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();

    final axes = Settings.instance.themeAxes;
    expect(axes.general, 'dragon');
    expect(axes.pieces, 'medieval');
    expect(axes.logo, 'ocean');
    expect(axes.menu, 'volcan');
    expect(axes.board, 'fleur');
  });
}
