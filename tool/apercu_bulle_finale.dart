/// L'aperçu de la bulle de cri TELLE QU'ELLE EST DANS L'APPLI.
///
/// Les planches précédentes dessinaient la forme à la main, avec le
/// rembourrage d'avant. Celle-ci fait poser de vrais `MessageBubble` par
/// Flutter et photographie le résultat : c'est donc le creux ajouté à la
/// marge, la largeur maximale, la police et l'échelle réelles.
///
/// `flutter test tool/apercu_bulle_finale.dart`
// Ce fichier EST un test — il tourne sous `flutter test` — mais il vit dans
// `tool/` pour que l'intégration continue ne le lance pas : il écrit un PNG,
// ce qui n'est pas le travail d'une vérification.
// ignore_for_file: invalid_use_of_visible_for_testing_member
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
import 'package:lafuga/ui/widgets/message_bubble.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('la planche finale', (tester) async {
    // Lecture SYNCHRONE : `testWidgets` tourne dans un temps truqué, où une
    // vraie entrée-sortie ne se termine jamais. Un `readAsBytes()` ici fige
    // le test jusqu'à son délai de dix minutes.
    final police = FontLoader('Roboto')
      ..addFont(
        Future.value(
          ByteData.view(
            File(
              '/opt/flutter/bin/cache/artifacts/material_fonts/'
              'Roboto-Regular.ttf',
            ).readAsBytesSync().buffer,
          ),
        ),
      );
    await police.load();
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
    addTearDown(resetScale);

    const cle = ValueKey('planche');
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final palette = paletteOf('original');
    Widget bulle(String t, bool deMoi) => Align(
      alignment: deMoi ? Alignment.centerRight : Alignment.centerLeft,
      child: MessageBubble(
        texte: t,
        deMoi: deMoi,
        palette: palette,
        selectionnable: false,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        home: Scaffold(
          backgroundColor: palette.menu,
          body: RepaintBoundary(
            key: cle,
            // Le fond DANS la photo : une capture ne prend que son enfant, et
            // sur du blanc les creux ne se lisent pas comme dans l'appli.
            child: ColoredBox(
              color: palette.menu,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    bulle('Salut, bien joué pour hier.', false),
                    bulle('Merci !', true),
                    bulle('Tu vas voir ce que tu vas voir !?', false),
                    bulle(
                      "J'arrive pas à y croire, t'as vraiment "
                      'poussé le garde là-dedans !',
                      true,
                    ),
                    bulle('On se refait ça demain ?', false),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boite = tester.renderObject<RenderRepaintBoundary>(find.byKey(cle));
    final image = await boite.toImage(pixelRatio: 3);
    final octets = await image.toByteData(format: ui.ImageByteFormat.png);
    File(
      'tool/apercus/bulle_finale.png',
    ).writeAsBytesSync(Uint8List.view(octets!.buffer));
  });
}
