/// Répondre à un message depuis la notification, sans ouvrir l'application.
///
/// C'est la « réponse directe » d'Android : la notification porte un champ de
/// saisie, et le texte tapé revient à l'application — qui peut être en
/// arrière-plan, ou même fermée. Dans ce dernier cas Android réveille un
/// isolate neuf, sans rien de l'application en cours : ni session, ni service
/// en ligne, ni réglages chargés. La réponse part donc d'ici, avec le strict
/// nécessaire lu dans les préférences.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../state/settings.dart';
import 'api_client.dart';

/// Identifiant de l'action « Répondre » de la notification.
const String kReplyActionId = 'lafuga_repondre';

/// Identifiant du champ de saisie de cette action.
const String kReplyInputId = 'lafuga_reponse';

/// Ce qu'une notification de message emporte avec elle : à qui répondre.
///
/// Sérialisé en JSON dans le `payload` de la notification — c'est tout ce qui
/// traverse jusqu'à l'isolate qui traitera la réponse.
String replyPayloadFor(String pseudo) => jsonEncode({'pseudo': pseudo});

/// Relit un payload. `null` si ce n'est pas une notification de message.
String? pseudoFromPayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return null;
    final pseudo = '${decoded['pseudo'] ?? ''}'.trim();
    return pseudo.isEmpty ? null : pseudo;
  } catch (_) {
    return null;
  }
}

/// Envoie la réponse tapée dans la notification.
///
/// Rend `true` si le serveur l'a acceptée. Ne lève jamais : une réponse qui
/// n'arrive pas se signale, elle ne fait pas tomber le processus.
Future<bool> sendReplyFromNotification({
  required String pseudo,
  required String text,
  http.Client? client,
  SharedPreferences? prefs,
}) async {
  final body = text.trim();
  if (pseudo.isEmpty || body.isEmpty) return false;

  final store = prefs ?? await SharedPreferences.getInstance();
  final token = store.getString(SettingsKeys.onlineToken) ?? '';
  if (token.isEmpty) return false;
  final serverUrl =
      store.getString(SettingsKeys.serverUrl) ?? kDefaultServerUrl;

  final api = ApiClient(client: client, serverUrl: serverUrl);
  try {
    final r = await api.post('/send_message', {
      'token': token,
      'pseudo': pseudo,
      'text': body,
    });
    return r.isOk;
  } finally {
    // Le client fourni appartient à l'appelant ; celui qu'on a créé, non.
    if (client == null) api.close();
  }
}
