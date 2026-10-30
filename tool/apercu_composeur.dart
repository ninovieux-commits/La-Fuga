/// Aperçu du COMPOSEUR DE POSITION : la pièce en main s'enfonce.
///
/// Ce fichier ne sert qu'à dessiner : il ne fait pas partie de l'application.
/// On le lance avec `flutter test tool/apercu_composeur.dart`, il écrit un PNG
/// dans `tool/apercus/`.
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
import 'package:lafuga/theme/theme_assets.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/position_composer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Size _ecran = Size(393, 851);

final GlobalKey _cadre = GlobalKey();

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('aperçu du composeur de position', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(_ecran);
    tester.view.physicalSize = _ecran;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Sans cela le texte sort en rectangles noirs : la police des tests n'a
    // pas de glyphes.
    // DANS `runAsync` : hors de lui, le temps du test est faux et la lecture
    // du fichier de police ne se termine jamais — le test se bloque là.
    await tester.runAsync(() async {
      final police = FontLoader('Roboto')
        ..addFont(
          File(
            '/opt/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
          ).readAsBytes().then((o) => ByteData.view(o.buffer)),
        );
      await police.load();
    });

    await tester.pumpWidget(
      RepaintBoundary(
        key: _cadre,
        child: const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: PositionComposerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Les images (pictos des touches, visages) ne sont pas chargées dans un
    // test : sans ce passage, l'aperçu les montre vides.
    final images = find.byType(Image).evaluate().toList();
    await tester.runAsync(() async {
      for (final e in images) {
        final image = e.widget as Image;
        await precacheImage(image.image, e);
      }
      final fond = imagesFor(Settings.instance.themeAxes.general)?.background;
      if (fond != null) {
        await precacheImage(
          AssetImage(fond),
          tester.element(find.byType(PositionComposerScreen)),
        );
      }
    });
    await tester.pumpAndSettle();

    final limite =
        _cadre.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await tester.runAsync(() => limite.toImage(pixelRatio: 2));
    final octets = await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.png),
    );
    Directory('tool/apercus').createSync(recursive: true);
    File(
      'tool/apercus/composeur.png',
    ).writeAsBytesSync(Uint8List.view(octets!.buffer));
  });
}
