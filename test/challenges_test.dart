/// Défis en direct : envoi, annulation, refus, et défi reçu.
library;

import 'package:lafuga/game/challenges.dart';
import 'package:lafuga/net/socket_client.dart';
import 'package:test/test.dart';

/// Connexion simulée : on relit ce qui est parti, et on rejoue ce que le
/// serveur enverrait.
final class _FakeSocket implements ChallengeSocket {
  final SocketListeners handlers = SocketListeners();
  final List<({String name, Map<String, dynamic> data})> sent = [];

  @override
  void on(String event, SocketHandler handler) => handlers.add(event, handler);

  @override
  void off(String event, [SocketHandler? handler]) =>
      handlers.remove(event, handler);

  void emit(String event, Map<String, dynamic> data) =>
      handlers.dispatch(event, data);

  Map<String, dynamic>? lastOf(String name) {
    for (final e in sent.reversed) {
      if (e.name == name) return e.data;
    }
    return null;
  }

  bool didSend(String name) => sent.any((e) => e.name == name);

  @override
  void defier({
    required String pseudoCible,
    required String objectif,
    required String cadence,
    bool random = false,
  }) => sent.add((
    name: 'defier',
    data: {
      'pseudo_cible': pseudoCible,
      'objectif': objectif,
      'cadence': cadence,
      'random': random,
    },
  ));

  @override
  void annulerDefi(String defiId) =>
      sent.add((name: 'annuler_defi', data: {'defi_id': defiId}));

  @override
  void repondreDefi(String defiId, bool accepte) => sent.add((
    name: 'repondre_defi',
    data: {'defi_id': defiId, 'accepte': accepte},
  ));
}

void main() {
  late _FakeSocket socket;
  late ChallengeService challenges;

  setUp(() {
    socket = _FakeSocket();
    challenges = ChallengeService(socket);
  });

  group('Envoyer un défi', () {
    test('le défi part avec l objectif et la cadence choisis', () {
      challenges.challenge(
        'Ana',
        objectif: '5',
        cadence: '10min',
        random: true,
      );

      expect(socket.lastOf('defier'), {
        'pseudo_cible': 'Ana',
        'objectif': '5',
        'cadence': '10min',
        'random': true,
      });
      expect(challenges.isWaiting, isTrue);
    });

    test('le serveur confirme et donne l identifiant du défi', () {
      challenges.bind();
      challenges.challenge('Ana', cadence: '5min');
      expect(challenges.pendingId, isNull, reason: 'pas encore confirmé');

      socket.emit(FugaEvents.defiEnvoye, {'defi_id': 'd42'});

      expect(challenges.pendingId, 'd42');
    });

    test('annuler un défi confirmé prévient le serveur', () {
      challenges.bind();
      challenges.challenge('Ana', cadence: '5min');
      socket.emit(FugaEvents.defiEnvoye, {'defi_id': 'd42'});

      challenges.cancel();

      expect(socket.lastOf('annuler_defi'), {'defi_id': 'd42'});
      expect(challenges.isWaiting, isFalse);
    });

    test('annuler avant la confirmation n envoie rien', () {
      // Sans identifiant, le serveur n'a rien à annuler : on arrête juste
      // d'attendre.
      challenges.bind();
      challenges.challenge('Ana', cadence: '5min');

      challenges.cancel();

      expect(socket.didSend('annuler_defi'), isFalse);
      expect(challenges.isWaiting, isFalse);
    });
  });

  group('Défi qui n aboutit pas', () {
    test('chaque raison de refus est distinguée', () {
      final reasons = <ChallengeFailure>[];
      challenges.bind(onFailed: reasons.add);

      for (final r in ['soi_meme', 'bloque', 'hors_ligne', null]) {
        socket.emit(FugaEvents.defiEchec, {'raison': r});
      }

      expect(reasons, [
        ChallengeFailure.self,
        ChallengeFailure.blocked,
        ChallengeFailure.unavailable,
        ChallengeFailure.unavailable,
      ]);
    });

    test('un échec remet le service au repos', () {
      challenges.bind();
      challenges.challenge('Ana', cadence: '5min');
      socket.emit(FugaEvents.defiEnvoye, {'defi_id': 'd42'});

      socket.emit(FugaEvents.defiEchec, {'raison': 'bloque'});

      expect(challenges.isWaiting, isFalse);
      expect(challenges.pendingId, isNull);
    });

    test('un refus nomme celui qui a refusé', () {
      String? refused;
      challenges.bind(onRefused: (o) => refused = o);

      socket.emit(FugaEvents.defiRefuse, {'cible': 'Ana'});

      expect(refused, 'Ana');
      expect(challenges.isWaiting, isFalse);
    });
  });

  group('Défi reçu', () {
    test('tout ce que le serveur annonce est lu', () {
      IncomingChallenge? received;
      challenges.bind(onReceived: (d) => received = d);

      socket.emit(FugaEvents.defiRecu, {
        'defi_id': 'd7',
        'defieur': 'Bob',
        'defieur_melo': 1610,
        'objectif': '3',
        'cadence': 'zen',
        'random': true,
      });

      expect(received!.id, 'd7');
      expect(received!.from, 'Bob');
      expect(received!.melo, 1610);
      expect(received!.objectif, '3');
      expect(received!.cadence, 'zen');
      expect(received!.random, isTrue);
    });

    test('un défi incomplet garde des valeurs sensées', () {
      IncomingChallenge? received;
      challenges.bind(onReceived: (d) => received = d);

      socket.emit(FugaEvents.defiRecu, {'defi_id': 'd8'});

      expect(received!.melo, 1500);
      expect(received!.objectif, 'partie');
      expect(received!.random, isFalse);
    });

    test('accepter et refuser répondent au bon défi', () {
      const defi = IncomingChallenge(id: 'd9', from: 'Bob');

      challenges.respond(defi, accept: true);
      expect(socket.lastOf('repondre_defi'), {
        'defi_id': 'd9',
        'accepte': true,
      });

      challenges.respond(defi, accept: false);
      expect(socket.lastOf('repondre_defi')!['accepte'], isFalse);
    });

    test('le défieur annule : on est prévenu', () {
      var cancelled = false;
      challenges.bind(onCancelled: () => cancelled = true);

      socket.emit(FugaEvents.defiAnnule, {});

      expect(cancelled, isTrue);
    });
  });

  test('se désabonner coupe tout', () {
    var received = 0;
    challenges.bind(onReceived: (_) => received++);
    challenges.unbind();

    socket.emit(FugaEvents.defiRecu, {'defi_id': 'd1'});

    expect(received, 0);
    expect(socket.handlers, isEmpty);
  });
}
