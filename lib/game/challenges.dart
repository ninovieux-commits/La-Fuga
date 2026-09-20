/// Défis en direct — portage de `_envoyer_defi` et des gestionnaires
/// `defi_*` du menu (main.py).
///
/// Un défi est un appariement choisi : on désigne l'adversaire au lieu de
/// laisser le matchmaking le trouver. Le serveur prévient la cible
/// (`defi_recu`) ; si elle accepte, la partie démarre par `partie_trouvee`,
/// exactement comme une partie trouvée au hasard.
library;

import '../net/socket_client.dart';

/// Un défi reçu.
final class IncomingChallenge {
  const IncomingChallenge({
    required this.id,
    required this.from,
    this.melo = 1500,
    this.objectif = 'partie',
    this.cadence = '15',
    this.random = false,
  });

  final String id;
  final String from;
  final int melo;
  final String objectif;
  final String cadence;
  final bool random;

  static IncomingChallenge fromEvent(Map<String, dynamic> d) =>
      IncomingChallenge(
        id: '${d['defi_id'] ?? ''}',
        from: '${d['defieur'] ?? ''}',
        melo: switch (d['defieur_melo']) {
          final int n => n,
          final num n => n.toInt(),
          _ => 1500,
        },
        objectif: '${d['objectif'] ?? 'partie'}',
        cadence: '${d['cadence'] ?? '15'}',
        random: d['random'] == true,
      );
}

/// Pourquoi un défi n'a pas abouti.
enum ChallengeFailure {
  /// On s'est défié soi-même.
  self,

  /// Un blocage est en place entre les deux joueurs.
  blocked,

  /// La cible n'est pas disponible (hors ligne).
  unavailable,
}

ChallengeFailure failureFromReason(String? reason) => switch (reason) {
  'soi_meme' => ChallengeFailure.self,
  'bloque' => ChallengeFailure.blocked,
  _ => ChallengeFailure.unavailable,
};

/// Envoi et réception des défis.
class ChallengeService {
  ChallengeService(this.socket);

  final ChallengeSocket socket;

  /// Identifiant du défi qu'on a envoyé et qui attend une réponse.
  String? _pendingId;

  String? get pendingId => _pendingId;

  /// Vrai tant qu'un défi envoyé attend sa réponse.
  bool get isWaiting => _waiting;
  bool _waiting = false;

  /// Abonne aux événements de défi. Chaque callback est facultatif.
  void bind({
    void Function(IncomingChallenge)? onReceived,
    void Function()? onSent,
    void Function(ChallengeFailure)? onFailed,
    void Function(String opponent)? onRefused,
    void Function()? onCancelled,
  }) {
    socket
      ..on(
        FugaEvents.defiRecu,
        (d) => onReceived?.call(IncomingChallenge.fromEvent(d)),
      )
      ..on(FugaEvents.defiEnvoye, (d) {
        // Le serveur confirme que le défi est parti : on retient son
        // identifiant, sans quoi on ne saurait pas quoi annuler.
        _pendingId = '${d['defi_id'] ?? ''}';
        onSent?.call();
      })
      ..on(FugaEvents.defiEchec, (d) {
        _clear();
        onFailed?.call(failureFromReason(d['raison'] as String?));
      })
      ..on(FugaEvents.defiRefuse, (d) {
        final opponent = '${d['cible'] ?? ''}';
        _clear();
        onRefused?.call(opponent);
      })
      ..on(FugaEvents.defiAnnule, (_) {
        _clear();
        onCancelled?.call();
      });
  }

  void unbind() {
    socket
      ..off(FugaEvents.defiRecu)
      ..off(FugaEvents.defiEnvoye)
      ..off(FugaEvents.defiEchec)
      ..off(FugaEvents.defiRefuse)
      ..off(FugaEvents.defiAnnule);
  }

  /// Défie un joueur, avec l'objectif et la cadence choisis.
  void challenge(
    String pseudo, {
    String objectif = 'partie',
    required String cadence,
    bool random = false,
  }) {
    _waiting = true;
    _pendingId = null;
    socket.defier(
      pseudoCible: pseudo,
      objectif: objectif,
      cadence: cadence,
      random: random,
    );
  }

  /// Annule le défi en attente. Sans identifiant confirmé, il n'y a rien à
  /// annuler côté serveur : on se contente d'arrêter d'attendre.
  void cancel() {
    final id = _pendingId;
    if (id != null && id.isNotEmpty) socket.annulerDefi(id);
    _clear();
  }

  /// Répond à un défi reçu.
  void respond(IncomingChallenge challenge, {required bool accept}) =>
      socket.repondreDefi(challenge.id, accept);

  void _clear() {
    _waiting = false;
    _pendingId = null;
  }
}
