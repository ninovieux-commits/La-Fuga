/// Correspondance : lecture des parties du serveur, rejeu des coups, et
/// atomicité du coup qui clôt une partie.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:test/test.dart';

/// Une partie telle que le serveur la décrit.
Map<String, dynamic> serverGame({
  String id = 'g1',
  String statut = 'en_cours',
  String maCouleur = 'Blanc',
  String movesText = '',
  bool myTurn = true,
  String randomCode = '',
  bool nulleARepondre = false,
  int chatNonLus = 0,
  bool? gagne,
}) => {
  'id': id,
  'statut': statut,
  'ma_couleur': maCouleur,
  'adversaire': 'Adversaire',
  'adversaire_melo': 1540,
  'mon_score': 3,
  'score_adverse': 2,
  'objectif': 'partie',
  'turn': myTurn ? maCouleur : (maCouleur == 'Blanc' ? 'Noir' : 'Blanc'),
  'moves_text': movesText,
  'my_turn': myTurn,
  'is_defieur': true,
  'resultat': gagne == null ? '' : (gagne ? '1-0' : '0-1'),
  'methode': gagne == null ? '' : 'fugue',
  'gagne': gagne,
  'chat_non_lus': chatNonLus,
  'nulle_a_repondre': nulleARepondre,
  'nulle_proposeur': nulleARepondre ? 'Adversaire' : '',
  'nulle_proposee_par_moi': false,
  'random_code': randomCode,
  'updated_at': '2026-09-19 22:00:00',
};

/// Client branché sur une réponse programmée, qui retient les requêtes.
final class Recorder {
  final List<({String path, Map<String, dynamic> body})> calls = [];
  Map<String, dynamic> response = {'ok': true};

  OnlineClient client() {
    final c = OnlineClient(
      api: ApiClient(
        client: MockClient((request) async {
          calls.add((
            path: request.url.path,
            body: Map<String, dynamic>.from(
              jsonDecode(request.body) as Map<String, dynamic>,
            ),
          ));
          return http.Response(
            jsonEncode(response),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    return c;
  }

  ({String path, Map<String, dynamic> body}) get last => calls.last;
}

void main() {
  group('Lecture d une partie', () {
    test('tous les champs du serveur sont repris', () {
      final g = CorrGame.fromJson(serverGame());
      expect(g.id, 'g1');
      expect(g.status, CorrStatus.enCours);
      expect(g.myCamp, Camp.blanc);
      expect(g.opponent, 'Adversaire');
      expect(g.opponentMelo, 1540);
      expect(g.myScore, 3);
      expect(g.opponentScore, 2);
      expect(g.myTurn, isTrue);
      expect(g.isChallenger, isTrue);
    });

    test('les trois statuts sont reconnus', () {
      expect(
        CorrGame.fromJson(serverGame(statut: 'defi')).status,
        CorrStatus.defi,
      );
      expect(
        CorrGame.fromJson(serverGame(statut: 'en_cours')).status,
        CorrStatus.enCours,
      );
      expect(
        CorrGame.fromJson(serverGame(statut: 'termine')).status,
        CorrStatus.termine,
      );
    });

    test('une partie terminée porte son résultat', () {
      final won = CorrGame.fromJson(serverGame(statut: 'termine', gagne: true));
      expect(won.won, isTrue);
      expect(won.result, '1-0');

      final lost = CorrGame.fromJson(
        serverGame(statut: 'termine', gagne: false),
      );
      expect(lost.won, isFalse);

      final draw = CorrGame.fromJson(serverGame(statut: 'termine'));
      expect(draw.won, isNull, reason: 'nulle');
    });

    test('une proposition de nulle est signalée avec son auteur', () {
      final g = CorrGame.fromJson(serverGame(nulleARepondre: true));
      expect(g.drawToAnswer, isTrue);
      expect(g.drawProposer, 'Adversaire');
    });

    test('les messages non lus sont comptés', () {
      expect(CorrGame.fromJson(serverGame(chatNonLus: 4)).unreadChat, 4);
    });

    test('sans code aléatoire, la position de départ est la standard', () {
      expect(
        CorrGame.fromJson(serverGame()).initialBoard.key,
        Board.initial().key,
      );
    });

    test('avec un code aléatoire, la position vient du code', () {
      final g = CorrGame.fromJson(serverGame(randomCode: '.03-09'));
      expect(g.initialBoard.key, isNot(Board.initial().key));
    });
  });

  group('Rejeu', () {
    test('une partie vide reste à la position de départ', () {
      final r = replay(CorrGame.fromJson(serverGame()))!;
      expect(r.board.key, Board.initial().key);
      expect(r.turn, Camp.blanc);
    });

    test('les coups sont rejoués dans l ordre et le trait alterne', () {
      // On fabrique deux coups légaux depuis la position de départ.
      var board = Board.initial();
      final m1 = generateMoves(board, Camp.blanc).first;
      final n1 = notationOn(board, m1);
      board = m1.board;
      final m2 = generateMoves(board, Camp.noir).first;
      final n2 = notationOn(board, m2);

      final g = CorrGame.fromJson(serverGame(movesText: '1.$n1/$n2'));
      final r = replay(g)!;
      expect(r.board.key, m2.board.key);
      expect(r.turn, Camp.blanc, reason: 'deux coups joués, à Blanc de jouer');
    });

    test('une partie qu on ne sait pas rejouer se signale', () {
      // Un coup impossible : mieux vaut refuser d'afficher que montrer une
      // position fausse.
      final g = CorrGame.fromJson(serverGame(movesText: '1.Si8-Si7'));
      expect(replay(g), isNull);
    });
  });

  group('Coup qui clôt la partie', () {
    test('une fugue ferme la partie', () {
      expect(
        closingMethodFor(
          boardAfter: Board.initial(),
          nextTurn: Camp.noir,
          fugue: true,
          mat: false,
        ),
        'fugue',
      );
    });

    test('un mat ferme la partie', () {
      expect(
        closingMethodFor(
          boardAfter: Board.initial(),
          nextTurn: Camp.noir,
          fugue: false,
          mat: true,
        ),
        'mat',
      );
    });

    test('la Trêve ferme la partie en nulle', () {
      final b = Board.empty();
      b.set(0, 0, Piece.blancSoldat); // isolée
      b.set(6, 7, Piece.noirGarde); // isolée
      b.set(3, 3, Piece.blancNurse);
      b.set(3, 4, Piece.blancNurse);
      expect(
        closingMethodFor(
          boardAfter: b,
          nextTurn: Camp.noir,
          fugue: false,
          mat: false,
        ),
        'nulle',
      );
    });

    test('un coup ordinaire ne ferme rien', () {
      expect(
        closingMethodFor(
          boardAfter: Board.initial(),
          nextTurn: Camp.noir,
          fugue: false,
          mat: false,
        ),
        isNull,
      );
    });
  });

  group('Service', () {
    late Recorder rec;
    late CorrespondenceService corr;

    setUp(() async {
      rec = Recorder();
      final client = rec.client();
      rec.response = {'ok': true, 'token': 't', 'pseudo': 'Nino'};
      await client.login('Nino', 'mdp');
      corr = CorrespondenceService(client);
      rec.response = {'ok': true};
    });

    test('la liste est convertie en parties', () async {
      rec.response = {
        'ok': true,
        'games': [serverGame(id: 'a'), serverGame(id: 'b', statut: 'defi')],
      };
      final games = await corr.list();
      expect(rec.last.path, '/corr_list');
      expect(games, hasLength(2));
      expect(games![1].status, CorrStatus.defi);
    });

    test('un coup ordinaire part sans méthode', () async {
      await corr.play('g1', 'Fa2-Fa3');
      expect(rec.last.path, '/corr_jouer');
      expect(rec.last.body.containsKey('methode'), isFalse);
    });

    test(
      'un coup qui clôt la partie part AVEC sa méthode, en une requête',
      () async {
        await corr.play('g1', 'Fa7*', method: 'fugue');
        expect(rec.last.body['methode'], 'fugue');
        expect(
          rec.calls.where((c) => c.path == '/corr_jouer').length,
          1,
          reason: 'atomique : jamais deux requêtes',
        );
      },
    );

    test('un défi transmet objectif et mode aléatoire', () async {
      await corr.challenge('Ami', '5', random: true);
      expect(rec.last.path, '/corr_defier');
      expect(rec.last.body['pseudo'], 'Ami');
      expect(rec.last.body['objectif'], '5');
      expect(rec.last.body['random'], isTrue);
    });

    test('un défi refusé remonte le message du serveur', () async {
      rec.response = {'ok': false, 'error': 'Joueur introuvable'};
      expect(await corr.challenge('Fantome', 'partie'), 'Joueur introuvable');
    });

    test(
      'accepter une nulle renvoie vrai quand la partie devient nulle',
      () async {
        rec.response = {'ok': true, 'nulle': true};
        expect(await corr.answerDraw('g1', true), isTrue);

        rec.response = {'ok': true, 'nulle': false};
        expect(await corr.answerDraw('g1', false), isFalse);
      },
    );

    test('un message de chat vide n est pas envoyé', () async {
      expect(await corr.sendChat('g1', '   '), isFalse);
      expect(rec.calls.where((c) => c.path == '/corr_chat_send'), isEmpty);
    });

    test('le chat se lit, quel que soit le nom de la liste', () async {
      // Le serveur renvoie « messages » ; on accepte aussi « chat ».
      rec.response = {
        'ok': true,
        'messages': [
          {'auteur': 'Ana', 'texte': 'à toi'},
        ],
      };
      expect(await corr.chat('g1'), [
        {'auteur': 'Ana', 'texte': 'à toi'},
      ]);
      expect(rec.last.path, '/corr_chat_list');

      rec.response = {
        'ok': true,
        'chat': [
          {'auteur': 'Bob', 'texte': 'ok'},
        ],
      };
      expect((await corr.chat('g1'))!.single['texte'], 'ok');
    });

    test('un chat indisponible se distingue d un chat vide', () async {
      rec.response = {'ok': false, 'error': 'oups'};
      expect(await corr.chat('g1'), isNull);

      rec.response = {'ok': true};
      expect(await corr.chat('g1'), isEmpty);
    });

    test('fermer une partie terminée la masque', () async {
      await corr.close('g1');
      expect(rec.last.path, '/corr_close');
      expect(rec.last.body['game_id'], 'g1');
    });
  });
}
