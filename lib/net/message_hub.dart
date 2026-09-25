/// Les messages privés, en direct, pour toute l'application.
///
/// Un seul point d'écoute : le menu y prend sa pastille, l'écran de partie la
/// sienne, et la conversation ouverte y prend les messages à afficher. Chacun
/// s'abonnait auparavant à `message_recu` de son côté — et comme la connexion
/// ne gardait qu'un écouteur par événement, ouvrir la boîte rendait le menu
/// sourd et la refermer coupait tout le monde. Il fallait quitter l'écran et y
/// revenir pour voir un message arriver.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'messages.dart';
import 'online_client.dart';
import 'socket_client.dart';

/// Un message qui vient d'arriver.
typedef IncomingMessage = ({String from, String text});

/// Ce que l'application sait des messages non lus, à l'instant.
class MessageHub extends ChangeNotifier {
  /// Non-lus par correspondant.
  final Map<String, int> _unread = {};

  final StreamController<IncomingMessage> _incoming =
      StreamController<IncomingMessage>.broadcast();

  /// Les messages au fil de l'eau — ce que suit une conversation ouverte.
  Stream<IncomingMessage> get incoming => _incoming.stream;

  /// Nombre total de messages non lus.
  int get total => _unread.values.fold(0, (a, b) => a + b);

  bool get hasUnread => _unread.values.any((n) => n > 0);

  int unreadFrom(String? pseudo) => pseudo == null ? 0 : (_unread[pseudo] ?? 0);

  /// Y a-t-il un message non lu de cette personne ? C'est la question que
  /// pose l'écran de partie : sa pastille ne s'allume que pour l'adversaire.
  bool hasUnreadFrom(String? pseudo) => unreadFrom(pseudo) > 0;

  RealtimeSocket? _socket;

  /// Écoute la connexion temps réel. Idempotent.
  void attach(RealtimeSocket? socket) {
    if (identical(socket, _socket)) return;
    detach();
    _socket = socket;
    socket?.on(FugaEvents.messageRecu, receive);
  }

  void detach() {
    _socket?.off(FugaEvents.messageRecu, receive);
    _socket = null;
  }

  /// Prend en compte un `message_recu`.
  ///
  /// C'est ce que la connexion appelle, et le seul point d'entrée : un test
  /// peut donc simuler un message sans serveur ni socket.
  void receive(Map<String, dynamic> data) {
    final from = '${data['de'] ?? ''}'.trim();
    if (from.isEmpty) return;
    _unread[from] = (_unread[from] ?? 0) + 1;
    _incoming.add((from: from, text: '${data['texte'] ?? ''}'));
    notifyListeners();
  }

  /// Relit les non-lus auprès du serveur.
  ///
  /// À l'ouverture et au retour au premier plan : un message reçu pendant que
  /// l'application dormait n'est passé par aucun événement.
  Future<void> refresh(OnlineClient client) async {
    if (!client.isLoggedIn) {
      clear();
      return;
    }
    final r = await client.listConversations();
    if (!r.isOk) return;
    final rows = r.get<List<dynamic>>('conversations') ?? const [];
    final fresh = <String, int>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final c = Conversation.fromJson(Map<String, dynamic>.from(row));
      if (c.unread > 0) fresh[c.pseudo] = c.unread;
    }
    if (mapEquals(fresh, _unread)) return;
    _unread
      ..clear()
      ..addAll(fresh);
    notifyListeners();
  }

  /// La conversation avec [pseudo] vient d'être lue.
  void markRead(String pseudo) {
    if (_unread.remove(pseudo) == null) return;
    notifyListeners();
  }

  /// Plus de compte ouvert : plus rien à signaler.
  void clear() {
    if (_unread.isEmpty) return;
    _unread.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    detach();
    unawaited(_incoming.close());
    super.dispose();
  }
}
