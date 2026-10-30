/// Aperçu de la bulle de devise : encadrée, et hérissée quand elle crie.
///
/// Ce fichier ne sert qu'à dessiner : il ne fait pas partie de l'application.
/// `flutter test tool/apercu_bulle_devise.dart` écrit un PNG dans
/// `tool/apercus/`.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/bulle_devise.dart';

final GlobalKey _cadre = GlobalKey();

Widget _ligne(String texte, {required bool crie}) => Padding(
  padding: const EdgeInsets.all(18),
  child: BulleDevise(
    couleur: paletteOf('original').fonce,
    crie: crie,
    child: Text(
      texte,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontFamily: 'Roboto',
      ),
    ),
  ),
);

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('aperçu de la bulle de devise', (tester) async {
    setScaleSize(const Size(393, 851));
    tester.view.physicalSize = const Size(520, 420);
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

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: _cadre,
          child: ColoredBox(
            color: const Color(0xFF9E9E9E),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ligne('une devise tranquille', crie: false),
                _ligne('fais ta prière !', crie: true),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final limite =
        _cadre.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final octets = await tester.runAsync(() async {
      final image = await limite.toImage(pixelRatio: 3);
      return image.toByteData(format: ui.ImageByteFormat.png);
    });
    Directory('tool/apercus').createSync(recursive: true);
    File(
      'tool/apercus/bulle_devise.png',
    ).writeAsBytesSync(Uint8List.view(octets!.buffer));
  });
}
