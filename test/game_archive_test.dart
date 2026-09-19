/// Archivage d'une partie terminée : marque de fin, en-tête, identifiant,
/// et destination (serveur si connecté, sinon l'appareil).
library;

import 'dart:io';

import 'package:lafuga/game/game_archive.dart';
import 'package:lafuga/game/nmc.dart';
import 'package:lafuga/state/local_games.dart';
import 'package:test/test.dart';

void main() {
  group('Points', () {
    test('mat et papatte valent 1 point', () {
      expect(pointsForMethod('mat'), 1);
      expect(pointsForMethod('papatte'), 1);
    });

    test('fugue, temps et abandon valent 2 points', () {
      expect(pointsForMethod('fugue'), 2);
      expect(pointsForMethod('temps'), 2);
      expect(pointsForMethod('abandon'), 2);
    });

    test('une nulle ne rapporte rien', () {
      expect(pointsForMethod('nulle'), 0);
    });
  });

  group('Méthode enregistrée', () {
    test('toutes les nulles sont écrites « nulle »', () {
      expect(nmcMethod('nulle_pat'), 'nulle');
      expect(nmcMethod('nulle_accord'), 'nulle');
      expect(nmcMethod('repetition'), 'nulle');
    });

    test('les autres fins gardent leur nom', () {
      expect(nmcMethod('fugue'), 'fugue');
      expect(nmcMethod('mat'), 'mat');
    });
  });

  group('Marque de fin sur le dernier coup', () {
    test('un mat ajoute #', () {
      expect(withEndSuffix(['Do1-Do2', 'Ré8-Ré7'], 'mat').last, 'Ré8-Ré7#');
    });

    test('le temps et l abandon ajoutent *', () {
      expect(withEndSuffix(['Do1-Do2'], 'temps').last, 'Do1-Do2*');
      expect(withEndSuffix(['Do1-Do2'], 'abandon').last, 'Do1-Do2*');
    });

    test('une fugue porte déjà son étoile', () {
      expect(withEndSuffix(['Mi7*'], 'fugue').last, 'Mi7*');
    });

    test('une nulle ne marque rien', () {
      expect(withEndSuffix(['Do1-Do2'], 'nulle').last, 'Do1-Do2');
    });

    test('on ne redouble pas une marque déjà posée', () {
      expect(withEndSuffix(['Do1-Do2#'], 'mat').last, 'Do1-Do2#');
      expect(withEndSuffix(['Mi7*'], 'temps').last, 'Mi7*');
    });

    test('une partie sans coup ne pose rien', () {
      expect(withEndSuffix(const [], 'mat'), isEmpty);
    });
  });

  group('En-tête', () {
    final when = DateTime(2026, 9, 19, 14, 3, 22);

    ArchivedGame archiveOf({String? winner, String method = 'fugue'}) =>
        buildArchive(
          player1: 'Nino',
          player2: 'deep grey',
          blanc: 'Nino',
          winner: winner,
          method: method,
          history: ['Do1-Do2', 'Ré8-Ré7'],
          cadence: '5min',
          now: when,
        );

    test('la date est à la minute, comme en Kivy', () {
      expect(archiveOf(winner: 'Nino').meta.date, '2026-09-19 14:03');
    });

    test('le résultat suit l ordre des joueurs', () {
      expect(archiveOf(winner: 'Nino').meta.result, '1-0');
      expect(archiveOf(winner: 'deep grey').meta.result, '0-1');
      expect(archiveOf(method: 'nulle_pat').meta.result, '½-½');
    });

    test('la méthode et les points vont ensemble', () {
      final g = archiveOf(winner: 'Nino', method: 'mat');
      expect(g.meta.method, 'mat');
      expect(g.meta.points, '1');
      expect(g.moves.last, 'Ré8-Ré7#', reason: 'le mat marque le dernier coup');
    });

    test('le .nmc se relit', () {
      final g = archiveOf(winner: 'Nino');
      final parsed = parseNmc(g.nmc);
      expect(parsed.meta.player1, 'Nino');
      expect(parsed.meta.cadence, '5min');
      expect(parsed.moves, g.moves);
    });

    test('une position tirée au sort est notée dans l en-tête', () {
      final g = buildArchive(
        player1: 'A',
        player2: 'B',
        blanc: 'A',
        winner: null,
        method: 'nulle',
        history: const [],
        randomCode: '.03-09',
        now: when,
      );
      expect(parseNmc(g.nmc).meta.random, '.03-09');
    });
  });

  group('Identifiant', () {
    ArchivedGame uidOf({String? online, String? corr, String blanc = 'Nino'}) =>
        buildArchive(
          player1: 'Nino',
          player2: 'deep grey',
          blanc: blanc,
          winner: 'Nino',
          method: 'fugue',
          history: const ['Mi7*'],
          onlineGameId: online,
          corrGameId: corr,
          now: DateTime(2026, 9, 19, 14, 3),
        );

    test('une partie en ligne reprend l identifiant du serveur', () {
      // Les deux joueurs enregistrent ainsi la MÊME partie.
      expect(uidOf(online: '42').uid, 'online_42');
    });

    test(
      'une partie par correspondance va aussi dans l historique en ligne',
      () {
        expect(uidOf(corr: '7').uid, 'online_corr7');
      },
    );

    test('une partie hors ligne est identifiée par son contenu', () {
      final a = uidOf();
      expect(a.uid, startsWith('local_'));
      expect(a.uid.length, 'local_'.length + 16);
      expect(a.uid, uidOf().uid, reason: 'même partie, même identifiant');
      expect(
        uidOf(blanc: 'deep grey').uid,
        isNot(a.uid),
        reason: 'une autre partie, un autre identifiant',
      );
    });
  });

  group('Destination', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('lafuga_arch'));
    tearDown(() => tmp.deleteSync(recursive: true));

    ArchivedGame partie() => buildArchive(
      player1: 'Joueur 1',
      player2: 'Joueur 2',
      blanc: 'Joueur 1',
      winner: 'Joueur 1',
      method: 'fugue',
      history: const ['Mi7*'],
      cadence: '5min',
    );

    test('hors ligne, la partie est écrite sur l appareil', () async {
      final store = LocalGamesStore(directory: tmp);
      final archive = GameArchive(account: _FakeAccount(), local: store);

      await archive.store(partie());

      final games = await store.list();
      expect(games, hasLength(1));
      expect(games.single.meta.player1, 'Joueur 1');
      expect(games.single.meta.method, 'fugue');
    });

    test('connecté, la partie part au serveur et non sur l appareil', () async {
      final store = LocalGamesStore(directory: tmp);
      final account = _FakeAccount(loggedIn: true);
      final game = partie();

      await GameArchive(account: account, local: store).store(game);

      expect(account.saved, hasLength(1));
      expect(account.saved.single['game_uid'], game.uid);
      expect(account.saved.single['nmc_text'], game.nmc);
      expect(account.saved.single['resultat'], '1-0');
      expect(account.saved.single['methode'], 'fugue');
      expect(account.saved.single['cadence'], '5min');
      expect(
        await store.list(),
        isEmpty,
        reason: 'l historique vient alors du compte',
      );
    });

    test('un serveur en panne ne gâche pas la fin de partie', () async {
      final archive = GameArchive(
        account: _FakeAccount(loggedIn: true, fails: true),
        local: LocalGamesStore(directory: tmp),
      );

      await expectLater(archive.store(partie()), completes);
    });
  });
}

/// Compte en ligne simulé : on regarde ce qui lui est envoyé.
final class _FakeAccount implements AccountGames {
  _FakeAccount({this.loggedIn = false, this.fails = false});

  final bool loggedIn;
  final bool fails;
  final List<Map<String, dynamic>> saved = [];

  @override
  bool get isLoggedIn => loggedIn;

  @override
  Future<void> saveGame(Map<String, dynamic> data) async {
    if (fails) throw const SocketException('pas de réseau');
    saved.add(data);
  }
}
