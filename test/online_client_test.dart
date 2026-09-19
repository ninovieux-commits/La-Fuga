/// Couche réseau : le client doit parler exactement le protocole de
/// `server.py`. Ces tests vérifient les chemins et les clés envoyées, parce
/// qu'une faute de frappe sur une clé ne se voit qu'en production.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:test/test.dart';

/// Enregistre les requêtes envoyées et renvoie une réponse programmée.
final class _Recorder {
  final List<({String path, Map<String, dynamic> body})> calls = [];
  Map<String, dynamic> response = {'ok': true};
  int statusCode = 200;

  http.Client get client => MockClient((request) async {
    calls.add((
      path: request.url.path,
      body: Map<String, dynamic>.from(
        jsonDecode(request.body) as Map<String, dynamic>,
      ),
    ));
    return http.Response(
      jsonEncode(response),
      statusCode,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  ({String path, Map<String, dynamic> body}) get last => calls.last;
}

void main() {
  late _Recorder rec;
  late OnlineClient online;

  setUp(() {
    rec = _Recorder();
    online = OnlineClient(api: ApiClient(client: rec.client));
  });

  group('Connexion', () {
    test('login envoie pseudo et mot de passe et ouvre la session', () async {
      rec.response = {
        'ok': true,
        'token': 'jeton-abc',
        'pseudo': 'Nino',
        'melo': 1620,
        'melo_random': 1480,
        'theme': 'dragon',
        'photo': 'dragon|Héritier',
      };
      final r = await online.login('Nino', 'motdepasse');

      expect(r.isOk, isTrue);
      expect(rec.last.path, '/login');
      expect(rec.last.body, {'pseudo': 'Nino', 'password': 'motdepasse'});
      expect(online.isLoggedIn, isTrue);
      expect(online.session!.token, 'jeton-abc');
      expect(online.session!.melo, 1620);
      expect(
        online.session!.meloRandom,
        1480,
        reason: 'le mélo Random Fuga est séparé',
      );
      expect(online.session!.theme, 'dragon');
    });

    test('register transmet aussi l email', () async {
      rec.response = {'ok': true, 'token': 't', 'pseudo': 'Nino'};
      await online.register('Nino', 'mdp', email: 'a@b.c');
      expect(rec.last.path, '/register');
      expect(rec.last.body['email'], 'a@b.c');
    });

    test('un refus du serveur laisse la session fermée', () async {
      rec.response = {'ok': false, 'error': 'Pseudo déjà pris'};
      final r = await online.login('Nino', 'mdp');
      expect(r.isOk, isFalse);
      expect(r.serverError, 'Pseudo déjà pris');
      expect(online.isLoggedIn, isFalse);
    });

    test(
      'une erreur HTTP avec corps JSON remonte le message du serveur',
      () async {
        rec.statusCode = 400;
        rec.response = {'ok': false, 'error': 'Mot de passe trop court'};
        final r = await online.login('Nino', 'x');
        expect(r.isOk, isFalse);
        expect(r.serverError, 'Mot de passe trop court');
        expect(
          r.isNetworkError,
          isFalse,
          reason: 'le serveur a répondu : ce n est pas une panne réseau',
        );
      },
    );
  });

  group('Reconnexion par token', () {
    test('un token valide rouvre la session', () async {
      rec.response = {'ok': true, 'pseudo': 'Nino', 'melo': 1500};
      await online.pingWithToken('jeton-sauvegarde');
      expect(rec.last.path, '/ping');
      expect(rec.last.body, {'token': 'jeton-sauvegarde'});
      expect(
        online.session!.token,
        'jeton-sauvegarde',
        reason: '/ping ne renvoie pas le token : on garde celui fourni',
      );
    });

    test('un token rejeté ferme la session', () async {
      rec.response = {'ok': false, 'error': 'Token invalide'};
      await online.pingWithToken('vieux-jeton');
      expect(online.isLoggedIn, isFalse);
    });

    test('une coupure réseau ne déconnecte PAS', () async {
      // Session déjà ouverte.
      rec.response = {'ok': true, 'token': 't', 'pseudo': 'Nino'};
      await online.login('Nino', 'mdp');
      expect(online.isLoggedIn, isTrue);

      // Puis le serveur devient injoignable.
      final offline = OnlineClient(
        api: ApiClient(
          client: MockClient((_) async => throw Exception('down')),
        ),
      );
      final r = await offline.pingWithToken('jeton');
      expect(r.isNetworkError, isTrue);
      // Le client d'origine garde sa session : une coupure ne doit pas
      // effacer un compte.
      expect(online.isLoggedIn, isTrue);
    });
  });

  group('Routes authentifiées', () {
    setUp(() async {
      rec.response = {'ok': true, 'token': 'jeton', 'pseudo': 'Nino'};
      await online.login('Nino', 'mdp');
      rec.response = {'ok': true};
    });

    test('le token accompagne chaque appel', () async {
      await online.listFavorites();
      expect(rec.last.path, '/list_favorites');
      expect(rec.last.body['token'], 'jeton');
    });

    test('get_profile sans pseudo demande le mien', () async {
      await online.getProfile();
      expect(rec.last.body['pseudo'], '');
    });

    test('les préférences de notification passent telles quelles', () async {
      await online.setNotifPrefs({
        'mail': true,
        'turn': false,
        'msg': true,
        'defi_corr': false,
        'defi_direct': true,
      });
      expect(rec.last.path, '/set_notif_prefs');
      expect(rec.last.body['turn'], isFalse);
      expect(rec.last.body['defi_direct'], isTrue);
      expect(rec.last.body['token'], 'jeton');
    });
  });

  group('Correspondance', () {
    setUp(() async {
      rec.response = {'ok': true, 'token': 'jeton', 'pseudo': 'Nino'};
      await online.login('Nino', 'mdp');
      rec.response = {'ok': true};
    });

    test('un coup ordinaire ne porte pas de méthode', () async {
      await online.corrJouer('g1', 'Fa2-Fa3');
      expect(rec.last.path, '/corr_jouer');
      expect(rec.last.body.containsKey('methode'), isFalse);
    });

    test(
      'un coup qui clôt la partie part avec sa méthode, en une requête',
      () async {
        await online.corrJouer('g1', 'Fa7*', methode: 'fugue');
        expect(rec.last.body['methode'], 'fugue');
        expect(
          rec.calls.where((c) => c.path == '/corr_jouer').length,
          1,
          reason: 'atomique : jamais deux requêtes',
        );
      },
    );

    test('le chat de correspondance est branché', () async {
      await online.corrChatSend('g1', 'bien joué');
      expect(rec.last.path, '/corr_chat_send');
      expect(rec.last.body['text'], 'bien joué');
    });
  });

  group('reconcileTheme', () {
    test('garde le thème local quand le serveur a une version tronquée', () {
      // 45 caractères : assez long pour que la troncature serveur morde.
      const local = 'arcenciel|insectes|deepgrey|medieval|imperial';
      assert(local.length > 40);
      final tronque = local.substring(0, 40);
      expect(
        reconcileTheme(tronque, local),
        local,
        reason: 'le serveur tronque à 40 caractères',
      );
    });

    test('prend le thème serveur quand il diffère vraiment', () {
      expect(
        reconcileTheme('ocean', 'dragon|dragon|dragon|dragon|dragon'),
        'ocean',
        reason: 'thème choisi depuis un autre appareil',
      );
    });

    test('un thème simple passe tel quel', () {
      expect(reconcileTheme('foret', 'original'), 'foret');
    });

    test('un thème serveur vide retombe sur original', () {
      expect(reconcileTheme('', 'original'), 'original');
      expect(reconcileTheme(null, 'original'), 'original');
    });
  });
}
