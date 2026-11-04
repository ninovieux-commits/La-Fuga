/// Aperçu du menu refondu : les deux façons de jouer côte à côte, la
/// recherche remontée, et les quatre grosses touches à symbole.
///
/// Ce fichier ne sert qu'à dessiner : il ne fait pas partie de l'application.
/// `flutter test tool/apercu_menu.dart` écrit des PNG dans `tool/apercus/`.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/main.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Key _cadre = Key('ecran');

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (nom, theme) in [
    ('menu', 'original'),
    ('menu_deepgrey', 'deepgrey'),
  ]) {
    testWidgets('aperçu du $nom', (tester) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({
        'lang_chosen': true,
        'tuto_seen': true,
        'theme': theme,
      });
      await Settings.load();
      await Translations.load('fr');
      resetScale();
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // LA POLICE DE L'APPLICATION, et non celle des essais : `FugaApp`
      // écrit en `NotoSansCJK`, et sans elle chaque lettre sort en carré.
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

      await tester.pumpWidget(
        const RepaintBoundary(key: _cadre, child: FugaApp()),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // Les dessins se décodent hors de la frame : sans cette attente, les
      // quatre symboles sortent blancs.
      await tester.runAsync(() async {
        for (final asset in [
          'assets/images/chat.webp',
          'assets/images/podium.webp',
          'assets/images/deepgrey_silhouette.webp',
          'assets/images/titre.webp',
        ]) {
          await precacheImage(
            AssetImage(asset),
            tester.element(find.byType(MaterialApp)),
          );
        }
      });
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      Directory('tool/apercus').createSync(recursive: true);
      final limite =
          tester.renderObject(find.byKey(_cadre)) as RenderRepaintBoundary;
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
