/// Le mélo doit TOUJOURS se mettre à jour.
///
/// Nino : « la mise à jour du mélo foire parfois. Elle doit toujours
/// s'effectuer. »
///
/// Elle ne s'effectuait en réalité jamais. Le mélo était lu au login, puis
/// plus jamais : l'écran de fin de partie affichait bien le nouveau
/// classement — il le tient de `melo_maj` — mais la session gardait l'ancien,
/// et le menu l'affichait tel quel. Il fallait se déconnecter et se
/// reconnecter. D'où le « parfois » : juste après la partie c'était bon, de
/// retour au menu c'était faux.
///
/// Deux chemins désormais, et les deux comptent : `melo_maj` pour que ce soit
/// juste tout de suite, `auth_ok` pour que ce le soit quand même quand
/// l'annonce s'est perdue.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/net/socket_client.dart';
import 'package:lafuga/state/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_realtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRealtime socket;
  late OnlineService online;
  late List<String> appels;
  late int meloServeur;
  late int meloRandomServeur;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    appels = [];
    meloServeur = 1500;
    meloRandomServeur = 1500;
    socket = FakeRealtime();

    final faux = MockClient((request) async {
      appels.add(request.url.path);
      return http.Response(
        jsonEncode(switch (request.url.path) {
          '/login' => {
            'ok': true,
            'token': 'jeton',
            'pseudo': 'Nino',
            'melo': 1500,
            'melo_random': 1500,
            'theme': 'original',
          },
          '/get_profile' => {
            'ok': true,
            'pseudo': 'Nino',
            'melo': meloServeur,
            'melo_random': meloRandomServeur,
            'photo': '',
          },
          _ => {'ok': true},
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    online = OnlineService(
      client: OnlineClient(api: ApiClient(client: faux)),
      socketFactory: (_) => socket,
    );
    await online.login('Nino', 'motdepasse');
    await online.connectSocket();
    appels.clear();
  });

  group('Après une partie classée', () {
    test('le mélo de la session suit — il restait bloqué au login', () async {
      expect(online.session!.melo, 1500);

      meloServeur = 1516;
      socket.emit(FugaEvents.meloMaj, {'mon_melo': 1516, 'delta': 16});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(online.session!.melo, 1516);
      expect(
        appels,
        contains('/get_profile'),
        reason: 'melo_maj ne dit pas LEQUEL des deux classements a bougé',
      );
    });

    test('et le classement Random aussi, qui est un autre compteur', () async {
      meloRandomServeur = 1470;
      socket.emit(FugaEvents.meloMaj, {'mon_melo': 1470, 'delta': -30});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(online.session!.meloRandom, 1470);
      expect(online.session!.melo, 1500, reason: 'le classé n a pas bougé');
    });

    test('le menu est prévenu', () async {
      var signaux = 0;
      online.revisionMelo.addListener(() => signaux++);

      meloServeur = 1532;
      socket.emit(FugaEvents.meloMaj, {'mon_melo': 1532, 'delta': 32});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(signaux, 1, reason: 'sans signal, le bouton Compte reste figé');
    });

    test(
      'et le téléphone le retient : un redémarrage ne l oublie pas',
      () async {
        meloServeur = 1544;
        socket.emit(FugaEvents.meloMaj, {'mon_melo': 1544, 'delta': 44});
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await Settings.load();
        expect(Settings.instance.onlineMelo, 1544);
      },
    );
  });

  group('Et quand l annonce se perd', () {
    test('la reconnexion rattrape : auth_ok porte les deux', () async {
      // Application tuée en fin de partie, socket coupée avant « melo_maj »,
      // partie finie pendant que le téléphone dormait : dans tous ces cas,
      // c'est la connexion suivante qui doit remettre les compteurs d'aplomb.
      socket.emit(FugaEvents.authOk, {
        'pseudo': 'Nino',
        'melo': 1601,
        'melo_random': 1399,
        'theme': 'original',
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(online.session!.melo, 1601);
      expect(online.session!.meloRandom, 1399);
      expect(
        appels,
        isNot(contains('/get_profile')),
        reason: 'auth_ok porte déjà les deux : pas besoin de redemander',
      );
    });

    test(
      'mais sans changement, on n écrit rien et on ne réveille personne',
      () async {
        var signaux = 0;
        online.revisionMelo.addListener(() => signaux++);
        socket.emit(FugaEvents.authOk, {
          'pseudo': 'Nino',
          'melo': 1500,
          'melo_random': 1500,
          'theme': 'original',
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(signaux, 0);
      },
    );
  });
}
