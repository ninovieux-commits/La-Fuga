/// Aperçu d'une conversation : les dessins hors de leur bulle, et l'heure
/// qu'un appui fait paraître.
///
/// Ce fichier ne sert qu'à dessiner : il ne fait pas partie de
/// l'application. `flutter test tool/apercu_conversation.dart` écrit un PNG
/// dans `tool/apercus/`.
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
import 'package:lafuga/game/enveloppe.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/decors_connus.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:lafuga/ui/widgets/message_bubble.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GlobalKey _cadre = GlobalKey();

/// Quatre heures d'affilée, pour que les lignes ne se ressemblent pas.
int _quand(int rang) =>
    DateTime(2026, 11, 12, 10 + rang, 20 + rang).millisecondsSinceEpoch ~/ 1000;

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('aperçu de la conversation', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
      'theme': 'original',
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    DecorsConnus.remember('celia', 'medieval');

    await tester.runAsync(() async {
      // LES ÉMOJIS SONT DANS LA MÊME FAMILLE QUE LE TEXTE : chargés sous le
      // nom « Roboto », ils en deviennent le recours, et un smiley cesse
      // d'être un carré vide.
      final police = FontLoader('Roboto')
        ..addFont(
          File(
            '/opt/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
          ).readAsBytes().then((o) => ByteData.view(o.buffer)),
        )
        ..addFont(
          File(
            '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf',
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

    final online = OnlineService(
      client: OnlineClient(
        api: ApiClient(
          client: MockClient((request) async {
            final corps = request.url.path == '/get_profile'
                ? {'ok': true, 'theme': 'medieval'}
                : {
                    'ok': true,
                    'messages': [
                      {
                        'texte': 'Tu joues quand ?',
                        'de_moi': false,
                        'created_at': _quand(0),
                      },
                      {
                        'texte': '😀😀😀',
                        'de_moi': true,
                        'created_at': _quand(1),
                      },
                      {
                        'texte': '[Soldat] [Garde Noir] [Nurse]',
                        'de_moi': false,
                        'created_at': _quand(2),
                      },
                      {
                        'texte': '😀 [Soldat] 😄 [Garde Noir]',
                        'de_moi': true,
                        'created_at': _quand(3),
                      },
                      {
                        'texte': kJetonEnveloppe,
                        'de_moi': false,
                        'created_at': _quand(4),
                      },
                      {
                        'texte': 'À tout de suite !',
                        'de_moi': true,
                        'created_at': _quand(5),
                      },
                    ],
                  };
            return http.Response(
              jsonEncode(corps),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      ),
    );

    await tester.pumpWidget(
      RepaintBoundary(
        key: _cadre,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Roboto'),
          home: ConversationScreen(online: online, pseudo: 'celia'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final images = find.byType(Image).evaluate().toList();
    await tester.runAsync(() async {
      for (final e in images) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await tester.pumpAndSettle();

    Future<void> ecrit(String nom) async {
      Directory('tool/apercus').createSync(recursive: true);
      final limite =
          _cadre.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final octets = await tester.runAsync(() async {
        final image = await limite.toImage(pixelRatio: 2);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File(
        'tool/apercus/$nom.png',
      ).writeAsBytesSync(Uint8List.view(octets!.buffer));
    }

    await ecrit('conversation');

    // UN APPUI SUR LE MESSAGE MÊLÉ : son heure paraît sous lui.
    final mele = find.byWidgetPredicate(
      (w) => w is MessageBubble && w.texte.contains('[Soldat]') && w.deMoi,
    );
    await tester.tap(mele);
    await tester.pumpAndSettle();
    await ecrit('conversation_heure');
  });
}
