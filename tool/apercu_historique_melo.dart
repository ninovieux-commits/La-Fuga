/// Aperçu de l'historique AVEC les variations de mélo à côté des noms.
///
/// Nino : « il faut que les mélos gagnés et perdus durant une partie soient
/// spécifiés dans l'historique, à côté des noms des joueurs. »
///
/// Les parties montrées ici sont des fichiers de l'appareil — c'est le seul
/// historique qu'un aperçu peut remplir sans serveur. En vrai, une partie
/// classée est une partie EN LIGNE, et sa variation viendra du serveur ;
/// l'affichage, lui, est exactement celui-ci.
///
/// `flutter test tool/apercu_historique_melo.dart` écrit un PNG dans
/// `tool/apercus/`.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/game/nmc.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/local_games.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/history_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Key _cadre = Key('ecran');

/// Quatre parties : deux avec les deux variations, une avec la mienne seule
/// — ce que l'App sait aujourd'hui —, une sans, comme avant.
const List<(String, String, String, String, int?, int?)> _parties = [
  ('nino', 'celia', '1-0', 'fugue', 12, -12),
  ('mesange', 'nino', '1-0', 'mat', -9, 9),
  ('nino', 'Vem', '½-½', 'nulle', 0, null),
  ('nino', 'lilou', '0-1', 'abandon', null, null),
];

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('aperçu de l historique avec les mélos', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
      'theme': 'original',
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

    final dossier = Directory.systemTemp.createTempSync('apercu_hist');
    addTearDown(() => dossier.deleteSync(recursive: true));
    final store = LocalGamesStore(directory: dossier);
    var i = 0;
    for (final (j1, j2, resultat, methode, m1, m2) in _parties) {
      await store.save(
        NmcMeta(
          date: '2026-11-0${6 - i} 1$i:30',
          player1: j1,
          player2: j2,
          blanc: j1,
          objectif: 'partie',
          // Le serveur range la cadence en clair : « 5 », « 15 », « zen ».
          cadence: '5',
          result: resultat,
          method: methode,
          points: methode == 'nulle' ? '0' : '2',
          melo1: m1,
          melo2: m2,
        ),
        const ['Do1-Do2', 'Do8-Do7'],
        name: 'partie$i',
      );
      i++;
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: _cadre,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'NotoSansCJK'),
          home: HistoryScreen(
            online: OnlineService.instance,
            mode: HistoryMode.local,
            store: store,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Directory('tool/apercus').createSync(recursive: true);
    final limite =
        tester.renderObject(find.byKey(_cadre)) as RenderRepaintBoundary;
    final octets = await tester.runAsync(() async {
      final image = await limite.toImage(pixelRatio: 2);
      return image.toByteData(format: ui.ImageByteFormat.png);
    });
    File(
      'tool/apercus/historique_melo.png',
    ).writeAsBytesSync(Uint8List.view(octets!.buffer));
  });
}
