/// Aperçu du volet « Classement » posé sur le menu, bandeau du haut vivant.
///
/// Ce fichier ne sert qu'à dessiner : il ne fait pas partie de l'application.
/// `flutter test tool/apercu_classement.dart` écrit un PNG dans
/// `tool/apercus/`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/widgets/profile_photo.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/menu_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fake_realtime.dart';

const Key _cadre = Key('ecran');

const List<String> _pseudos = [
  'mesange',
  'nino',
  'celia',
  'lilou',
  'Vem',
  'corbeau',
  'alouette',
  'faucon',
  'pinson',
  'hirondelle',
];

Map<String, dynamic> _classement() => {
  'ok': true,
  'joueurs': [
    for (var i = 0; i < _pseudos.length; i++)
      {
        'rang': i + 1,
        'pseudo': _pseudos[i],
        'melo': 1930 - i * 37,
        'photo': '',
      },
  ],
  'moi': {'rang': 42, 'pseudo': 'nino', 'melo': 1530, 'photo': ''},
};

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('aperçu du classement', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    resetScale();
    // L'ÉCHELLE À LA MAIN. Sans [FugaScale] au-dessus — et il n'y en a pas
    // ici, puisqu'on pose `MenuScreen` sous un `MaterialApp` nu — l'échelle
    // se lit sur la fenêtre du banc d'essai, qui reste à 800 × 600 quoi
    // qu'on dise à `tester.view`. L'aperçu sortait alors avec des
    // écritures presque deux fois trop grandes pour son écran, et Nino a
    // cru les mélos énormes : ils ne le sont que sur l'aperçu.
    setScaleSize(const Size(393, 851));
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      for (final (famille, chemin) in [
        ('NotoSansCJK', 'assets/fonts/NotoSansCJKsc-Regular.otf'),
        (
          'Roboto',
          '/opt/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
        ),
      ]) {
        final police = FontLoader(famille)
          ..addFont(
            File(chemin).readAsBytes().then((o) => ByteData.view(o.buffer)),
          );
        await police.load();
      }
    });

    final socket = FakeRealtime();
    final client = MockClient((request) async {
      final reponse = switch (request.url.path) {
        '/login' => {'ok': true, 'token': 't', 'pseudo': 'nino', 'melo': 1530},
        '/classement' => _classement(),
        _ => {'ok': true},
      };
      return http.Response(
        jsonEncode(reponse),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final online = OnlineService(
      client: OnlineClient(api: ApiClient(client: client)),
      socketFactory: (_) => socket,
    );
    await online.login('nino', 'mdp');
    await online.connectSocket();

    await tester.pumpWidget(
      RepaintBoundary(
        key: _cadre,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'NotoSansCJK'),
          home: MenuScreen(online: online),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Classement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Classement'));
    await tester.pumpAndSettle();

    // Une photo par défaut est le logo du thème : un `Image.asset`, qui se
    // décode HORS de la frame. Sans cette attente, la colonne des visages
    // sort vide sur l'aperçu — et seulement sur l'aperçu.
    await tester.runAsync(() async {
      await precacheImage(
        AssetImage(logoAssetOf('original')),
        tester.element(find.byType(MaterialApp)),
      );
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
      'tool/apercus/classement.png',
    ).writeAsBytesSync(Uint8List.view(octets!.buffer));
  });
}
