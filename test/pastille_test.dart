/// LA PASTILLE DES MESSAGES NON LUS.
///
/// Nino, trois captures en main : « celle de la photo 1 est mangée et celle
/// de la photo 2 est à l'ancienne. Arrange ça. La pastille doit être en
/// couleur 1 avec le contour noir. » Elle a clignoté le temps d'un essai,
/// puis : « ne le fais pas clignoter finalement. »
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/unread_dot.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  group('Elle ne rétrécit pas la touche', () {
    /// Une touche qui PEUT rétrécir : son contenu est plus étroit que la
    /// place qu'on lui donne. C'est le cas de « Conversations » dans le
    /// menu, dont le mot ne remplit pas la cellule.
    Future<({Rect cellule, Rect touche, Rect pastille})> rangee(
      WidgetTester tester, {
      required bool nonLu,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 80,
              child: Row(
                children: [
                  Expanded(
                    child: UnreadDot(
                      show: nonLu,
                      // UNE COLONNE, comme les grosses touches du menu :
                      // c'est elle qui se replie sur la largeur de son mot
                      // dès qu'on lui lâche la bride. Un `Center`, lui,
                      // remplit quand même, et ne montrerait rien.
                      child: const Material(
                        key: Key('touche'),
                        color: Color(0xFF808080),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [Text('Conv')],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return (
        cellule: tester.getRect(find.byType(Row)),
        touche: tester.getRect(find.byKey(const Key('touche'))),
        pastille: nonLu
            ? tester.getRect(find.byType(PastilleNonLue))
            : Rect.zero,
      );
    }

    testWidgets('la touche garde sa largeur, et la pastille est dedans', (
      tester,
    ) async {
      // Nino : « gros souci avec le bouton conversations lorsqu'il y a un
      // nouveau message. » La pile de la pastille donnait des contraintes
      // LÂCHES à la touche, qui se repliait sur la largeur de son mot ; la
      // pastille, restée au bord de la pile, flottait à côté d'elle.
      final sans = await rangee(tester, nonLu: false);
      final avec = await rangee(tester, nonLu: true);

      expect(
        avec.touche.width,
        moreOrLessEquals(sans.touche.width, epsilon: 0.5),
        reason: 'la pastille ne change pas la largeur de la touche',
      );
      expect(
        avec.touche.width,
        moreOrLessEquals(avec.cellule.width, epsilon: 0.5),
        reason: 'la touche remplit toujours sa cellule',
      );
      // Et la pastille est POSÉE DESSUS, pas à côté.
      expect(
        avec.touche.contains(avec.pastille.topLeft),
        isTrue,
        reason: 'la pastille déborde de la touche',
      );
      expect(
        avec.touche.contains(
          avec.pastille.bottomRight - const Offset(0.5, 0.5),
        ),
        isTrue,
        reason: 'la pastille déborde de la touche',
      );
    });
  });

  group('Son allure', () {
    testWidgets('couleur 1 du thème, et le trait noir des touches', (
      tester,
    ) async {
      await poser(tester);
      final peinture = rond(tester);

      expect(peinture.color, paletteOf('foret').clair);
      expect(peinture.border?.top.color, Colors.black);
      expect(peinture.shape, BoxShape.circle);
    });

    testWidgets('elle reste allumée : plus de clignotement', (tester) async {
      await poser(tester);
      expect(find.byType(AnimatedOpacity), findsNothing);

      // Trois secondes plus tard, elle est toujours là, entière.
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(PastilleNonLue), findsOneWidget);
      expect(find.byType(Opacity), findsNothing);
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
