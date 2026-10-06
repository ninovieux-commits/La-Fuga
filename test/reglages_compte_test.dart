/// Les réglages appartiennent au JOUEUR, pas au téléphone.
///
/// Nino : « le choix de l'instrument doit être enregistré dans le compte du
/// joueur », puis « je voudrais que la vitesse de glissée par défaut dans l'app
/// corresponde à ce réglage et que le choix de l'utilisateur à ce propos soit
/// embarqué avec son compte. »
///
/// Il suivait l'appareil : changer de téléphone, ou se reconnecter après une
/// réinstallation, et l'on retrouvait le piano. Deux règles, et la seconde est
/// celle qu'on oublie :
///
///   — le compte GAGNE sur l'appareil, c'est tout l'intérêt de l'y enregistrer ;
///   — sauf quand le compte n'a rien — un compte d'avant, ou tout juste créé —
///     et c'est alors l'appareil qui le lui donne.
///
/// Sans la seconde, créer un compte remettrait le piano à quelqu'un qui venait
/// de choisir la harpe.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_realtime.dart';

/// Un serveur de papier : il note ce qu'on lui envoie et répond ce qu'on veut.
final class _Serveur {
  final List<({String path, Map<String, dynamic> body})> appels = [];

  /// Réponse par chemin ; à défaut, `{'ok': true}`.
  final Map<String, Map<String, dynamic>> reponses = {};

  /// Chemins auxquels répondre 404 — un serveur pas encore corrigé.
  final Set<String> absents = {};

  http.Client get client => MockClient((request) async {
    final chemin = request.url.path;
    appels.add((
      path: chemin,
      body: Map<String, dynamic>.from(
        jsonDecode(request.body) as Map<String, dynamic>,
      ),
    ));
    if (absents.contains(chemin)) {
      return http.Response('<html>404</html>', 404);
    }
    return http.Response(
      jsonEncode(reponses[chemin] ?? {'ok': true}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  bool aAppele(String chemin) => appels.any((a) => a.path == chemin);

  Map<String, dynamic> corps(String chemin) =>
      appels.lastWhere((a) => a.path == chemin).body;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Serveur serveur;
  late OnlineClient client;

  /// Ouvre une session en se connectant, avec les réglages que le compte porte.
  Future<OnlineService> seConnecter({
    required String surLAppareil,
    required String dansLeCompte,
    bool serveurCorrige = true,
    double glisseeLocale = kGlisseeDefaut,
    double? glisseeDuCompte,
  }) async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'instrument': surLAppareil,
      'slide_speed': glisseeLocale,
    });
    await Settings.load();
    serveur = _Serveur();
    serveur.reponses['/login'] = {
      'ok': true,
      'token': 'jeton',
      'pseudo': 'nino',
      'melo': 1500,
      'theme': 'original',
      // Un compte d'avant ne porte pas la clé du tout : c'est le cas vide.
      if (dansLeCompte.isNotEmpty) 'instrument': dansLeCompte,
      if (glisseeDuCompte != null) 'glissee': glisseeDuCompte,
    };
    if (!serveurCorrige) {
      serveur.absents.add('/set_instrument');
      serveur.absents.add('/set_glissee');
    }
    client = OnlineClient(api: ApiClient(client: serveur.client));
    final service = OnlineService(
      client: client,
      settings: Settings.instance,
      socketFactory: (_) => FakeRealtime(),
    );
    await service.login('nino', 'motdepasse');
    return service;
  }

  group('La route', () {
    setUp(() {
      serveur = _Serveur();
      client = OnlineClient(api: ApiClient(client: serveur.client));
    });

    test('elle envoie le bon chemin et la bonne clé', () async {
      await client.setInstrument('harpe');
      expect(serveur.appels.last.path, '/set_instrument');
      expect(serveur.appels.last.body['instrument'], 'harpe');
      expect(
        serveur.appels.last.body.containsKey('token'),
        isTrue,
        reason: 'la route est authentifiée',
      );
    });

    test('la session retient l instrument envoyé', () async {
      serveur.reponses['/login'] = {
        'ok': true,
        'token': 'jeton',
        'pseudo': 'nino',
        'instrument': 'piano',
      };
      await client.login('nino', 'motdepasse');
      expect(client.session!.instrument, 'piano');
      await client.setInstrument('cloche');
      expect(client.session!.instrument, 'cloche');
    });

    test('un compte sans instrument donne une chaîne VIDE, pas le piano', () {
      // C'est ce vide qui distingue « ce compte veut le piano » de « ce compte
      // n a jamais rien dit ». Les confondre ferait écraser le choix de
      // l'appareil à chaque connexion d'un ancien compte.
      serveur.reponses['/login'] = {
        'ok': true,
        'token': 'jeton',
        'pseudo': 'nino',
      };
      return client.login('nino', 'motdepasse').then((_) {
        expect(client.session!.instrument, isEmpty);
      });
    });
  });

  group('À la connexion, le compte gagne', () {
    test('l instrument du compte remplace celui de l appareil', () async {
      await seConnecter(surLAppareil: 'piano', dansLeCompte: 'harpe');
      expect(
        Settings.instance.instrument,
        'harpe',
        reason: 'c est tout l intérêt de l enregistrer dans le compte',
      );
    });

    test('et rien n est renvoyé au serveur : il le savait déjà', () async {
      await seConnecter(surLAppareil: 'piano', dansLeCompte: 'harpe');
      expect(serveur.aAppele('/set_instrument'), isFalse);
    });

    test('le même instrument des deux côtés ne provoque rien', () async {
      await seConnecter(surLAppareil: 'orgue', dansLeCompte: 'orgue');
      expect(Settings.instance.instrument, 'orgue');
      expect(serveur.aAppele('/set_instrument'), isFalse);
    });
  });

  group('Un compte sans instrument reçoit celui de l appareil', () {
    test('il est envoyé au serveur', () async {
      await seConnecter(surLAppareil: 'xylophone', dansLeCompte: '');
      expect(serveur.aAppele('/set_instrument'), isTrue);
      expect(serveur.corps('/set_instrument')['instrument'], 'xylophone');
    });

    test('et le réglage local n est PAS écrasé', () async {
      // Le piège : prendre le vide du compte pour un choix, et remettre le
      // premier instrument de la liste à quelqu'un qui en avait choisi un.
      await seConnecter(surLAppareil: 'xylophone', dansLeCompte: '');
      expect(Settings.instance.instrument, 'xylophone');
    });
  });

  group('Un serveur pas encore corrigé', () {
    test('le 404 ne casse rien, et le réglage local tient', () async {
      await seConnecter(
        surLAppareil: 'guitare',
        dansLeCompte: '',
        serveurCorrige: false,
      );
      expect(
        Settings.instance.instrument,
        'guitare',
        reason: 'on ne perd rien : on ne gagne pas la mémoire du compte',
      );
    });
  });

  group('La vitesse de glissée, même histoire', () {
    test('le défaut est celui relevé sur la capture de Nino', () async {
      // Mesuré au pixel : pouce à 238, piste de 84 à 995, curseur jusqu'à 0,6.
      // L'ancien défaut, 0,18 s, était presque deux fois plus lent.
      expect(kGlisseeDefaut, 0.10);
      SharedPreferences.setMockInitialValues({'lang_chosen': true});
      await Settings.load();
      expect(Settings.instance.slideSpeed, kGlisseeDefaut);
    });

    test('la route envoie le bon chemin et la bonne clé', () async {
      final srv = _Serveur();
      final cli = OnlineClient(api: ApiClient(client: srv.client));
      await cli.setGlissee(0.25);
      expect(srv.appels.last.path, '/set_glissee');
      expect(srv.appels.last.body['glissee'], 0.25);
    });

    testWidgets('celle du compte remplace celle de l appareil', (tester) async {
      await seConnecter(
        surLAppareil: 'piano',
        dansLeCompte: 'piano',
        glisseeLocale: 0.10,
        glisseeDuCompte: 0.42,
      );
      expect(Settings.instance.slideSpeed, 0.42);
      expect(serveur.aAppele('/set_glissee'), isFalse);
    });

    testWidgets('un compte qui n a rien dit reçoit celle de l appareil', (
      tester,
    ) async {
      await seConnecter(
        surLAppareil: 'piano',
        dansLeCompte: 'piano',
        glisseeLocale: 0.30,
      );
      expect(serveur.aAppele('/set_glissee'), isTrue);
      expect(serveur.corps('/set_glissee')['glissee'], 0.30);
      expect(
        Settings.instance.slideSpeed,
        0.30,
        reason: 'le réglage local ne doit pas être écrasé',
      );
    });

    testWidgets('zéro est un CHOIX, pas une absence', (tester) async {
      // Glissée instantanée. Le piège serait de la confondre avec « ce compte
      // n a rien dit » et de la remplacer par celle de l appareil.
      await seConnecter(
        surLAppareil: 'piano',
        dansLeCompte: 'piano',
        glisseeLocale: 0.30,
        glisseeDuCompte: 0,
      );
      expect(Settings.instance.slideSpeed, 0);
      expect(serveur.aAppele('/set_glissee'), isFalse);
    });

    testWidgets('un serveur pas encore corrigé ne casse rien', (tester) async {
      await seConnecter(
        surLAppareil: 'piano',
        dansLeCompte: 'piano',
        glisseeLocale: 0.30,
        serveurCorrige: false,
      );
      expect(Settings.instance.slideSpeed, 0.30);
    });
  });
}
