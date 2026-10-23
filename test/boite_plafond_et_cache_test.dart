/// Une boîte pleine reste vivante, et une boîte déjà vue s'ouvre sans roue.
///
/// Nino : « j'aimerais que ça charge pas (mémoire cache) », et « même quand
/// la discussion est bien affichée, ça fait le bug du message le plus récent
/// qui n'apparaît pas en temps réel ».
///
/// LE SECOND A UNE CAUSE EXACTE, et c'est le serveur qui la donne : passé
/// 200 messages, il efface le plus ancien à chaque nouveau (`patch_plafond_
/// messages.py`). La boîte en garde donc 200 pour toujours — et la relecture
/// de l'écran, qui comparait les LONGUEURS, ne voyait plus jamais rien
/// arriver. Le patch serveur concluait « rien à changer dans l'application ».
/// C'était vrai partout, sauf ici.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/decors_connus.dart';
import 'package:lafuga/net/messages.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/messages_caches.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:lafuga/ui/widgets/message_bubble.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, Object>> surLeServeur;
  late int requetes;
  late OnlineService online;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    await MessagesCaches.oublie();
    DecorsConnus.clear();
    DecorsConnus.remember('toto', 'foret');

    requetes = 0;
    surLeServeur = [
      for (var i = 0; i < 200; i++) {'texte': 'message $i', 'de_moi': i.isEven},
    ];
    online = OnlineService(
      client: OnlineClient(
        api: ApiClient(
          client: MockClient((req) async {
            if (req.url.path.endsWith('/list_conversation')) requetes++;
            if (req.url.path.endsWith('/send_message')) {
              // Le plafond : un de plus, un de moins. La longueur ne bouge
              // PAS.
              surLeServeur
                ..removeAt(0)
                ..add({'texte': 'tout dernier', 'de_moi': true});
            }
            return http.Response(
              jsonEncode({
                'ok': true,
                'messages': surLeServeur,
                'description': 'd',
                'theme': 'foret',
                'photo': 'nurse',
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      ),
    );
  });

  Future<void> ouvrir(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ConversationScreen(online: online, pseudo: 'toto'),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> bulles(WidgetTester tester) => tester
      .widgetList<MessageBubble>(find.byType(MessageBubble))
      .map((b) => b.texte)
      .toList();

  testWidgets('une boîte PLEINE voit quand même arriver un message', (
    tester,
  ) async {
    await ouvrir(tester);
    expect(bulles(tester), isNot(contains('tout dernier')));

    // L'autre écrit. La longueur ne change pas — c'est tout le piège.
    surLeServeur
      ..removeAt(0)
      ..add({'texte': 'tout dernier', 'de_moi': false});
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(
      bulles(tester),
      contains('tout dernier'),
      reason: 'comparer les longueurs rendait la relecture aveugle à 200',
    );
  });

  testWidgets('mon propre message ne disparaît pas dans une boîte pleine', (
    tester,
  ) async {
    await ouvrir(tester);
    await tester.enterText(find.byType(TextField), 'tout dernier');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    // La relecture déclenchée par l'envoi, puis celle du filet.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(
      bulles(tester).where((t) => t == 'tout dernier').length,
      1,
      reason: 'il quittait les envois en vol sans entrer dans la liste',
    );
  });

  testWidgets('la deuxième ouverture n attend plus rien', (tester) async {
    await ouvrir(tester);
    expect(requetes, 1);
    expect(bulles(tester), isNotEmpty);

    // On referme, on rouvre : le cache doit tenir l'écran DÈS la première
    // image, avant toute réponse du serveur.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        home: ConversationScreen(online: online, pseudo: 'toto'),
      ),
    );
    await tester.pump();

    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: 'on sait déjà ce qu il y a dedans : rien à annoncer',
    );
    expect(bulles(tester), isNotEmpty);
    await tester.pumpAndSettle();
  });

  test('le cache garde le texte et le côté, et pas plus de 200', () async {
    await MessagesCaches.retiens('toto', [
      for (var i = 0; i < 250; i++) ChatMessage(text: 'm$i', fromMe: i.isEven),
    ]);
    final relus = MessagesCaches.connus('toto');
    expect(relus, hasLength(200));
    expect(relus.last.text, 'm249', reason: 'ce sont les DERNIERS qu on garde');
    expect(relus.last.fromMe, isFalse);
  });

  test('la déconnexion emporte les conversations gardées', () async {
    await MessagesCaches.retiens('toto', [
      const ChatMessage(text: 'salut', fromMe: true),
    ]);
    expect(MessagesCaches.connus('toto'), isNotEmpty);
    await MessagesCaches.oublie();
    expect(MessagesCaches.connus('toto'), isEmpty);
  });
}
