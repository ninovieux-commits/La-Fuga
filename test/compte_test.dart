/// CHANGER DE PSEUDO, CHANGER DE MOT DE PASSE.
///
/// Nino le demandait depuis longtemps. Ce qui se vérifie ici est le côté
/// application : ce qui part au serveur, et ce que la session en retient.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';

/// Serveur simulé : répond ce qu'on lui dit, et retient ce qu'on lui envoie.
final class _Serveur {
  final List<({String chemin, Map<String, dynamic> corps})> appels = [];
  final Map<String, Map<String, dynamic>> reponses = {};

  http.Client get client => MockClient((requete) async {
    appels.add((
      chemin: requete.url.path,
      corps: Map<String, dynamic>.from(jsonDecode(requete.body) as Map),
    ));
    return http.Response(
      jsonEncode(reponses[requete.url.path] ?? {'ok': true}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  Map<String, dynamic> corpsDe(String chemin) =>
      appels.lastWhere((a) => a.chemin == chemin).corps;
}

void main() {
  late _Serveur serveur;
  late OnlineClient client;

  setUp(() async {
    serveur = _Serveur();
    client = OnlineClient(api: ApiClient(client: serveur.client));
    serveur.reponses['/login'] = {
      'ok': true,
      'token': 'jeton',
      'pseudo': 'nino',
    };
    await client.login('nino', 'mdp');
  });

  group('Le pseudo', () {
    test('la session prend le nouveau nom, et garde son jeton', () async {
      serveur.reponses['/changer_pseudo'] = {'ok': true, 'pseudo': 'Nino'};

      final r = await client.changerPseudo('Nino');

      expect(r.isOk, isTrue);
      expect(serveur.corpsDe('/changer_pseudo')['pseudo'], 'Nino');
      expect(serveur.corpsDe('/changer_pseudo')['token'], 'jeton');
      expect(client.pseudo, 'Nino');
      expect(
        client.token,
        'jeton',
        reason: 'le serveur range ses jetons par compte : on reste connecté',
      );
    });

    test('la session garde le reste du compte', () async {
      serveur.reponses['/changer_pseudo'] = {'ok': true, 'pseudo': 'Nino'};
      final avant = client.session!;
      await client.changerPseudo('Nino');
      final apres = client.session!;

      expect(apres.melo, avant.melo);
      expect(apres.theme, avant.theme);
      expect(apres.photo, avant.photo);
    });

    test('refusé, le nom ne change pas', () async {
      serveur.reponses['/changer_pseudo'] = {
        'ok': false,
        'error': 'Pseudo deja pris',
      };

      final r = await client.changerPseudo('celia');

      expect(r.isOk, isFalse);
      expect(r.serverError, 'Pseudo deja pris');
      expect(client.pseudo, 'nino', reason: 'rien ne doit avoir bougé');
    });
  });

  group('Le mot de passe', () {
    test('l ancien part avec le nouveau', () async {
      serveur.reponses['/changer_mdp'] = {'ok': true};

      final r = await client.changerMotDePasse('avant', 'apres');

      expect(r.isOk, isTrue);
      final corps = serveur.corpsDe('/changer_mdp');
      expect(corps['ancien'], 'avant');
      expect(corps['nouveau'], 'apres');
      expect(corps['token'], 'jeton');
    });

    test(
      'et la session ne bouge pas : c est le serveur qui ferme les autres',
      () async {
        serveur.reponses['/changer_mdp'] = {'ok': true};
        await client.changerMotDePasse('avant', 'apres');

        expect(client.token, 'jeton');
        expect(client.pseudo, 'nino');
      },
    );

    test(
      'mauvais mot de passe : le serveur le dit, on le rend tel quel',
      () async {
        serveur.reponses['/changer_mdp'] = {
          'ok': false,
          'error': 'Mot de passe incorrect',
        };

        final r = await client.changerMotDePasse('faux', 'apres');

        expect(r.isOk, isFalse);
        expect(r.serverError, 'Mot de passe incorrect');
      },
    );
  });
}
