/// Aperçu de l'éditeur : le fond noir, le cadre blanc, le cadre bleu de
/// sélection et sa poignée, la touche de couleur et le curseur d'épaisseur.
///
/// Ce fichier ne sert qu'à dessiner : il ne fait pas partie de l'application.
/// `flutter test tool/apercu_editeur.dart` écrit un PNG dans `tool/apercus/`.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/editeur_image_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GlobalKey _cadre = GlobalKey();

/// Une fausse photo : un dégradé et un carré, de quoi juger les contrastes.
Uint8List fausseePhoto() {
  final image = img.Image(width: 480, height: 360);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(x, y, 60 + x ~/ 4, 90 + y ~/ 6, 120);
    }
  }
  img.fillRect(
    image,
    x1: 150,
    y1: 120,
    x2: 330,
    y2: 240,
    color: img.ColorRgb8(210, 190, 160),
  );
  return img.encodePng(image);
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('aperçu de l éditeur', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
      'theme': 'foret',
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
    tester.view.physicalSize = const Size(393, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final photo = fausseePhoto();

    await tester.runAsync(() async {
      final police = FontLoader('Roboto')
        ..addFont(
          File(
            '/opt/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
          ).readAsBytes().then((o) => ByteData.view(o.buffer)),
        );
      await police.load();
      // LES ICÔNES SONT UNE POLICE, elles aussi : sans elle, les touches de
      // la barre sortent en carrés vides.
      final icones = FontLoader('MaterialIcons')
        ..addFont(
          File(
            '/opt/flutter/bin/cache/artifacts/material_fonts/'
            'MaterialIcons-Regular.otf',
          ).readAsBytes().then((o) => ByteData.view(o.buffer)),
        );
      await icones.load();
    });

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Roboto'),
        home: RepaintBoundary(
          key: _cadre,
          child: DefaultTextStyle(
            style: const TextStyle(fontFamily: 'Roboto'),
            child: EditeurImageScreen(image: photo, moi: 'Nino', lui: 'celia'),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(
        MemoryImage(photo),
        tester.element(find.byType(EditeurImageScreen)),
      );
    });
    await tester.pumpAndSettle();

    // Le tampon, posé : il arrive sélectionné, donc dans son cadre bleu.
    await tester.tap(find.byTooltip('Tampon'));
    await tester.pumpAndSettle();

    Directory('tool/apercus').createSync(recursive: true);
    final limite =
        _cadre.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final octets = await tester.runAsync(() async {
      final image = await limite.toImage(pixelRatio: 2.5);
      return image.toByteData(format: ui.ImageByteFormat.png);
    });
    File(
      'tool/apercus/editeur.png',
    ).writeAsBytesSync(Uint8List.view(octets!.buffer));
  });
}
