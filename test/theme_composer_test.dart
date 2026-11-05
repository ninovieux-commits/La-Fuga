/// Composeur de thèmes : cinq axes indépendants, et ce qu'on applique est
/// bien ce qu'on a choisi.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/theme_composer_screen.dart';
import 'package:lafuga/ui/widgets/theme_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ThemeComposerScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('chaque rangée s ouvre sur le thème déjà choisi', (tester) async {
    // Les rangées partaient toujours de la gauche : un thème choisi loin
    // dans la liste — Deep Grey est le dix-septième — restait hors de
    // l'écran, et le composeur s'ouvrait sans qu'on voie ce qu'on avait.
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    setScaleSize(const Size(393, 851));
    addTearDown(resetScale);

    await Settings.instance.setTheme(
      const ThemeAxes(
        general: 'deepgrey',
        pieces: 'dragon',
        logo: 'deepgrey',
        menu: 'dragon',
        board: 'deepgrey',
      ).toString(),
    );
    await open(tester);

    // La rangée « Général » est la première, donc visible sans défiler :
    // sa vignette « Deep Grey » doit déjà être à l'écran.
    final vignette = find.text(kThemeLabels['deepgrey']!).first;
    expect(vignette, findsOneWidget);
    final boite = tester.getRect(vignette);
    expect(
      boite.left,
      greaterThanOrEqualTo(0),
      reason: 'la vignette choisie déborde à gauche',
    );
    expect(
      boite.right,
      lessThanOrEqualTo(393),
      reason: 'la vignette choisie déborde à droite de l écran',
    );
  });

  testWidgets('l aperçu suit ce qu on compose, avant d appliquer', (
    tester,
  ) async {
    // Nino : « le plateau ne se met pas bien à jour. » Le composeur ne
    // montrait rien du résultat : il fallait appliquer, sortir, et aller
    // ouvrir une partie pour voir ce qu'on avait fait.
    setScaleSize(const Size(393, 851));
    addTearDown(resetScale);
    await open(tester);

    ThemePreview apercu() =>
        tester.widget<ThemePreview>(find.byType(ThemePreview));
    expect(apercu().themeDuPlateau, 'original');

    // On choisit un plateau SANS appliquer : l'aperçu doit déjà le porter.
    await tester.scrollUntilVisible(
      find.text('Plateau'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    final rangee = find.ancestor(
      of: find.text('Plateau'),
      matching: find.byType(Column),
    );
    expect(rangee, findsWidgets);
    await tester.tap(
      find.descendant(
        of: rangee.first,
        matching: find.text(kThemeLabels['foret']!),
      ),
    );
    await tester.pumpAndSettle();

    expect(apercu().themeDuPlateau, 'foret');
    expect(
      Settings.instance.themeAxes.board,
      'original',
      reason: 'rien n est enregistré tant qu on n a pas appliqué',
    );
  });

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
