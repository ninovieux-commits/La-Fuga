/// Partie en ligne : on lui envoie des événements serveur à la main et on
/// vérifie ce qu'elle fait — sans serveur, sans interface.
///
/// C'est la couche la plus pénible à déboguer en production : autant la
/// coincer ici.
library;

import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/engine/random_fuga.dart';
import 'package:lafuga/game/clock.dart';
import 'package:lafuga/game/move_controller.dart';
import 'package:lafuga/game/online_game.dart';
import 'package:lafuga/net/socket_client.dart';
import 'package:test/test.dart';

/// Connexion simulée : retient ce qui est émis, et permet de déclencher un
/// événement serveur à la demande.
final class FakeSocket implements GameSocket {
  final Map<String, void Function(Map<String, dynamic>)> handlers = {};
  final List<({String name, Map<String, dynamic> data})> sent = [];

  @override
  void on(String event, void Function(Map<String, dynamic>) handler) =>
      handlers[event] = handler;

  @override
  void off(String event) => handlers.remove(event);

  /// Simule un événement venu du serveur.
  void emit(String event, Map<String, dynamic> data) =>
      handlers[event]?.call(data);

  bool didSend(String name) => sent.any((e) => e.name == name);

  Map<String, dynamic>? lastOf(String name) {
    for (final e in sent.reversed) {
      if (e.name == name) return e.data;
    }
    return null;
  }

  @override
  void jouerCoup({
    required String gameId,
    required String notation,
    int? clockBlanc,
    int? clockNoir,
    int? clockMe,
  }) => sent.add((
    name: 'jouer_coup',
    data: {
      'game_id': gameId,
      'notation': notation,
      'clock_blanc': clockBlanc,
      'clock_noir': clockNoir,
      'clock_me': clockMe,
    },
  ));

  @override
  void finPartie({
    required String gameId,
    required String methode,
    String? loserColor,
  }) => sent.add((
    name: 'fin_partie',
    data: {'game_id': gameId, 'methode': methode, 'loser_color': loserColor},
  ));

  @override
  void proposerNulle(String gameId) =>
      sent.add((name: 'proposer_nulle', data: {'game_id': gameId}));

  @override
  void chat(String gameId, String texte) =>
      sent.add((name: 'chat', data: {'game_id': gameId, 'texte': texte}));

  @override
  void pretPartieSuivante(String gameId) =>
      sent.add((name: 'pret_partie_suivante', data: {'game_id': gameId}));

  @override
  void abandonnerMatch(String gameId) =>
      sent.add((name: 'abandonner_match', data: {'game_id': gameId}));
}

OnlineGame makeGame({
  Camp myCamp = Camp.blanc,
  Cadence cadence = Cadence.illimitee,
  String? randomCode,
  FakeSocket? socket,
  void Function(OnlineEvent)? onChanged,
}) => OnlineGame(
  socket: socket ?? FakeSocket(),
  cadence: cadence,
  onChanged: onChanged,
  info: OnlineGameInfo(
    gameId: 'g1',
    myCamp: myCamp,
    opponent: 'Adversaire',
    opponentMelo: 1500,
    objectif: 'partie',
    cadence: cadence.label,
    randomCode: randomCode,
  ),
);

/// Joue le premier coup légal du camp au trait, en gestes.
String playFirstMove(OnlineGame g) {
  final move = generateMoves(g.game.board, g.game.turn).first;
  g.tapCell(move.from);
  g.tapCell(move.to);
  final result = g.tapCell(move.to); // retoucher pour valider
  return result.notation ?? '';
}

void main() {
  group('Ouverture', () {
    test("lit un payload partie_trouvee", () {
      final info = OnlineGameInfo.fromEvent({
        'game_id': 'abc',
        'couleur': 'Noir',
        'adversaire': 'Nino',
        'adversaire_melo': 1620,
        'objectif': '5',
        'cadence': '5min',
        'random_code': '.03-09',
      });
      expect(info.gameId, 'abc');
      expect(info.myCamp, Camp.noir);
      expect(info.opponent, 'Nino');
      expect(info.opponentMelo, 1620);
      expect(info.objectif, '5');
      expect(info.randomCode, '.03-09');
    });

    test('sans code aléatoire, on part de la position standard', () {
      final g = makeGame();
      expect(g.game.board.key, Board.initial().key);
    });

    test('avec un code aléatoire, on part de SA position', () {
      final g = makeGame(randomCode: '.03-09');
      expect(g.game.board.key, isNot(Board.initial().key));
      expect(g.game.board.key, buildRandomFugaBoard('.03-09')!.key);
    });

    test('un code aléatoire invalide retombe sur la position standard', () {
      final g = makeGame(randomCode: 'bidon');
      expect(g.game.board.key, Board.initial().key);
    });
  });

  group('Mon tour', () {
    test('un coup validé part au serveur', () {
      final socket = FakeSocket();
      final g = makeGame(socket: socket, cadence: Cadence.blitz5);
      final notation = playFirstMove(g);

      expect(socket.didSend('jouer_coup'), isTrue);
      final sent = socket.lastOf('jouer_coup')!;
      expect(sent['notation'], notation);
      expect(sent['game_id'], 'g1');
    });

    test("l'horloge part sous les TROIS clés", () {
      final socket = FakeSocket();
      final g = makeGame(socket: socket, cadence: Cadence.blitz5);
      playFirstMove(g);

      final sent = socket.lastOf('jouer_coup')!;
      // Le serveur lit « clock_me » : sans elle, la synchro ne marche pas.
      expect(sent['clock_me'], 300);
      // Les deux autres gardent la compatibilité avec un client Kivy.
      expect(sent['clock_blanc'], 300);
      expect(sent['clock_noir'], 300);
    });

    test('je ne peux pas jouer quand ce n est pas mon tour', () {
      final socket = FakeSocket();
      final g = makeGame(myCamp: Camp.noir, socket: socket);
      expect(g.isMyTurn, isFalse, reason: 'les Blancs commencent');

      final move = generateMoves(g.game.board, Camp.blanc).first;
      expect(g.tapCell(move.from).effect, ControllerEffect.none);
      expect(socket.didSend('jouer_coup'), isFalse);
    });
  });

  group('Coup adverse', () {
    test('un coup reçu est rejoué sur le plateau', () {
      final socket = FakeSocket();
      final g = makeGame(myCamp: Camp.noir, socket: socket);

      final move = generateMoves(g.game.board, Camp.blanc).first;
      final notation = notationOn(g.game.board, move);
      socket.emit(FugaEvents.coupAdverse, {
        'game_id': 'g1',
        'notation': notation,
        'clock_adverse': 250,
      });

      expect(g.game.board.key, move.board.key);
      expect(g.game.turn, Camp.noir, reason: 'la main me revient');
      expect(g.isMyTurn, isTrue);
    });

    test("l'horloge adverse est synchronisée", () {
      final socket = FakeSocket();
      final g = makeGame(
        myCamp: Camp.noir,
        socket: socket,
        cadence: Cadence.blitz5,
      );

      final move = generateMoves(g.game.board, Camp.blanc).first;
      socket.emit(FugaEvents.coupAdverse, {
        'notation': notationOn(g.game.board, move),
        'clock_adverse': 250,
      });
      expect(g.clock.remainingFor(Camp.blanc), 250);
    });

    test('une notation qui ne correspond à rien est ignorée', () {
      final socket = FakeSocket();
      final g = makeGame(myCamp: Camp.noir, socket: socket);
      final before = g.game.board.key;

      socket.emit(FugaEvents.coupAdverse, {'notation': 'Si8-Si7'});

      expect(
        g.game.board.key,
        before,
        reason: 'mieux vaut ignorer que jouer autre chose',
      );
      expect(g.game.turn, Camp.blanc, reason: 'la main n a pas tourné');
    });

    test(
      "un coup adverse qui termine la partie ne renvoie rien au serveur",
      () {
        final socket = FakeSocket();
        final g = makeGame(myCamp: Camp.noir, socket: socket);

        socket.emit(FugaEvents.partieTerminee, {
          'methode': 'fugue',
          'loser_color': 'Noir',
        });

        expect(g.endReason, 'fugue');
        expect(g.loser, Camp.noir);
        expect(
          socket.didSend('fin_partie'),
          isFalse,
          reason: 'l adversaire le sait déjà',
        );
      },
    );
  });

  group('Fin de partie', () {
    test('un abandon prévient le serveur', () {
      final socket = FakeSocket();
      final g = makeGame(socket: socket);
      g.resign();

      expect(g.endReason, 'abandon');
      expect(g.loser, Camp.blanc);
      final sent = socket.lastOf('fin_partie')!;
      expect(sent['methode'], 'abandon');
      expect(sent['loser_color'], 'Blanc');
    });

    test('une partie ne se termine qu une fois', () {
      final socket = FakeSocket();
      final g = makeGame(socket: socket);
      g.resign();
      socket.emit(FugaEvents.partieTerminee, {
        'methode': 'mat',
        'loser_color': 'Noir',
      });

      expect(g.endReason, 'abandon', reason: 'la première fin fait foi');
      expect(socket.sent.where((e) => e.name == 'fin_partie').length, 1);
    });

    test('plus rien ne se joue après la fin', () {
      final socket = FakeSocket();
      final g = makeGame(socket: socket);
      g.resign();
      final before = g.game.board.key;

      final move = generateMoves(g.game.board, Camp.blanc).first;
      g.tapCell(move.from);
      expect(g.game.board.key, before);
    });
  });

  group('Nulle', () {
    test('proposer la nulle passe par le serveur', () {
      final socket = FakeSocket();
      makeGame(socket: socket).offerDraw();
      expect(socket.didSend('proposer_nulle'), isTrue);
    });

    test('une proposition reçue est signalée', () {
      final socket = FakeSocket();
      final events = <OnlineEvent>[];
      final g = makeGame(socket: socket, onChanged: events.add);

      socket.emit(FugaEvents.nulleProposee, {'game_id': 'g1'});

      expect(g.drawOffered, isTrue);
      expect(events, contains(OnlineEvent.drawOffered));
    });

    test('accepter termine la partie en nulle', () {
      final socket = FakeSocket();
      final g = makeGame(socket: socket);
      socket.emit(FugaEvents.nulleProposee, {});
      g.acceptDraw();

      expect(g.endReason, 'nulle');
      expect(g.loser, isNull);
      expect(socket.lastOf('fin_partie')!['loser_color'], isNull);
    });

    test('refuser laisse la partie continuer', () {
      final socket = FakeSocket();
      final g = makeGame(socket: socket);
      socket.emit(FugaEvents.nulleProposee, {});
      g.declineDraw();

      expect(g.drawOffered, isFalse);
      expect(g.endReason, isNull);
    });
  });

  group('Présence, chat et match', () {
    test('la déconnexion de l adversaire est suivie', () {
      final socket = FakeSocket();
      final g = makeGame(socket: socket);

      socket.emit(FugaEvents.adversaireDeconnecte, {'delai': 60});
      expect(g.opponentConnected, isFalse);
      expect(g.disconnectGrace, 60);

      socket.emit(FugaEvents.adversaireRevenu, {'game_id': 'g1'});
      expect(g.opponentConnected, isTrue);
      expect(g.disconnectGrace, isNull);
    });

    test('le chat va dans les deux sens', () {
      final socket = FakeSocket();
      final g = makeGame(socket: socket);

      g.sendChat('bien joué');
      expect(socket.lastOf('chat')!['texte'], 'bien joué');
      expect(g.chat.last.text, 'bien joué');

      socket.emit(FugaEvents.chatRecu, {'texte': 'merci'});
      expect(g.chat.last.text, 'merci');
      expect(g.chat.last.author, 'Adversaire');
    });

    test('un message vide n est pas envoyé', () {
      final socket = FakeSocket();
      final g = makeGame(socket: socket);
      g.sendChat('   ');
      expect(socket.didSend('chat'), isFalse);
      expect(g.chat, isEmpty);
    });

    test('le mélo mis à jour est retenu', () {
      final socket = FakeSocket();
      final g = makeGame(socket: socket);
      socket.emit(FugaEvents.meloMaj, {'mon_melo': 1612, 'delta': 12});
      expect(g.newMelo, 1612);
      expect(g.meloDelta, 12);
    });

    test('le score du match suit les événements', () {
      final socket = FakeSocket();
      final g = makeGame(socket: socket);

      socket.emit(FugaEvents.matchContinue, {
        'score_blanc': 2,
        'score_noir': 1,
        'objectif': '5',
      });
      expect(g.matchContinues, isTrue);
      expect(g.scoreBlanc, 2);
      expect(g.scoreNoir, 1);

      socket.emit(FugaEvents.matchOver, {'score_blanc': 5, 'score_noir': 3});
      expect(g.matchContinues, isFalse);
      expect(g.scoreBlanc, 5);
    });
  });

  test('dispose retire tous les abonnements', () {
    final socket = FakeSocket();
    final g = makeGame(socket: socket);
    expect(socket.handlers, isNotEmpty);
    g.dispose();
    expect(socket.handlers, isEmpty);
  });
}
