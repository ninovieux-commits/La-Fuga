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
import 'dart:math' as math;
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

/// Un mot cerné d'une couleur AU CHOIX.
///
/// Nino : « l'écriture doit être blanc sur blanc avec contours noirs pour la
/// couleur 1, et noir sur noir avec les contours blancs pour la couleur 2. »
/// `MotTouche` cerne toujours de noir ; ici le cerne devient un réglage.
Widget _motCerne({
  required String texte,
  required Color couleur,
  required Color contour,
  required TextStyle style,
  int maxLines = 1,
}) => Text(
  texte,
  textAlign: TextAlign.center,
  maxLines: maxLines,
  style: style.copyWith(
    color: couleur,
    shadows: [
      for (var i = 0; i < kCopiesDuBord; i++)
        Shadow(
          color: contour,
          offset: Offset(
            kTraitPicto * math.cos(2 * math.pi * i / kCopiesDuBord),
            kTraitPicto * math.sin(2 * math.pi * i / kCopiesDuBord),
          ),
        ),
    ],
  ),
);

/// Un dessin cerné d'une couleur AU CHOIX — la couronne de [PictoTouche],
/// dont la couleur du cerne n'est plus forcément le noir.
class _PictoCerne extends StatelessWidget {
  const _PictoCerne({
    required this.asset,
    required this.couleur,
    required this.contour,
    required this.part,
  });

  final String asset;
  final Color couleur;
  final Color contour;
  final double part;

  Widget _dessin(Color teinte) =>
      Image.asset(asset, color: teinte, fit: BoxFit.contain);

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    widthFactor: part,
    heightFactor: part,
    child: Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < kCopiesDuBord; i++)
          Transform.translate(
            offset: Offset(
              kTraitPicto * math.cos(2 * math.pi * i / kCopiesDuBord),
              kTraitPicto * math.sin(2 * math.pi * i / kCopiesDuBord),
            ),
            child: _dessin(contour),
          ),
        _dessin(couleur),
      ],
    ),
  );
}

/// Une des quatre grosses touches, telle que le menu la dessine.
Widget _grosse(String dessin, String texte, Color teinte, Color contour) {
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
              child: _PictoCerne(
                asset: dessin,
                couleur: teinte,
                contour: contour,
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

  for (final (nom, encreSurClair, cerneInverse) in [
    // Le mot reste blanc, cerné de noir, comme partout aujourd'hui.
    ('noir_blanc', Colors.white, false),
    // Le mot passe au noir sur fond clair, toujours cerné de noir.
    ('noir_blanc_encre', Colors.black, false),
    // LA RÈGLE DE NINO : la couleur 1 s'écrit en blanc cerné de noir, la
    // couleur 2 en noir cerné de blanc — le cerne prend l'opposé.
    ('noir_blanc_cernes', Colors.white, true),
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

      // Sur la couleur 1, le mot est blanc et le cerne noir ; sur la
      // couleur 2, le mot est noir et le cerne blanc.
      Color encreDe(Color fond) => cerneInverse
          ? (fond == kCouleur1 ? kCouleur1 : kCouleur2)
          : (fond == kCouleur1 ? encreSurClair : Colors.white);
      Color cerneDe(Color fond) =>
          cerneInverse && fond == kCouleur2 ? kCouleur1 : kCouleur2;

      Widget touche(String texte, Color fond) {
        final rayon = S(18);
        return Material(
          color: fond,
          shape: formeDeTouche(BorderRadius.circular(rayon)),
          child: InkWell(
            borderRadius: BorderRadius.circular(rayon),
            onTap: () {},
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: S(10)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: _motCerne(
                    texte: texte,
                    couleur: encreDe(fond),
                    contour: cerneDe(fond),
                    style: TextStyle(
                      fontSize: SF(16),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

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
                                    cerneDe(kCouleur1),
                                  ),
                                ),
                                SizedBox(width: ecart),
                                Expanded(
                                  child: _grosse(
                                    'assets/images/podium.webp',
                                    T('Classement'),
                                    kCouleur2,
                                    cerneDe(kCouleur2),
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
                                    cerneDe(kCouleur2),
                                  ),
                                ),
                                SizedBox(width: ecart),
                                Expanded(
                                  child: _grosse(
                                    'assets/images/plus.webp',
                                    T('Autres'),
                                    kCouleur1,
                                    cerneDe(kCouleur1),
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
