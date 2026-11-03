/// Aperçu des jetons d'enveloppe : le dessin, le chrono, le balancement.
///
/// Ce fichier ne sert qu'à dessiner : il ne fait pas partie de l'application.
/// `flutter test tool/apercu_enveloppes.dart` écrit un PNG dans
/// `tool/apercus/`. Le balancement ne se voit pas sur une image fixe : on
/// dessine donc la MÊME enveloppe à quatre instants de son aller-retour.
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
import 'package:lafuga/ui/widgets/enveloppe_jeton.dart';
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

  testWidgets('aperçu des enveloppes', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
    tester.view.physicalSize = const Size(420, 170);
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
    final recue = _env(kEnveloppeVie, deMoi: false);
    final mienne = _env(
      const Duration(hours: 12, minutes: 34),
      deMoi: true,
      id: 2,
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        // Sans famille explicite, le texte sort en carrés vides : la police
        // chargée s'appelle « Roboto », et rien ne la designe par défaut.
        theme: ThemeData(fontFamily: 'Roboto'),
        home: RepaintBoundary(
          key: _cadre,
          child: ColoredBox(
            color: const Color(0xFFB0A0A4),
            // La police chargée s'appelle « Roboto » ; sans ce style par
            // défaut, le texte sort en carrés vides.
            child: DefaultTextStyle(
              style: const TextStyle(fontFamily: 'Roboto'),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    EnveloppeJeton(
                      enveloppe: recue,
                      couleur: palette.fonce,
                      maintenant: maintenant,
                      cote: 76,
                      onTap: () {},
                    ),
                    EnveloppeJeton(
                      enveloppe: mienne,
                      couleur: palette.clair,
                      maintenant: maintenant,
                      cote: 76,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Directory('tool/apercus').createSync(recursive: true);
    // QUATRE INSTANTS DU BALANCEMENT : il ne se voit pas sur une image fixe,
    // alors on en prend quatre, un quart d'aller-retour d'écart, et le
    // montage les met côte à côte.
    for (var i = 0; i < 4; i++) {
      await tester.pump(kEnveloppeBalancement ~/ 4);
      final limite =
          _cadre.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final octets = await tester.runAsync(() async {
        final image = await limite.toImage(pixelRatio: 3);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File(
        'tool/apercus/enveloppes_$i.png',
      ).writeAsBytesSync(Uint8List.view(octets!.buffer));
    }
  });
}
