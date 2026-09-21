/// Les tailles suivent l'écran — portage de `_scale_factor`, `S` et `SF`.
///
/// Kivy compose tout sur un écran de 720 px de large et multiplie ensuite
/// chaque taille par `largeur / 720`. Rien ne doit rester figé : sur un
/// téléphone deux fois plus large, tout doit être deux fois plus grand.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Map<String, Object> _launched = {'lang_chosen': true, 'tuto_seen': true};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(_launched);
    await Settings.load();
    await Translations.load('fr');
    resetScale();
  });

  tearDown(resetScale);

  test('la référence est l écran de 720 px de Kivy', () {
    setScaleSize(const Size(720, 1600));
    expect(scaleFactor, 1);
    expect(S(44), 44);
    expect(SF(16), 16 * kFontBoost);
    expect(SH(0.16), 1600 * 0.16);
  });

  test('deux fois plus large, deux fois plus grand', () {
    setScaleSize(const Size(360, 800));
    final small = S(44);
    setScaleSize(const Size(720, 1600));
    expect(S(44), small * 2);
  });

  test('une largeur absurde ne fait pas tout disparaître', () {
    setScaleSize(const Size(0, 0));
    expect(scaleFactor, 1);
  });

  testWidgets('un bouton grandit avec la fenêtre', (tester) async {
    Future<double> heightOn(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: FugaScale(
            // Sous `FugaScale`, comme un vrai écran : l'échelle est fixée
            // avant que le contenu ne se construise.
            child: Builder(
              builder: (context) => Center(
                child: SizedBox(
                  width: 200,
                  child: FugaButton(
                    text: 'Jouer',
                    height: S(48),
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // Le premier rendu fixe l'échelle, le second la met en œuvre.
      await tester.pump();
      return tester.getSize(find.byType(FugaButton)).height;
    }

    final narrow = await heightOn(const Size(360, 800));
    final wide = await heightOn(const Size(720, 1600));

    expect(narrow, lessThan(wide));
    expect(wide / narrow, closeTo(2, 0.01));
  });
}
