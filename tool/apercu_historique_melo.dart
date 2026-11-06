/// Aperçu de l'historique EN LIGNE, mélos compris.
///
/// Nino : « il faut que les mélos gagnés et perdus durant une partie soient
/// spécifiés dans l'historique, à côté des noms des joueurs », puis
/// « ajoute aussi le mélo des joueurs tel que : mesange 1500 -9 vs nino
/// 1512 +9 ».
///
/// L'HISTORIQUE EN LIGNE, et pas celui de l'appareil : une partie classée
/// est une partie en ligne, c'est donc là qu'un mélo se lit. Nino, devant
/// la première version de cet aperçu : « c'est n'importe quoi que ton
/// aperçu montre l'historique local au lieu du en ligne. » Le serveur est
/// remplacé ici par un faux qui rend ce qu'il rendra le jour où il rangera
/// les quatre colonnes.
///
/// `flutter test tool/apercu_historique_melo.dart` écrit un PNG dans
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
import 'package:lafuga/state/local_games.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/history_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fake_realtime.dart';

const Key _cadre = Key('ecran');

/// Quatre parties : deux avec les deux classements, une avec le mien seul
/// — ce que l'App sait AUJOURD'HUI, le serveur n'annonçant que le mien —,
/// une sans rien, comme avant.
///
/// `(joueur1, joueur2, résultat, méthode, mélo1, var1, mélo2, var2)`. Le
/// joueur1 est le Blanc : c'est ainsi que l'archive d'une partie jouée
/// contre quelqu'un la range.
const List<(String, String, String, String, int?, int?, int?, int?)> _parties =
    [
      ('nino', 'celia', '1-0', 'fugue', 1512, 12, 1488, -12),
      // Nino gagne par mat : « 0-1 », le second nommé. Les mélos le
      // disent aussi, et les deux doivent se tenir.
      ('mesange', 'nino', '0-1', 'mat', 1500, -9, 1512, 9),
      ('nino', 'Vem', '½-½', 'nulle', 1503, 0, null, null),
      ('nino', 'lilou', '0-1', 'abandon', null, null, null, null),
    ];

/// Ce que `list_games` rendra.
List<Map<String, dynamic>> _lignesDuServeur() => [
  for (var i = 0; i < _parties.length; i++)
    () {
      final (j1, j2, resultat, methode, m1, v1, m2, v2) = _parties[i];
      return <String, dynamic>{
        'game_uid': 'online_g$i',
        'joueur1': j1,
        'joueur2': j2,
        'blanc': j1,
        'resultat': resultat,
        'methode': methode,
        'cadence': '5',
        'objectif': 'partie',
        // Le serveur date en secondes depuis l'époque.
        'played_at':
            DateTime(2026, 11, 6 - i, 10 + i, 30).millisecondsSinceEpoch ~/
            1000,
        if (m1 != null) 'melo1': m1,
        if (m2 != null) 'melo2': m2,
        if (v1 != null) 'variation1': v1,
        if (v2 != null) 'variation2': v2,
      };
    }(),
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

    // LE SERVEUR, EN FAUX. Il rend la liste comme il la rendra le jour où
    // il rangera les quatre colonnes de mélo.
    final client = MockClient((requete) async {
      final reponse = switch (requete.url.path) {
        '/login' => {'ok': true, 'token': 't', 'pseudo': 'nino', 'melo': 1512},
        '/list_games' => {'ok': true, 'games': _lignesDuServeur()},
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
      socketFactory: (_) => FakeRealtime(),
    );
    await online.login('nino', 'mdp');

    await tester.pumpWidget(
      RepaintBoundary(
        key: _cadre,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'NotoSansCJK'),
          home: HistoryScreen(
            online: online,
            mode: HistoryMode.online,
            store: LocalGamesStore(directory: dossier),
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
