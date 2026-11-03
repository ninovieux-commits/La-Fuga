/// LA PASTILLE DES MESSAGES NON LUS.
///
/// Nino, trois captures en main : « celle de la photo 1 est mangée et celle
/// de la photo 2 est à l'ancienne. Arrange ça. La pastille doit être en
/// couleur 1 avec le contour noir. Elle doit apparaître et disparaître à
/// intervalles de 1,5 seconde. »
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/unread_dot.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// L'opacité que la pastille vise en ce moment.
double opacite(WidgetTester tester) =>
    tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

/// Le rond peint.
BoxDecoration rond(WidgetTester tester) =>
    tester
            .widget<Container>(
              find.descendant(
                of: find.byType(PastilleNonLue),
                matching: find.byType(Container),
              ),
            )
            .decoration!
        as BoxDecoration;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
      'theme': 'foret',
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
  });
  tearDown(resetScale);

  /// Une touche carrée de [cote] points, marquée d'une pastille.
  Future<int> poser(WidgetTester tester, {double cote = 36}) async {
    var appuis = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: cote,
              height: cote,
              child: UnreadDot(
                show: true,
                child: Material(
                  child: InkWell(
                    onTap: () => appuis++,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return appuis;
  }

  group('Son allure', () {
    test('elle bat toutes les 1,5 seconde', () {
      expect(kBattementPastille, const Duration(milliseconds: 1500));
    });

    testWidgets('couleur 1 du thème, et le trait noir des touches', (
      tester,
    ) async {
      await poser(tester);
      final peinture = rond(tester);

      expect(peinture.color, paletteOf('foret').clair);
      expect(peinture.border?.top.color, Colors.black);
      expect(peinture.shape, BoxShape.circle);
    });

    testWidgets('elle s allume, s éteint, et se rallume', (tester) async {
      await poser(tester);
      expect(opacite(tester), 1);

      await tester.pump(kBattementPastille);
      await tester.pump();
      expect(opacite(tester), 0, reason: 'elle disparaît au bout d une 1,5 s');

      await tester.pump(kBattementPastille);
      await tester.pump();
      expect(opacite(tester), 1, reason: 'et revient la 1,5 s suivante');
    });
  });

  group('Sa place', () {
    // Nino : « celle de la photo 1 est mangée. » Elle débordait de la touche,
    // et le bandeau d'une partie rogne ce qui dépasse.
    testWidgets('elle tient DANS la touche', (tester) async {
      await poser(tester);
      final touche = tester.getRect(find.byType(UnreadDot));
      final pastille = tester.getRect(find.byType(PastilleNonLue));

      expect(touche.contains(pastille.topLeft), isTrue);
      expect(
        touche.contains(pastille.bottomRight - const Offset(0.1, 0.1)),
        isTrue,
      );
    });

    // Elle faisait vingt points quelle que soit la touche : sur une touche
    // de trente-six, elle en couvrait le centre.
    testWidgets('et laisse le centre de la touche libre', (tester) async {
      await poser(tester);
      final touche = tester.getRect(find.byType(UnreadDot));
      final pastille = tester.getRect(find.byType(PastilleNonLue));

      expect(pastille.contains(touche.center), isFalse);
      expect(pastille.width, lessThan(touche.width / 2));
    });

    testWidgets('sur une grande touche, elle ne grossit pas sans fin', (
      tester,
    ) async {
      await poser(tester, cote: 300);
      expect(
        tester.getRect(find.byType(PastilleNonLue)).width,
        moreOrLessEquals(S(22), epsilon: 0.01),
      );
    });
  });

  group('Son doigt', () {
    // Mesuré : l'appui tombait sur la pastille, et le chat ne s'ouvrait plus.
    testWidgets('elle ne prend pas l appui destiné à la touche', (
      tester,
    ) async {
      var appuis = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 36,
                height: 36,
                child: UnreadDot(
                  show: true,
                  child: Material(
                    child: InkWell(
                      onTap: () => appuis++,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // En plein sur la pastille, dans le coin bas-droit.
      await tester.tapAt(tester.getRect(find.byType(PastilleNonLue)).center);
      await tester.pump();

      expect(appuis, 1, reason: 'le doigt doit traverser la pastille');
    });

    testWidgets('sans pastille, la touche est rendue telle quelle', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnreadDot(show: false, child: Text(T('Messages'))),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PastilleNonLue), findsNothing);
      expect(find.text('Messages'), findsOneWidget);
    });
  });
}
