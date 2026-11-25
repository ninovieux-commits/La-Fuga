/// Aperçus des quatre nouveautés : défier d'où qu'on soit, et écrire à qui
/// n'est pas dans ses favoris.
///
/// Nino : « tous les boutons défier doivent lancer un popup avec [direct] et
/// [correspondance] […] sur le profil, ajoute d'une ligne : "actions :
/// [défier] [message]" […] sur le popup fiche joueur, ajout d'une touche
/// "[message]" […] dans les boîtes de messages, ajout d'une touche
/// "[nouveau]" qui ouvre un popup avec tous les favoris. »
///
/// Ce fichier ne sert qu'à dessiner : il ne fait pas partie de
/// l'application. On le lance avec `flutter test tool/apercu_defier_ecrire
/// .dart`, il écrit ses PNG dans `tool/apercus/`.
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
import 'package:lafuga/game/defi_relais.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/theme_fuga.dart';
import 'package:lafuga/ui/screens/account_screen.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:lafuga/ui/widgets/player_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Size _ecran = Size(393, 851);
final GlobalKey _cadre = GlobalKey();

/// Les réponses du serveur simulé, par route.
final Map<String, Map<String, dynamic>> _reponses = {
  '/login': {'ok': true, 'token': 't', 'pseudo': 'nino', 'melo': 1567},
  '/get_profile': {
    'ok': true,
    'pseudo': 'mesange',
    'is_self': false,
    'melo': 1500,
    'melo_random': 1500,
    'photo': 'dragon|Nurse',
    'description': 'prout',
    'followers': [
      {'pseudo': '_antonio_de_la_vega_', 'melo': 1500, 'online': false},
      {'pseudo': 'celia', 'melo': 1395, 'online': false},
      {'pseudo': 'nino', 'melo': 1567, 'online': true},
    ],
    'following': [
      {'pseudo': 'nino', 'melo': 1567, 'online': true},
    ],
    'blocked': <Map<String, dynamic>>[],
    'h2h_direct_moi': 0,
    'h2h_direct_lui': 0,
    'h2h_corr_moi': 35,
    'h2h_corr_lui': 4,
  },
  '/list_favorites': {
    'ok': true,
    'favorites': [
      {'pseudo': 'celia', 'melo': 1395, 'online': true},
      {'pseudo': 'lilou', 'melo': 1491, 'online': false},
      {'pseudo': 'Maeva', 'melo': 1500, 'online': false},
      {'pseudo': 'mesange', 'melo': 1500, 'online': true},
      {'pseudo': 'Vem', 'melo': 1500, 'online': false},
    ],
  },
  '/list_conversations': {
    'ok': true,
    'conversations': [
      {
        'pseudo': 'mesange',
        'last_text': "j'ai jamais dit que ça devait l'être",
        'last_from_me': false,
        'unread': 0,
      },
      {
        'pseudo': 'celia',
        'last_text': 'caca',
        'last_from_me': false,
        'unread': 0,
      },
      {
        'pseudo': 'Maeva',
        'last_text': "ça va j'suis rassuré",
        'last_from_me': true,
        'unread': 0,
      },
    ],
  },
};

OnlineService _service() => OnlineService(
  client: OnlineClient(
    api: ApiClient(
      client: MockClient(
        (r) async => http.Response(
          jsonEncode(_reponses[r.url.path] ?? {'ok': true}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OnlineService online;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
      'theme': 'original',
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(_ecran);
    online = _service();
    await online.client.login('nino', 'mdp');
    OnlineService.instance = online;
    // Le menu est censé être à l'écoute sous l'écran : sans lui, les touches
    // « Défier » pâliraient et l'aperçu ne montrerait rien.
    DefiRelais.pose((_) async {}, correspondance: (_) async {});
    addTearDown(DefiRelais.oublie);
  });

  /// Pose l'écran, charge la police et les images, et rend le cadre à
  /// photographier.
  Future<void> pose(WidgetTester tester, Widget ecran) async {
    tester.view.physicalSize = _ecran;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Sans cela le texte sort en rectangles noirs : la police des tests n'a
    // pas de glyphes. DANS `runAsync` : hors de lui, le temps du test est
    // faux et la lecture du fichier ne se termine jamais.
    await tester.runAsync(() async {
      final police = FontLoader('Roboto')
        ..addFont(
          File(
            '/opt/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
          ).readAsBytes().then((o) => ByteData.view(o.buffer)),
        );
      await police.load();
      // ET CELLE DE L'APPLICATION : le thème la nomme, et sans elle tout
      // sort en rectangles blancs.
      final sienne = FontLoader('NotoSansCJK')
        ..addFont(
          File(
            'assets/fonts/NotoSansCJKsc-Regular.otf',
          ).readAsBytes().then((o) => ByteData.view(o.buffer)),
        );
      await sienne.load();
    });

    await tester.pumpWidget(
      RepaintBoundary(
        key: _cadre,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          // LE VRAI THÈME DE L'APPLICATION : sans lui, l'aperçu montrerait
          // les couleurs d'usine de Material et ne prouverait rien.
          theme: themeFuga(),
          home: ecran,
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
  }

  Future<void> photographie(WidgetTester tester, String nom) async {
    final limite =
        _cadre.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await tester.runAsync(() => limite.toImage(pixelRatio: 2));
    final octets = await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.png),
    );
    Directory('tool/apercus').createSync(recursive: true);
    File(
      'tool/apercus/$nom.png',
    ).writeAsBytesSync(Uint8List.view(octets!.buffer));
  }

  testWidgets('le profil, sa ligne d actions, et le choix du défi', (
    tester,
  ) async {
    await pose(tester, AccountScreen(online: online, pseudo: 'mesange'));
    await tester.scrollUntilVisible(find.text(T('Actions :')), 60);
    await tester.pumpAndSettle();
    await photographie(tester, 'profil_actions');

    await tester.tap(find.text(T('Défier')));
    await tester.pumpAndSettle();
    await photographie(tester, 'popup_defi');
  });

  testWidgets('la fiche du joueur et sa touche « Message »', (tester) async {
    await pose(
      tester,
      Builder(
        builder: (context) => Scaffold(
          backgroundColor: paletteOf('original').menu,
          body: Center(
            child: TextButton(
              onPressed: () => showPlayerCard(
                context,
                online: online,
                palette: paletteOf('original'),
                pseudo: 'mesange',
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    await photographie(tester, 'fiche_message');
  });

  testWidgets('la liste des messages et sa touche « Nouveau »', (tester) async {
    await pose(tester, ConversationsScreen(online: online));
    await photographie(tester, 'messages_nouveau');

    await tester.tap(find.text(T('Nouveau')));
    await tester.pumpAndSettle();
    await photographie(tester, 'messages_popup_favoris');
  });
}
