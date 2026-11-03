/// Aperçu de la palette : les carreaux, et les nuances.
///
/// Ce fichier ne sert qu'à dessiner : il ne fait pas partie de l'application.
/// `flutter test tool/apercu_palette.dart` écrit un PNG dans `tool/apercus/`.
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
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:lafuga/ui/widgets/palette_couleurs.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GlobalKey _cadre = GlobalKey();

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('aperçu de la palette', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
    tester.view.physicalSize = const Size(700, 560);
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
          child: ColoredBox(
            color: Colors.black,
            child: DefaultTextStyle(
              style: const TextStyle(fontFamily: 'Roboto'),
              child: Padding(
                padding: EdgeInsets.all(S(10)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < 2; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: S(8)),
                          // Material, comme le Dialog du vrai popup : le
                          // champ du code hexadécimal en a besoin.
                          child: Material(
                            color: kFugaGrey,
                            child: Padding(
                              padding: EdgeInsets.all(S(8)),
                              child: const CorpsDeLaPalette(
                                actuelle: Color(0xFFFF2D2D),
                              ),
                            ),
                          ),
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
    await tester.pumpAndSettle();

    // Celle de droite passe en nuances : les deux modes côte à côte.
    await tester.tap(find.text('Nuances').at(1));
    await tester.pumpAndSettle();

    Directory('tool/apercus').createSync(recursive: true);
    final limite =
        _cadre.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final octets = await tester.runAsync(() async {
      final image = await limite.toImage(pixelRatio: 2.5);
      return image.toByteData(format: ui.ImageByteFormat.png);
    });
    File(
      'tool/apercus/palette.png',
    ).writeAsBytesSync(Uint8List.view(octets!.buffer));
  });
}
