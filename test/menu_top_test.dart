/// Le haut du menu : aucune bande vide, et le défilement va jusqu'au bord.
///
/// L'appli tourne en plein écran immersif — Kivy donne au défilement TOUTE la
/// fenêtre (`ScrollView(size_hint=(1, 1))`) et place les touches Random et
/// Compte à `top: 0.985`, soit 1,5 % du haut. La version Flutter ajoutait une
/// `SafeArea` : sur un téléphone à encoche, elle réservait en haut une bande
/// que rien ne remplissait, et le menu ne pouvait pas défiler jusqu'au bord.
///
/// Ce test simule justement un écran à encoche : sans cela, la marge de
/// sécurité vaut zéro et le défaut reste invisible.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/menu_screen.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    resetScale();
  });
  tearDown(resetScale);

  /// Ouvre le menu sur un écran donné, avec une encoche en haut.
  Future<void> ouvrir(WidgetTester tester, Size taille, double encoche) async {
    tester.view.physicalSize = taille;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(top: encoche);
    tester.view.viewPadding = FakeViewPadding(top: encoche);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: FugaScale(child: MenuScreen(online: OnlineService())),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
  }

  Rect toucheNommee(WidgetTester tester, String texte) {
    for (final element in find.byType(FugaButton).evaluate()) {
      if ((element.widget as FugaButton).text == texte) {
        return (element.renderObject as RenderBox).localToGlobal(Offset.zero) &
            (element.renderObject as RenderBox).size;
      }
    }
    fail('touche « $texte » introuvable');
  }

  for (final (forme, taille, encoche) in [
    ('un téléphone à encoche', const Size(393, 851), 48.0),
    ('un téléphone sans encoche', const Size(393, 851), 0.0),
    ('un grand écran à encoche', const Size(412, 915), 60.0),
  ]) {
    group('sur $forme', () {
      testWidgets('les touches du haut sont à 1,5 % du bord, comme en Kivy', (
        tester,
      ) async {
        await ouvrir(tester, taille, encoche);
        final attendu = SH(0.015);
        for (final texte in ['Random', 'Compte']) {
          final r = toucheNommee(tester, texte);
          expect(
            r.top,
            moreOrLessEquals(attendu, epsilon: 0.5),
            reason:
                'la touche « $texte » commence à ${r.top.toStringAsFixed(1)} '
                'au lieu de ${attendu.toStringAsFixed(1)} : une bande vide '
                'reste en haut de l\'écran',
          );
        }
      });

      testWidgets('le menu défile sur toute la hauteur de l\'écran', (
        tester,
      ) async {
        await ouvrir(tester, taille, encoche);
        final vue = find.byType(SingleChildScrollView);
        expect(vue, findsOneWidget);
        final box = tester.renderObject<RenderBox>(vue);
        final haut = box.localToGlobal(Offset.zero).dy;
        expect(
          haut,
          moreOrLessEquals(0, epsilon: 0.5),
          reason:
              'le menu commence à ${haut.toStringAsFixed(1)} : il ne peut pas '
              'défiler jusqu\'en haut de l\'écran',
        );
        expect(
          box.size.height,
          moreOrLessEquals(taille.height, epsilon: 0.5),
          reason: 'le menu n\'occupe pas toute la hauteur',
        );
      });

      testWidgets('en défilant, le contenu passe bien sous le bord du haut', (
        tester,
      ) async {
        await ouvrir(tester, taille, encoche);
        final titre = find.byType(Image).first;
        final avant = tester.getRect(titre).top;
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -220),
        );
        await tester.pumpAndSettle();
        final apres = tester.getRect(titre).top;
        expect(
          apres,
          lessThan(avant - 100),
          reason: 'le contenu n\'a pas défilé vers le haut',
        );
        expect(
          apres,
          lessThan(SH(0.015)),
          reason:
              'le titre s\'arrête à ${apres.toStringAsFixed(1)} : quelque '
              'chose bloque le défilement avant le bord de l\'écran',
        );
      });
    });
  }
}
