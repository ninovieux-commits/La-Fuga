/// Aperçu du COMPOSEUR DE THÈMES, pour en juger d'un coup d'œil.
///
/// Ce fichier ne sert qu'à dessiner : il ne fait pas partie de l'application.
/// `flutter test tool/apercu_theme_composeur.dart` écrit des PNG dans
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
import 'package:lafuga/theme/theme_assets.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/theme_composer_screen.dart';
import 'package:lafuga/ui/widgets/profile_photo.dart';
import 'package:lafuga/ui/widgets/theme_image_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Key _cadre = Key('ecran');

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (nom, compo) in [
    ('composeur_theme', 'original|medieval|ocean|dragon|fleur'),
    (
      'composeur_theme_deepgrey',
      'deepgrey|deepgrey|deepgrey|deepgrey|deepgrey',
    ),
  ]) {
    testWidgets('aperçu du $nom', (tester) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({
        'lang_chosen': true,
        'tuto_seen': true,
        'theme': compo,
      });
      await Settings.load();
      await Translations.load('fr');
      resetScale();
      setScaleSize(const Size(393, 851));
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(resetScale);

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
        RepaintBoundary(
          key: _cadre,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'NotoSansCJK'),
            home: const ThemeComposerScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Les vignettes sont des `Image.asset` : elles se décodent hors frame.
      await tester.runAsync(() async {
        for (final theme in kThemeOrder) {
          await precacheImage(
            AssetImage(logoAssetOf(theme)),
            tester.element(find.byType(MaterialApp)),
          );
          for (final asset in [
            imagesFor(theme)?.background,
            imagesFor(theme)?.board,
          ]) {
            if (asset == null) continue;
            await precacheImage(
              AssetImage(asset),
              tester.element(find.byType(MaterialApp)),
            );
          }
          await ThemeImageCache.load(theme);
        }
      });
      await tester.pumpAndSettle();

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
