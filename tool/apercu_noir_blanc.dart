/// Maquette : et si les deux couleurs de deepgrey étaient le blanc et le noir ?
///
/// Nino : « et si on fait comme couleur 1 et couleur 2 mais avec noir et
/// blanc ? » Autrement dit : pas de dégradé, mais les deux couleurs du
/// thème remplacées par du blanc et du noir francs — ce que le thème fait
/// déjà avec ses deux couleurs partout ailleurs.
///
/// DEUX VERSIONS, parce qu'un détail décide de tout : le mot d'une touche
/// est écrit en blanc dans toute l'application. Sur une touche BLANCHE, il
/// ne tient que par son contour noir. La seconde image lui donne l'encre
/// noire quand le fond est clair.
///
/// RIEN DANS `lib/` N'EST TOUCHÉ : l'aperçu redessine les rangées du menu à
/// la main, et l'application ne connaît pas ces couleurs.
///
/// `flutter test tool/apercu_noir_blanc.dart` écrit deux PNG dans
/// `tool/apercus/`.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/menu_screen.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:lafuga/ui/widgets/picto_touche.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ce que deviendraient les deux couleurs du thème.
const Color kCouleur1 = Colors.white;
const Color kCouleur2 = Colors.black;

final GlobalKey _cadre = GlobalKey();

/// Une des quatre grosses touches, telle que le menu la dessine.
Widget _grosse(String dessin, String texte, Color teinte) {
  final rayon = S(18);
  final marge = S(8);
  return SizedBox(
    height: touchHeight() * 2,
    child: Material(
      color: kGrisTouche,
      shape: formeDeTouche(BorderRadius.circular(rayon)),
      child: Padding(
        padding: EdgeInsets.all(marge),
        child: Column(
          children: [
            Expanded(
              child: PictoTouche(
                asset: dessin,
                couleur: teinte,
                part: kPartDuSymboleDesGrosses,
              ),
            ),
            SizedBox(height: S(4)),
            // Deux lignes réservées, comme dans le menu : sans elles,
            // « Affronter Deep Grey » perdrait sa seconde ligne.
            SizedBox(
              height: SF(14) * 1.35 * 2,
              child: Center(
                child: MotTouche(
                  texte: texte,
                  couleur: Colors.white,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: SF(14),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (nom, encreSurClair) in [
    // Le mot reste blanc, comme partout dans l'application aujourd'hui.
    ('noir_blanc', Colors.white),
    // Le mot passe au noir quand le fond est clair.
    ('noir_blanc_encre', Colors.black),
  ]) {
    testWidgets('aperçu $nom', (tester) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({
        'lang_chosen': true,
        'tuto_seen': true,
        'theme': 'deepgrey',
      });
      await Settings.load();
      await Translations.load('fr');
      resetScale();
      setScaleSize(const Size(393, 851));
      tester.view.physicalSize = const Size(393, 440);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
        for (final (famille, chemin) in [
          ('NotoSansCJK', 'assets/fonts/NotoSansCJKsc-Regular.otf'),
          (
            'Roboto',
            '/opt/flutter/bin/cache/artifacts/material_fonts/'
                'Roboto-Regular.ttf',
          ),
        ]) {
          final police = FontLoader(famille)
            ..addFont(
              File(chemin).readAsBytes().then((o) => ByteData.view(o.buffer)),
            );
          await police.load();
        }
      });

      final ecart = intervalleDuMenu();

      Widget rangee(List<Widget> touches) => Padding(
        padding: EdgeInsets.symmetric(horizontal: S(kMargeDeLaBande)),
        child: Row(
          children: [
            for (var i = 0; i < touches.length; i++) ...[
              if (i > 0) SizedBox(width: ecart),
              Expanded(child: touches[i]),
            ],
          ],
        ),
      );

      Widget touche(String texte, Color fond) => FugaButton(
        text: texte,
        color: fond,
        textColor: fond == kCouleur1 ? encreSurClair : Colors.white,
        height: double.infinity,
        fontSize: SF(16),
        onPressed: () {},
      );

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'NotoSansCJK'),
          home: RepaintBoundary(
            key: _cadre,
            child: ColoredBox(
              color: paletteOf('deepgrey').menu,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: S(10)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Les cadences : celle du milieu s'allume en couleur 2,
                    // les deux bords en couleur 1.
                    SizedBox(
                      height: touchHeight(),
                      child: rangee([
                        touche('5 min', kCouleur1),
                        touche('15 min', kCouleur2),
                        FugaButton(
                          text: '30 min',
                          fontSize: SF(15),
                          height: double.infinity,
                          onPressed: () {},
                        ),
                      ]),
                    ),
                    SizedBox(height: ecart),
                    SizedBox(
                      height: touchHeight(),
                      child: rangee([
                        touche(T('Jouer en local'), kCouleur1),
                        touche(T('Jouer en ligne'), kCouleur2),
                      ]),
                    ),
                    SizedBox(height: ecart),
                    // Les symboles aussi portent les deux couleurs : c'est
                    // là que deepgrey les perdait, gris sur gris.
                    Center(
                      child: FractionallySizedBox(
                        widthFactor: 0.7,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _grosse(
                                    'assets/images/chat.webp',
                                    T('Conversations'),
                                    kCouleur1,
                                  ),
                                ),
                                SizedBox(width: ecart),
                                Expanded(
                                  child: _grosse(
                                    'assets/images/podium.webp',
                                    T('Classement'),
                                    kCouleur2,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: ecart),
                            Row(
                              children: [
                                Expanded(
                                  child: _grosse(
                                    'assets/images/deepgrey_silhouette.webp',
                                    nomInsecable(T('Affronter Deep Grey')),
                                    kCouleur2,
                                  ),
                                ),
                                SizedBox(width: ecart),
                                Expanded(
                                  child: _grosse(
                                    'assets/images/plus.webp',
                                    T('Autres'),
                                    kCouleur1,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (final asset in [
          'assets/images/chat.webp',
          'assets/images/podium.webp',
          'assets/images/deepgrey_silhouette.webp',
          'assets/images/plus.webp',
        ]) {
          await precacheImage(
            AssetImage(asset),
            tester.element(find.byType(MaterialApp)),
          );
        }
      });
      await tester.pumpAndSettle();

      Directory('tool/apercus').createSync(recursive: true);
      final limite =
          _cadre.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final octets = await tester.runAsync(() async {
        final image = await limite.toImage(pixelRatio: 2);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File(
        'tool/apercus/$nom.png',
      ).writeAsBytesSync(Uint8List.view(octets!.buffer));
    });
  }
}
