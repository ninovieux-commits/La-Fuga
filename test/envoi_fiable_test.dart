/// Un message que j'envoie ne doit ni disparaître, ni paraître deux fois.
///
/// Nino : « je reçois tous les messages de ma femme instantanément mais
/// certains de mes messages se perdent ou sont ralentis, et ne s'affichent
/// pas sur la partie. »
///
/// Deux défauts distincts tenaient là-dedans :
///
///   1. la relecture de sécurité remplace la liste des messages par celle du
///      serveur toutes les quatre secondes. Un message parti depuis moins de
///      quatre secondes n'y est pas encore : il disparaissait de l'écran, et
///      la réponse d'envoi écrivait ensuite dans un indice périmé.
///   2. la bande de la partie ne voyait que les messages écrits DEPUIS le
///      plateau. Un mot tapé dans la boîte de messages n'y paraissait jamais.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/message_hub.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:lafuga/ui/widgets/message_bubble.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un serveur de messagerie en réduction : il range ce qu'on lui envoie, et
/// le rend à qui le demande. On peut retenir sa réponse pour jouer la lenteur.
class FauxServeur {
  final List<Map<String, Object>> messages = [
    {'texte': 'coucou', 'de_moi': false},
  ];

  /// Quand il est posé, `/send_message` attend ce jeton pour répondre.
  Completer<void>? retient;

  /// Le prochain envoi échoue.
  bool refuse = false;

  int envois = 0;

  http.Client get client => MockClient((request) async {
    final json = jsonDecode(request.body) as Map<String, dynamic>;
    if (request.url.path.endsWith('/send_message')) {
      envois++;
      await retient?.future;
      if (refuse) {
        return http.Response(
          jsonEncode({'ok': false, 'error': 'refusé'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      messages.add({'texte': '${json['text']}', 'de_moi': true});
      return http.Response(
        jsonEncode({'ok': true}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    return http.Response(
      jsonEncode({'ok': true, 'messages': messages}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

List<String> bullesAffichees(WidgetTester tester) => tester
    .widgetList<MessageBubble>(find.byType(MessageBubble))
    .map((b) => b.texte)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FauxServeur serveur;
  late OnlineService online;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    serveur = FauxServeur();
    online = OnlineService(
      client: OnlineClient(api: ApiClient(client: serveur.client)),
    );
  });

  Future<void> ouvre(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ConversationScreen(online: online, pseudo: 'toto'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ecris(WidgetTester tester, String texte) async {
    await tester.enterText(find.byType(TextField), texte);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
  }

  testWidgets('un envoi lent survit à la relecture qui passe au milieu', (
    tester,
  ) async {
    serveur.retient = Completer<void>();
    await ouvre(tester);
    await ecris(tester, 'je suis là');
    expect(bullesAffichees(tester), ['coucou', 'je suis là']);

    // La relecture de sécurité passe pendant que l'envoi est en l'air. Elle
    // rapporte la liste du serveur, qui ne connaît pas encore mon message.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(
      bullesAffichees(tester),
      ['coucou', 'je suis là'],
      reason: 'mon message ne doit pas disparaître le temps du voyage',
    );

    // Le serveur répond enfin.
    serveur.retient!.complete();
    await tester.pumpAndSettle();
    expect(bullesAffichees(tester), [
      'coucou',
      'je suis là',
    ], reason: 'il revient UNE fois, pas deux');
  });

  testWidgets('la relecture suivante ne le dédouble pas', (tester) async {
    await ouvre(tester);
    await ecris(tester, 'je suis là');
    await tester.pumpAndSettle();
    // Deux relectures de plus, de quoi faire paraître un doublon s'il y en a.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(bullesAffichees(tester), ['coucou', 'je suis là']);
    expect(serveur.envois, 1, reason: 'un envoi, pas deux');
  });

  testWidgets('deux fois le même mot font deux bulles', (tester) async {
    await ouvre(tester);
    await ecris(tester, 'ok');
    await tester.pumpAndSettle();
    await ecris(tester, 'ok');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(bullesAffichees(tester), ['coucou', 'ok', 'ok']);
  });

  testWidgets('un envoi refusé reste à l écran, et le dit', (tester) async {
    serveur.refuse = true;
    await ouvre(tester);
    await ecris(tester, 'je suis là');
    await tester.pumpAndSettle();
    expect(
      bullesAffichees(tester),
      ['coucou', 'je suis là'],
      reason: 'un message perdu en silence est pire que pas de message',
    );
    final echouee = tester
        .widgetList<MessageBubble>(find.byType(MessageBubble))
        .firstWhere((b) => b.texte == 'je suis là');
    expect(echouee.echoue, isTrue);

    // Et il résiste aux relectures : il n'est pas sur le serveur, mais il
    // doit rester sous mes yeux.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(bullesAffichees(tester), ['coucou', 'je suis là']);
  });

  testWidgets('ce que j écris est annoncé à toute l application', (
    tester,
  ) async {
    final vus = <OutgoingMessage>[];
    final ecoute = online.messages.outgoing.listen(vus.add);
    addTearDown(ecoute.cancel);

    await ouvre(tester);
    await ecris(tester, 'je suis là');
    await tester.pump();

    expect(vus, [
      (to: 'toto', text: 'je suis là'),
    ], reason: 'sans cette annonce, la partie ouverte dessous ne verrait rien');
  });

  test('la boîte aux lettres ne crie pas dans le vide', () {
    final hub = MessageHub();
    final vus = <OutgoingMessage>[];
    final ecoute = hub.outgoing.listen(vus.add);
    hub
      ..noteEnvoi('toto', 'salut')
      ..noteEnvoi('', 'sans destinataire')
      ..noteEnvoi('toto', '');
    return Future<void>.delayed(Duration.zero, () {
      expect(vus, [(to: 'toto', text: 'salut')]);
      ecoute.cancel();
      hub.dispose();
    });
  });
}
