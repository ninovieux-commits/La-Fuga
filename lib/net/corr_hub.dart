/// Ce qui bouge en correspondance, en direct, pour toute l'application.
///
/// La correspondance n'avait aucun événement temps réel. Le serveur n'envoyait
/// que des notifications push — donc rien du tout à une application ouverte,
/// et rien non plus si le joueur avait coupé ses notifications. Les trois
/// écrans concernés n'avaient qu'un recours : redemander la liste toutes les
/// quatre secondes. Un coup pouvait donc mettre quatre secondes à apparaître,
/// et chaque écran ouvert interrogeait le serveur quinze fois par minute.
///
/// Un seul point d'écoute ici, comme pour les messages : le menu y prend ses
/// aperçus, la partie ouverte s'y réveille, et son chat aussi. Chacun
/// s'abonnant de son côté, la connexion ne gardant qu'un écouteur par
/// événement, ouvrir une partie aurait rendu le menu sourd.
library;

import 'dart:async';

import 'socket_client.dart';

/// Un changement en correspondance : ce qui a bougé, et dans quelle partie.
///
/// [gameId] est vide pour ce qui ne concerne pas une partie précise.
typedef CorrChange = ({String type, String gameId});

/// Les changements de correspondance au fil de l'eau.
class CorrHub {
  final StreamController<CorrChange> _changes =
      StreamController<CorrChange>.broadcast();

  /// À suivre pour se rafraîchir à l'instant où quelque chose bouge.
  Stream<CorrChange> get changes => _changes.stream;

  /// Les types qui concernent la correspondance.
  ///
  /// `message` n'en est pas : les messages privés ont leur propre chemin
  /// (`message_recu`, et [MessageHub] derrière). Le laisser passer ici
  /// ferait relire la liste des parties à chaque message reçu.
  static bool concerneCorresp(String type) =>
      type.startsWith('corr_') || type == 'defi_corr';

  RealtimeSocket? _socket;

  /// Écoute la connexion temps réel. Idempotent.
  void attach(RealtimeSocket? socket) {
    if (identical(socket, _socket)) return;
    detach();
    _socket = socket;
    socket?.on(FugaEvents.majDirecte, receive);
  }

  void detach() {
    _socket?.off(FugaEvents.majDirecte, receive);
    _socket = null;
  }

  /// Prend en compte un `maj_directe`.
  ///
  /// Seul point d'entrée : un test peut donc simuler un coup adverse sans
  /// serveur ni socket.
  void receive(Map<String, dynamic> data) {
    final type = '${data['type'] ?? ''}'.trim();
    if (!concerneCorresp(type)) return;
    _changes.add((type: type, gameId: '${data['game_id'] ?? ''}'.trim()));
  }

  void dispose() {
    detach();
    unawaited(_changes.close());
  }
}
