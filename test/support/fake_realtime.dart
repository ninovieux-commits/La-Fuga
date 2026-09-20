/// Connexion temps réel simulée, partagée par les tests du menu.
library;

import 'dart:async';

import 'package:lafuga/net/socket_client.dart';

final class FakeRealtime implements RealtimeSocket {
  final Map<String, void Function(Map<String, dynamic>)> handlers = {};
  final List<({String name, Map<String, dynamic> data})> sent = [];
  final StreamController<bool> _state = StreamController<bool>.broadcast();

  @override
  bool isConnected = true;

  @override
  Stream<bool> get onConnectionChanged => _state.stream;

  void emit(String event, Map<String, dynamic> data) =>
      handlers[event]?.call(data);

  bool didSend(String name) => sent.any((e) => e.name == name);

  Map<String, dynamic>? lastOf(String name) {
    for (final e in sent.reversed) {
      if (e.name == name) return e.data;
    }
    return null;
  }

  void _record(String name, [Map<String, dynamic> data = const {}]) =>
      sent.add((name: name, data: data));

  @override
  void on(String event, void Function(Map<String, dynamic>) handler) =>
      handlers[event] = handler;

  @override
  void off(String event) => handlers.remove(event);

  @override
  Future<void> connect(String token) async => isConnected = true;

  @override
  void disconnect() => isConnected = false;

  @override
  void dispose() => _state.close();

  @override
  void chercherPartie({
    required String objectif,
    required String cadence,
    bool random = false,
  }) => _record('chercher_partie', {
    'objectif': objectif,
    'cadence': cadence,
    'random': random,
  });

  @override
  void annulerRecherche() => _record('annuler_recherche');

  @override
  void defier({
    required String pseudoCible,
    required String objectif,
    required String cadence,
    bool random = false,
  }) => _record('defier', {
    'pseudo_cible': pseudoCible,
    'objectif': objectif,
    'cadence': cadence,
    'random': random,
  });

  @override
  void annulerDefi(String defiId) =>
      _record('annuler_defi', {'defi_id': defiId});

  @override
  void repondreDefi(String defiId, bool accepte) =>
      _record('repondre_defi', {'defi_id': defiId, 'accepte': accepte});

  @override
  void jouerCoup({
    required String gameId,
    required String notation,
    int? clockBlanc,
    int? clockNoir,
    int? clockMe,
  }) => _record('jouer_coup');

  @override
  void proposerNulle(String gameId) => _record('proposer_nulle');

  @override
  void finPartie({
    required String gameId,
    required String methode,
    String? loserColor,
  }) => _record('fin_partie');

  @override
  void chat(String gameId, String texte) => _record('chat');

  @override
  void pretPartieSuivante(String gameId) => _record('pret_partie_suivante');

  @override
  void abandonnerMatch(String gameId) => _record('abandonner_match');
}
