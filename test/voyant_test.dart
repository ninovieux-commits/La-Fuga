/// Les deux voyants du menu : la barre de séparation et le cadre des aperçus
/// de correspondance.
///
/// Nino : « le contour gris des aperçus de correspondance qui s'allume en
/// couleur 1 quand c'est à nous de jouer (comme la barre de séparation) doit
/// devenir de la même épaisseur que la barre de séparation en question. [...]
/// Le gris quand ce n'est pas éclairé doit être le gris médian. En couleur
/// système deepgrey ça s'allume en blanc (idem pour la barre de
/// séparation). »
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/corr_slot.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

CorrGame _partie({required bool aMoi}) => CorrGame.fromJson({
  'id': 'x',
  'statut': 'en_cours',
  'ma_couleur': 'Blanc',
  'adversaire': 'mesange',
  'turn': aMoi ? 'Blanc' : 'Noir',
  'moves_text': '1.Do2-Do3/Do7-Do6',
  'my_turn': aMoi,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'lang_chosen': true});
    await Settings.load();
    await Translations.load('fr');
    resetScale();
  });
  tearDown(resetScale);

  group('La couleur d un voyant allumé', () {
    test('ne se confond JAMAIS avec celle d un voyant éteint', () {
      for (final nom in kThemeOrder) {
        expect(
          couleurAllumee(paletteOf(nom)),
          isNot(kGrisTouche),
          reason: 'thème $nom : allumé, le voyant doit se voir',
        );
      }
    });

    test('c est la couleur 1 du thème, et le blanc en deepgrey', () {
      expect(couleurAllumee(paletteOf('deepgrey')), Colors.white);
      final original = paletteOf('original');
      expect(couleurAllumee(original), original.clair);
    });
  });

  group('Le cadre d un aperçu de correspondance', () {
    /// Le `Container` qui porte le cadre : le seul de la case à avoir une
    /// bordure au premier plan.
    Container cadreDe(WidgetTester tester) => tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(CorrSlot),
            matching: find.byType(Container),
          ),
        )
        .firstWhere((c) => c.foregroundDecoration != null);

    Future<void> pose(
      WidgetTester tester, {
      required bool aMoi,
      String theme = 'original',
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FugaScale(
            child: Center(
              child: SizedBox(
                width: 178,
                child: CorrSlot(
                  game: _partie(aMoi: aMoi),
                  palette: paletteOf(theme),
                  boardTheme: theme,
                  pieceTheme: theme,
                  onTap: () {},
                  onAccept: (_) {},
                  onRefuse: (_) {},
                  onCancel: (_) {},
                  onRematch: (_) {},
                  onClose: (_) {},
                  onShow: (_) {},
                  onShowChallenge: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('fait l épaisseur de la barre de séparation', (tester) async {
      await pose(tester, aMoi: true);
      expect(
        cadreDe(tester).padding,
        EdgeInsets.all(S(kEpaisseurDuVoyant)),
        reason:
            'le cadre et la barre disent la même chose, à la même '
            'épaisseur',
      );
    });

    testWidgets('s allume quand c est à nous, et reste gris sinon', (
      tester,
    ) async {
      await pose(tester, aMoi: true);
      expect(
        (cadreDe(tester).decoration! as BoxDecoration).color,
        paletteOf('original').clair,
      );

      await pose(tester, aMoi: false);
      expect(
        (cadreDe(tester).decoration! as BoxDecoration).color,
        kGrisTouche,
        reason: 'éteint, c est le gris médian de toutes les touches',
      );
    });

    testWidgets('s allume en BLANC en système deepgrey', (tester) async {
      await pose(tester, aMoi: true, theme: 'deepgrey');
      expect(
        (cadreDe(tester).decoration! as BoxDecoration).color,
        Colors.white,
        reason: 'les deux couleurs du thème valent le gris des touches',
      );
    });
  });
}
