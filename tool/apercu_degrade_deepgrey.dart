/// Maquette : et si la couleur de sélection de deepgrey était un DÉGRADÉ ?
///
/// En thème deepgrey, les deux couleurs du thème valent rgb(128, 128, 128),
/// c'est-à-dire exactement le fond des touches : une touche allumée ne se
/// distingue pas d'une touche éteinte. Nino : « montre-moi à quoi ça
/// ressemblerait si la couleur de sélection deep grey était un dégradé de
/// blanc au centre jusqu'à noir au bord. Et montre-moi aussi pour un dégradé
/// noir au centre et blanc au bord. »
///
/// RIEN DANS `lib/` N'EST TOUCHÉ : ce fichier redessine les rangées du menu
/// à la main, comme `apercu_touche_enveloppe` redessine la boîte aux
/// lettres. Tant que le choix n'est pas fait, l'application ne connaît pas
/// ces dégradés.
///
/// `flutter test tool/apercu_degrade_deepgrey.dart` écrit deux PNG dans
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

final GlobalKey _cadre = GlobalKey();

/// Une touche dont le FOND est un dégradé : la touche ordinaire, rendue
/// transparente, posée sur le dégradé. Son trait noir et son arrondi ne
/// changent pas d'un cheveu.
Widget _toucheDegradee({
  required String texte,
  required Gradient degrade,
  double? hauteur,
}) => Container(
  decoration: BoxDecoration(
    gradient: degrade,
    borderRadius: BorderRadius.circular(S(18)),
  ),
  child: FugaButton(
    text: texte,
    color: Colors.transparent,
    height: hauteur ?? touchHeight(),
    fontSize: SF(16),
    onPressed: () {},
  ),
);

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
            MotTouche(
              texte: texte,
              couleur: Colors.white,
              style: TextStyle(fontSize: SF(14), fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (nom, degrade) in [
    // Blanc au centre, noir au bord.
    (
      'degrade_clair',
      const RadialGradient(colors: [Colors.white, Colors.black], radius: 0.9),
    ),
    // Noir au centre, blanc au bord.
    (
      'degrade_sombre',
      const RadialGradient(colors: [Colors.black, Colors.white], radius: 0.9),
    ),
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
      tester.view.physicalSize = const Size(393, 330);
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
      final palette = paletteOf('deepgrey');

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
                    // La rangée des cadences : celle du milieu est choisie.
                    SizedBox(
                      height: touchHeight(),
                      child: rangee([
                        FugaButton(
                          text: '5 min',
                          fontSize: SF(15),
                          height: double.infinity,
                          onPressed: () {},
                        ),
                        _toucheDegradee(
                          texte: '15 min',
                          degrade: degrade,
                          hauteur: double.infinity,
                        ),
                        FugaButton(
                          text: '30 min',
                          fontSize: SF(15),
                          height: double.infinity,
                          onPressed: () {},
                        ),
                      ]),
                    ),
                    SizedBox(height: ecart),
                    // Les deux façons de jouer : les deux couleurs du thème.
                    SizedBox(
                      height: touchHeight(),
                      child: rangee([
                        _toucheDegradee(
                          texte: T('Jouer en local'),
                          degrade: degrade,
                          hauteur: double.infinity,
                        ),
                        _toucheDegradee(
                          texte: T('Jouer en ligne'),
                          degrade: degrade,
                          hauteur: double.infinity,
                        ),
                      ]),
                    ),
                    SizedBox(height: ecart),
                    // Les grosses touches ne changent pas : leur fond n'a
                    // jamais été une couleur de thème.
                    Center(
                      child: FractionallySizedBox(
                        widthFactor: 0.7,
                        child: Row(
                          children: [
                            Expanded(
                              child: _grosse(
                                'assets/images/chat.webp',
                                T('Conversations'),
                                palette.clair,
                              ),
                            ),
                            SizedBox(width: ecart),
                            Expanded(
                              child: _grosse(
                                'assets/images/podium.webp',
                                T('Classement'),
                                palette.fonce,
                              ),
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
