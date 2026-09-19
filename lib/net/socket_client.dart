/// Client Socket.IO du serveur La Fuga — portage de la partie temps réel de
/// `OnlineClient` (main.py).
///
/// Mêmes noms d'événements et mêmes charges utiles que le client Kivy :
/// `server.py` ne change pas.
library;

import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

/// Événements émis par le serveur, tels que le client Kivy les écoute.
abstract final class FugaEvents {
  static const String authOk = 'auth_ok';
  static const String authErreur = 'auth_erreur';
  static const String rechercheEnCours = 'recherche_en_cours';
  static const String partieTrouvee = 'partie_trouvee';
  static const String rechercheTimeout = 'recherche_timeout';
  static const String coupAdverse = 'coup_adverse';
  static const String partieTerminee = 'partie_terminee';
  static const String adversaireDeconnecte = 'adversaire_deconnecte';
  static const String adversaireRevenu = 'adversaire_revenu';
  static const String reprisePartie = 'reprise_partie';
  static const String etatPartie = 'etat_partie';
  static const String chatRecu = 'chat_recu';
  static const String messageRecu = 'message_recu';
  static const String nulleProposee = 'nulle_proposee';
  static const String meloMaj = 'melo_maj';
  static const String adversairePret = 'adversaire_pret';
  static const String matchContinue = 'match_continue';
  static const String matchOver = 'match_over';
  static const String matchAbandonne = 'match_abandonne';
  static const String defiRecu = 'defi_recu';
  static const String defiEnvoye = 'defi_envoye';
  static const String defiEchec = 'defi_echec';
  static const String defiRefuse = 'defi_refuse';
  static const String defiAnnule = 'defi_annule';

  /// Tous les événements écoutés, dans l'ordre du client Kivy.
  static const List<String> all = [
    authOk,
    authErreur,
    rechercheEnCours,
    partieTrouvee,
    rechercheTimeout,
    coupAdverse,
    partieTerminee,
    adversaireDeconnecte,
    chatRecu,
    messageRecu,
    nulleProposee,
    meloMaj,
    adversaireRevenu,
    reprisePartie,
    etatPartie,
    adversairePret,
    matchContinue,
    matchOver,
    matchAbandonne,
    defiRecu,
    defiEnvoye,
    defiEchec,
    defiRefuse,
    defiAnnule,
  ];
}

/// Ce qu'une partie attend de sa connexion temps réel.
///
/// Extrait en interface pour qu'une partie en ligne se teste sans serveur :
/// c'est précisément la couche la plus pénible à déboguer en production.
abstract interface class GameSocket {
  /// Abonne un callback à un événement serveur.
  void on(String event, void Function(Map<String, dynamic>) handler);

  /// Retire l'abonnement à un événement.
  void off(String event);

  /// Transmet un coup à l'adversaire.
  void jouerCoup({
    required String gameId,
    required String notation,
    int? clockBlanc,
    int? clockNoir,
    int? clockMe,
  });

  /// Propose la nulle.
  void proposerNulle(String gameId);

  /// Signale la fin d'une partie. [loserColor] nul = nulle.
  void finPartie({
    required String gameId,
    required String methode,
    String? loserColor,
  });

  /// Envoie un message dans le chat de la partie.
  void chat(String gameId, String texte);

  /// Signale qu'on est prêt pour la partie suivante du match.
  void pretPartieSuivante(String gameId);

  /// Abandonne le match en cours.
  void abandonnerMatch(String gameId);
}

/// Connexion temps réel : matchmaking, défis et parties.
class FugaSocket implements GameSocket {
  FugaSocket({required this.serverUrl});

  final String serverUrl;

  io.Socket? _socket;
  String? _token;

  final Map<String, void Function(Map<String, dynamic>)> _handlers = {};
  final StreamController<bool> _connectionState =
      StreamController<bool>.broadcast();

  /// État de la connexion, pour afficher un indicateur à l'écran.
  Stream<bool> get onConnectionChanged => _connectionState.stream;

  bool get isConnected => _socket?.connected ?? false;

  /// Abonne un callback à un événement serveur. Un seul par événement, comme
  /// en Kivy.
  @override
  void on(String event, void Function(Map<String, dynamic>) handler) {
    _handlers[event] = handler;
  }

  @override
  void off(String event) => _handlers.remove(event);

  /// Se connecte et s'authentifie.
  ///
  /// La reconnexion est automatique et illimitée : sur mobile, les coupures
  /// sont la norme. **À chaque (re)connexion, `auth` est réémis** — sans cela
  /// le serveur ne réassocie pas le nouveau socket au compte ni à la partie en
  /// cours, l'adversaire nous voit déconnecté et les coups se perdent.
  Future<void> connect(String token) async {
    _token = token;
    if (_socket != null) {
      if (!_socket!.connected) _socket!.connect();
      return;
    }

    final socket = io.io(
      serverUrl,
      io.OptionBuilder()
          // On laisse négocier polling puis montée en websocket : forcer un
          // seul transport échouait sur certains réseaux mobiles.
          .setTransports(['polling', 'websocket'])
          .enableReconnection()
          .setReconnectionAttempts(1 << 30)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(10000)
          .disableAutoConnect()
          .build(),
    );

    socket.onConnect((_) {
      _connectionState.add(true);
      final t = _token;
      if (t != null) socket.emit('auth', {'token': t});
    });
    socket.onDisconnect((_) => _connectionState.add(false));

    for (final event in FugaEvents.all) {
      socket.on(event, (data) {
        final handler = _handlers[event];
        if (handler == null) return;
        handler(data is Map ? Map<String, dynamic>.from(data) : {});
      });
    }

    _socket = socket;
    socket.connect();
  }

  void _emit(String event, [Map<String, dynamic> data = const {}]) =>
      _socket?.emit(event, data);

  // ── Matchmaking ───────────────────────────────────────────────────────────

  void chercherPartie({
    required String objectif,
    required String cadence,
    bool random = false,
  }) => _emit('chercher_partie', {
    'objectif': objectif,
    'cadence': cadence,
    'random': random,
  });

  void annulerRecherche() => _emit('annuler_recherche');

  // ── Défis ─────────────────────────────────────────────────────────────────

  void defier({
    required String pseudoCible,
    required String objectif,
    required String cadence,
    bool random = false,
  }) => _emit('defier', {
    'pseudo_cible': pseudoCible,
    'objectif': objectif,
    'cadence': cadence,
    'random': random,
  });

  void annulerDefi(String defiId) => _emit('annuler_defi', {'defi_id': defiId});

  void repondreDefi(String defiId, bool accepte) =>
      _emit('repondre_defi', {'defi_id': defiId, 'accepte': accepte});

  // ── Partie en cours ───────────────────────────────────────────────────────

  /// Transmet un coup à l'adversaire.
  ///
  /// ⚠️ Le client Kivy envoie `clock_blanc` / `clock_noir`, mais `server.py`
  /// lit **`clock_me`** et relaie `coup_adverse {clock_adverse}`. La synchro
  /// d'horloge est donc inopérante dans l'app actuelle : `clock_adverse` vaut
  /// toujours `null`. On envoie ici les **trois** clés : `clock_me` fait
  /// fonctionner la synchro sans toucher au serveur, les deux autres gardent
  /// la compatibilité avec un client Kivy à l'autre bout.
  @override
  void jouerCoup({
    required String gameId,
    required String notation,
    int? clockBlanc,
    int? clockNoir,
    int? clockMe,
  }) => _emit('jouer_coup', {
    'game_id': gameId,
    'notation': notation,
    'clock_blanc': clockBlanc,
    'clock_noir': clockNoir,
    'clock_me': clockMe,
  });

  @override
  void proposerNulle(String gameId) =>
      _emit('proposer_nulle', {'game_id': gameId});

  /// Signale la fin d'une partie. `loserColor` nul = nulle.
  @override
  void finPartie({
    required String gameId,
    required String methode,
    String? loserColor,
  }) => _emit('fin_partie', {
    'game_id': gameId,
    'methode': methode,
    'loser_color': loserColor,
  });

  @override
  void chat(String gameId, String texte) =>
      _emit('chat', {'game_id': gameId, 'texte': texte});

  /// Envoie l'état complet à un adversaire qui vient de se reconnecter.
  void envoyerEtat(String gameId, Map<String, dynamic> etat) =>
      _emit('envoyer_etat', {'game_id': gameId, ...etat});

  @override
  void pretPartieSuivante(String gameId) =>
      _emit('pret_partie_suivante', {'game_id': gameId});

  @override
  void abandonnerMatch(String gameId) =>
      _emit('abandonner_match', {'game_id': gameId});

  void disconnect() {
    _socket?.disconnect();
    _connectionState.add(false);
  }

  void dispose() {
    _handlers.clear();
    _socket?.dispose();
    _socket = null;
    _connectionState.close();
  }
}
