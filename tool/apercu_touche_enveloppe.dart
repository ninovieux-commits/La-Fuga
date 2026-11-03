/// Aperçu de la touche « enveloppe + » contre « < Retour », et de la rangée
/// de jetons à sa nouvelle taille.
///
/// Ce fichier ne sert qu'à dessiner : il ne fait pas partie de l'application.
/// `flutter test tool/apercu_touche_enveloppe.dart` écrit un PNG dans
/// `tool/apercus/`.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/game/enveloppe.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:lafuga/ui/widgets/enveloppe_jeton.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GlobalKey _cadre = GlobalKey();

Enveloppe _env(Duration reste, {required bool deMoi, int id = 1}) {
  final maintenant = DateTime(2026, 11, 3, 12);
  return Enveloppe(
    id: id,
    deMoi: deMoi,
    creeA: maintenant.millisecondsSinceEpoch ~/ 1000,
    expireA: maintenant.add(reste).millisecondsSinceEpoch ~/ 1000,
  );
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('aperçu de la touche enveloppe', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
    tester.view.physicalSize = const Size(393, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final police = FontLoader('Roboto')
        ..addFont(
          File(
            '/opt/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
          ).readAsBytes().then((o) => ByteData.view(o.buffer)),
        );
      await police.load();
    });

    final palette = paletteOf('original');
    final maintenant = DateTime(2026, 11, 3, 12);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Roboto'),
        home: RepaintBoundary(
          key: _cadre,
          child: ColoredBox(
            color: const Color(0xFF6B5A3E),
            child: DefaultTextStyle(
              style: const TextStyle(fontFamily: 'Roboto'),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // LE BANDEAU : « < Retour » et la touche, côte à côte,
                    // pour comparer les deux gris.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SizedBox(
                          width: 110,
                          child: FugaButton(
                            text: '< Retour',
                            fontSize: SF(16),
                            onPressed: () {},
                          ),
                        ),
                        SizedBox(
                          height: touchHeight(),
                          child: ToucheEnveloppePlus(
                            palette: palette,
                            onPressed: () {},
                          ),
                        ),
                      ],
                    ),
                    // LA RANGÉE DU BAS : les visages et les deux boîtes
                    // aux lettres. Recopié de `_boiteAuxLettres`, dans la
                    // conversation : un aperçu ne peut pas appeler une
                    // méthode privée d'écran, et c'est l'ALLURE qu'on vient
                    // vérifier ici, pas le branchement.
                    Row(
                      children: [
                        _visage(const Color(0xFFCCCCCC)),
                        _boite(palette.fonce, maintenant, [
                          _env(kEnveloppeVie, deMoi: true, id: 1),
                          _env(
                            const Duration(hours: 12, minutes: 34),
                            deMoi: true,
                            id: 2,
                          ),
                        ]),
                        const Spacer(),
                        _boite(palette.fonce, maintenant, [
                          _env(
                            const Duration(hours: 47, minutes: 59),
                            deMoi: false,
                            id: 3,
                          ),
                        ]),
                        _visage(const Color(0xFF888888)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // LE DESSIN NE PARAÎT QUE SI ON L'ATTEND. Un `Image.asset` se décode
    // hors de la frame : sans `precacheImage` dans un `runAsync`, l'aperçu
    // sortait avec des cases vides, et Nino l'a vu avant moi — « y a même pas
    // les enveloppes sur ton aperçu ».
    await tester.runAsync(() async {
      for (final asset in [
        'assets/images/enveloppe.webp',
        'assets/images/enveloppe_plus.webp',
      ]) {
        await precacheImage(
          AssetImage(asset),
          tester.element(find.byType(ColoredBox).first),
        );
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    Directory('tool/apercus').createSync(recursive: true);
    final limite =
        _cadre.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final octets = await tester.runAsync(() async {
      final image = await limite.toImage(pixelRatio: 3);
      return image.toByteData(format: ui.ImageByteFormat.png);
    });
    File(
      'tool/apercus/touche_enveloppe.png',
    ).writeAsBytesSync(Uint8List.view(octets!.buffer));
  });
}

/// Un visage, à la taille qu'il a au bas d'une conversation.
Widget _visage(Color couleur) => Container(
  width: kAvatarBasConversation,
  height: kAvatarBasConversation,
  decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
);

/// Une boîte aux lettres, comme la conversation la dessine.
Widget _boite(Color couleur, DateTime maintenant, List<Enveloppe> dedans) {
  final cote = touchHeight();
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        height: hauteurDuMotDeLaBoite,
        child: Text(
          'Boîte aux lettres',
          style: TextStyle(
            color: Colors.white,
            fontSize: SF(10),
            fontWeight: FontWeight.bold,
            shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
          ),
        ),
      ),
      SizedBox(height: S(2)),
      Container(
        padding: EdgeInsets.all(S(3)),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(S(8)),
          border: const Border.fromBorderSide(kTraitDeTouche),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var place = 0; place < kEnveloppesEnAttente; place++)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: S(2)),
                child: SizedBox(
                  width: cote,
                  height: cote,
                  child: place < dedans.length
                      ? EnveloppeJeton(
                          enveloppe: dedans[place],
                          couleur: couleur,
                          maintenant: maintenant,
                          onTap: () {},
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
