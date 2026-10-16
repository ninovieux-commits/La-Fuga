/// Chacun ses couleurs.
///
/// Nino : « les bulles de l'adversaire restent à sa couleur, mais mes bulles
/// doivent être à ma couleur ! »
///
/// C'est la troisième fois que la question se pose, et les trois réponses
/// tiennent ensemble : le décor de la page est à lui (« on entre chez lui »),
/// ses bulles aussi (« que les bulles dépendent du thème de l'adversaire »),
/// mais ce que J'ÉCRIS reste à moi, d'une conversation à l'autre. Ce fichier
/// fige ce partage, aux deux endroits où des bulles paraissent.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/decors_connus.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:lafuga/ui/widgets/bulles_en_jeu.dart';
import 'package:lafuga/ui/widgets/message_bubble.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La palette que porte la bulle d'un côté donné.
ThemePalette? palettePortee(WidgetTester tester, {required bool deMoi}) {
  for (final b in tester.widgetList<MessageBubble>(
    find.byType(MessageBubble),
  )) {
    if (b.deMoi == deMoi) return b.palette;
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
      'theme': 'original',
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
  });
  tearDown(resetScale);

  // -------------------------------------------------------------------------
  // Sur le plateau
  // -------------------------------------------------------------------------

  group('dans le bandeau de la partie', () {
    late StreamController<BulleEnJeu> flux;

    Future<void> bande(WidgetTester tester, {ThemePalette? mienne}) async {
      flux = StreamController<BulleEnJeu>.broadcast();
      addTearDown(flux.close);
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 393,
              height: 851 * 12 / 104,
              child: BullesEnJeu(
                flux: flux.stream,
                // Le bandeau est le sien : son thème à lui.
                palette: paletteOf('foret'),
                mienne: mienne,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('ses mots à lui, les miens à moi', (tester) async {
      await bande(tester, mienne: paletteOf('original'));
      flux.add((texte: 'Et paf', deMoi: false));
      flux.add((texte: 'Bien vu', deMoi: true));
      await tester.pumpAndSettle();

      expect(
        palettePortee(tester, deMoi: false),
        paletteOf('foret'),
        reason: 'ses bulles doivent rester à sa couleur',
      );
      expect(
        palettePortee(tester, deMoi: true),
        paletteOf('original'),
        reason: 'les miennes sont à moi',
      );
    });

    testWidgets('sa couleur arrive jusqu au pixel', (tester) async {
      await bande(tester, mienne: paletteOf('original'));
      flux.add((texte: 'Et paf', deMoi: false));
      await tester.pumpAndSettle();

      final boite = tester.widget<Container>(
        find.descendant(
          of: find.byType(MessageBubble),
          matching: find.byType(Container),
        ),
      );
      expect(
        (boite.decoration! as BoxDecoration).color,
        paletteOf('foret').fonce,
        reason: 'la palette n est pas seulement rangée, elle est peinte',
      );
    });

    testWidgets('sans mes couleurs, les deux se confondent', (tester) async {
      // L'ancien comportement, et celui qu'il faut quand on ne connaît pas
      // encore le thème d'en face.
      await bande(tester);
      flux.add((texte: 'Bien vu', deMoi: true));
      await tester.pumpAndSettle();
      expect(palettePortee(tester, deMoi: true), paletteOf('foret'));
    });
  });

  // -------------------------------------------------------------------------
  // Dans la boîte de messages
  // -------------------------------------------------------------------------

  testWidgets('la conversation partage ses couleurs de la même façon', (
    tester,
  ) async {
    DecorsConnus.remember('toto', 'foret');
    final online = OnlineService(
      client: OnlineClient(
        api: ApiClient(
          client: MockClient(
            (request) async => http.Response(
              jsonEncode({
                'ok': true,
                'messages': [
                  {'texte': 'Et paf', 'de_moi': false},
                  {'texte': 'Bien vu', 'de_moi': true},
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ConversationScreen(online: online, pseudo: 'toto'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MessageBubble), findsNWidgets(2));
    expect(
      palettePortee(tester, deMoi: false),
      paletteOf('foret'),
      reason: 'on entre chez lui : ses mots portent ses couleurs',
    );
    expect(
      palettePortee(tester, deMoi: true),
      paletteOf('original'),
      reason: 'ce que j écris reste à moi',
    );
  });
}
