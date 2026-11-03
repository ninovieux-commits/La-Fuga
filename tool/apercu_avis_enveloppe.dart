/// Aperçu de l'avis « a envoyé une enveloppe », dans le fil.
///
/// Ce fichier ne sert qu'à dessiner : il ne fait pas partie de l'application.
/// `flutter test tool/apercu_avis_enveloppe.dart` écrit un PNG dans
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
import 'package:lafuga/ui/widgets/avis_enveloppe.dart';
import 'package:lafuga/ui/widgets/enveloppe_jeton.dart';
import 'package:lafuga/ui/widgets/message_bubble.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GlobalKey _cadre = GlobalKey();

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('aperçu de l avis d enveloppe', (tester) async {
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

    // La sienne et la mienne : deux thèmes bien distincts, pour qu'on voie
    // que l'avis prend la couleur de CELUI QUI ENVOIE.
    final sienne = paletteOf('volcan');
    final mienne = paletteOf('foret');

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
                padding: EdgeInsets.all(S(10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ligne(
                      deMoi: false,
                      enfant: MessageBubble(
                        texte: 'Tu as vu le chien ?',
                        deMoi: false,
                        palette: sienne,
                      ),
                    ),
                    _ligne(
                      deMoi: false,
                      enfant: AvisEnveloppe(
                        texte: 'celia ${T('a envoyé une enveloppe')}',
                        couleur: couleurEnveloppe(sienne),
                        deMoi: false,
                      ),
                    ),
                    _ligne(
                      deMoi: true,
                      enfant: MessageBubble(
                        texte: 'Pas encore, je regarde',
                        deMoi: true,
                        palette: mienne,
                      ),
                    ),
                    _ligne(
                      deMoi: true,
                      enfant: AvisEnveloppe(
                        texte: T('Vous avez envoyé une enveloppe'),
                        couleur: couleurEnveloppe(mienne),
                        deMoi: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    Directory('tool/apercus').createSync(recursive: true);
    final limite =
        _cadre.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final octets = await tester.runAsync(() async {
      final image = await limite.toImage(pixelRatio: 3);
      return image.toByteData(format: ui.ImageByteFormat.png);
    });
    File(
      'tool/apercus/avis_enveloppe.png',
    ).writeAsBytesSync(Uint8List.view(octets!.buffer));
  });
}

/// Une ligne du fil, rangée du côté de son auteur.
Widget _ligne({required bool deMoi, required Widget enfant}) => Padding(
  padding: EdgeInsets.symmetric(vertical: S(4)),
  child: Row(
    mainAxisAlignment: deMoi ? MainAxisAlignment.end : MainAxisAlignment.start,
    children: [Flexible(child: enfant)],
  ),
);
