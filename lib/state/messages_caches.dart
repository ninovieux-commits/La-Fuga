/// Les derniers messages connus d'une conversation, gardés sur le téléphone.
///
/// Nino : « j'aimerais que ça charge pas (mémoire cache) ».
///
/// La boîte s'ouvrait sur une roue le temps d'un aller-retour au serveur,
/// alors qu'elle sait déjà, à peu de chose près, ce qu'elle va y trouver :
/// ce qu'elle affichait la dernière fois. Elle ouvre donc dessus, et la
/// relecture remplace ce qui a changé — sans que rien clignote, puisque
/// l'écran était déjà juste.
///
/// ## Dans les préférences, et pas dans un fichier
///
/// Les préférences sont DÉJÀ chargées au démarrage de l'application : leur
/// lecture est immédiate, sans attente ni `await`. C'est tout l'intérêt
/// ici — un cache qu'il faudrait aller lire sur le disque rendrait la
/// première image aussi lente que la requête qu'on évite.
///
/// ## Ce qu'on garde
///
/// Le texte et le côté, rien d'autre. Ni date, ni état d'envoi : le premier
/// ne s'affiche nulle part, le second n'appartient qu'à l'écran du moment.
/// Le serveur plafonne une boîte à 200 messages, donc le cache aussi — il ne
/// peut pas grossir plus que ce qu'on peut recevoir.
///
/// Les messages sont écrits en clair, comme toute messagerie garde les siens
/// sur l'appareil. Ils partent à la déconnexion, avec le reste.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../net/messages.dart';

/// Même plafond que le serveur : une boîte ne dépasse pas 200 messages.
const int kMessagesCachesMax = 200;

class MessagesCaches {
  MessagesCaches._();

  static SharedPreferences? _prefs;

  /// À appeler une fois au démarrage, avec les préférences déjà ouvertes.
  static void utilise(SharedPreferences prefs) => _prefs = prefs;

  static String _cle(String pseudo) => 'conv_${pseudo.trim().toLowerCase()}';

  /// Ce qu'on affichait la dernière fois. Vide si on ne sait rien.
  static List<ChatMessage> connus(String pseudo) {
    final brut = _prefs?.getString(_cle(pseudo));
    if (brut == null || brut.isEmpty) return const [];
    try {
      final lu = jsonDecode(brut);
      if (lu is! List) return const [];
      return [
        for (final m in lu)
          if (m is Map)
            ChatMessage(text: '${m['t'] ?? ''}', fromMe: m['m'] == true),
      ];
    } catch (_) {
      // Un cache illisible n'est pas une panne : on ouvre sur rien, et la
      // relecture remplit.
      return const [];
    }
  }

  /// Retient ce que le serveur vient de rendre.
  static Future<void> retiens(String pseudo, List<ChatMessage> messages) async {
    final prefs = _prefs;
    if (prefs == null || pseudo.trim().isEmpty) return;
    final garde = messages.length > kMessagesCachesMax
        ? messages.sublist(messages.length - kMessagesCachesMax)
        : messages;
    await prefs.setString(
      _cle(pseudo),
      jsonEncode([
        for (final m in garde) {'t': m.text, 'm': m.fromMe},
      ]),
    );
  }

  /// Oublie tout — à la déconnexion, et dans les tests.
  static Future<void> oublie() async {
    final prefs = _prefs;
    if (prefs == null) return;
    for (final cle in prefs.getKeys().where((k) => k.startsWith('conv_'))) {
      await prefs.remove(cle);
    }
  }
}
