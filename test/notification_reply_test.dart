/// Répondre depuis la notification, comme les applis de messagerie.
///
/// L'application peut être fermée : Android réveille alors un isolate neuf,
/// sans session ni service en ligne. La réponse doit partir quand même — et,
/// si elle n'y arrive pas, le dire plutôt que de disparaître en silence.
library;

import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/net/notification_reply.dart';
import 'package:lafuga/net/push_notifications.dart';
import 'package:lafuga/state/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<({String path, Map<String, dynamic> body})> calls;

  /// Serveur simulé : retient ce qu'on lui envoie.
  http.Client serverThat({bool accepts = true}) {
    calls = [];
    return MockClient((request) async {
      calls.add((
        path: request.url.path,
        body: Map<String, dynamic>.from(jsonDecode(request.body) as Map),
      ));
      return http.Response(
        jsonEncode(accepts ? {'ok': true} : {'error': 'refusé'}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
  }

  Future<SharedPreferences> prefsWith({String token = 'jeton'}) async {
    SharedPreferences.setMockInitialValues({
      if (token.isNotEmpty) SettingsKeys.onlineToken: token,
    });
    return SharedPreferences.getInstance();
  }

  group('Le trajet aller de la réponse', () {
    test('elle part au serveur, avec la session lue sur l appareil', () async {
      final sent = await sendReplyFromNotification(
        pseudo: 'Ana',
        text: '  à toi de jouer  ',
        client: serverThat(),
        prefs: await prefsWith(),
      );

      expect(sent, isTrue);
      expect(calls.single.path, '/send_message');
      expect(calls.single.body, {
        'token': 'jeton',
        'pseudo': 'Ana',
        'text': 'à toi de jouer',
      });
    });

    test('sans compte ouvert, rien ne part', () async {
      final sent = await sendReplyFromNotification(
        pseudo: 'Ana',
        text: 'coucou',
        client: serverThat(),
        prefs: await prefsWith(token: ''),
      );
      expect(sent, isFalse);
      expect(calls, isEmpty);
    });

    test('une réponse vide ne part pas', () async {
      final sent = await sendReplyFromNotification(
        pseudo: 'Ana',
        text: '   ',
        client: serverThat(),
        prefs: await prefsWith(),
      );
      expect(sent, isFalse);
      expect(calls, isEmpty);
    });

    test('un refus du serveur se sait', () async {
      final sent = await sendReplyFromNotification(
        pseudo: 'Ana',
        text: 'coucou',
        client: serverThat(accepts: false),
        prefs: await prefsWith(),
      );
      expect(sent, isFalse, reason: 'de quoi prévenir le joueur');
    });
  });

  group('Ce que la notification emporte', () {
    test('le destinataire fait l aller-retour', () {
      expect(pseudoFromPayload(replyPayloadFor('Ana')), 'Ana');
    });

    test('un payload qui n est pas le nôtre ne dit rien', () {
      expect(pseudoFromPayload(null), isNull);
      expect(pseudoFromPayload(''), isNull);
      expect(pseudoFromPayload('pas du json'), isNull);
      expect(pseudoFromPayload(jsonEncode({'autre': 1})), isNull);
      expect(pseudoFromPayload(jsonEncode({'pseudo': '  '})), isNull);
    });
  });

  group('Qui a écrit', () {
    test('toutes les façons usuelles de le dire sont acceptées', () {
      for (final key in kSenderKeys) {
        expect(
          senderOf(RemoteMessage(data: {key: 'Ana'})),
          'Ana',
          reason: 'clé « $key »',
        );
      }
    });

    test('sans expéditeur, pas de champ de réponse', () {
      expect(senderOf(const RemoteMessage(data: {'body': 'coucou'})), isNull);
      // Et la notification se construit alors sans action.
      expect(PushNotifications.androidDetails(null).actions, isNull);
    });

    test('avec un expéditeur, la notification porte le champ', () {
      final actions = PushNotifications.androidDetails('Ana').actions;
      expect(actions, hasLength(1));
      expect(actions!.single.id, kReplyActionId);
      expect(actions.single.inputs, hasLength(1));
      expect(
        actions.single.cancelNotification,
        isTrue,
        reason: 'sans cela Android y laisse tourner un rouet',
      );
    });
  });
}
