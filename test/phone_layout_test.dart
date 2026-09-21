/// Les écrans tiennent sur un vrai téléphone, en portrait.
///
/// La fenêtre de test par défaut fait 800 × 600 — plus large que haute, ce
/// qu'aucun téléphone n'est. Or toutes les tailles sont maintenant
/// proportionnelles : un débordement ne se verrait que dans la bonne forme
/// d'écran. Ce test rejoue les écrans principaux dans celle d'un téléphone,
/// et tout débordement fait échouer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/main.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/game_screen.dart';
import 'package:lafuga/ui/screens/menu_screen.dart';
import 'package:lafuga/ui/widgets/pause_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Map<String, Object> _launched = {'lang_chosen': true, 'tuto_seen': true};

/// Un écran de téléphone courant, en pixels logiques.
const Size _phone = Size(393, 851);

/// Un petit écran, pour le cas serré.
const Size _small = Size(320, 640);

/// Une tablette, pour le cas large.
const Size _tablet = Size(834, 1112);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(_launched);
    await Settings.load();
    await Translations.load('fr');
    resetScale();
  });

  tearDown(resetScale);

  Future<void> useScreen(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  for (final (name, size) in [
    ('un téléphone', _phone),
    ('un petit écran', _small),
    ('une tablette', _tablet),
  ]) {
    testWidgets('le menu tient sur $name', (tester) async {
      await useScreen(tester, size);
      await tester.pumpWidget(const FugaApp());
      await tester.pumpAndSettle();

      expect(find.byType(MenuScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('l écran de jeu tient sur $name', (tester) async {
      await useScreen(tester, size);
      await tester.pumpWidget(
        const MaterialApp(home: GameScreen(aiCamp: null)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GameScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la pause tient sur $name', (tester) async {
      await useScreen(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          home: FugaScale(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showPauseDialog(context, palette: paletteOf(kDefaultTheme)),
                child: const Text('pause'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('pause'));
      await tester.pumpAndSettle();

      expect(find.text('Reprendre'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
