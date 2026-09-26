/// Le client parle-t-il vraiment au serveur ? Contrôle contre un vrai serveur.
///
/// Toute la suite réseau passe par `MockClient` : elle vérifie que le client
/// sait lire une réponse qu'on lui donne, jamais que le serveur donne bien
/// celle-là. Ce test-ci ne simule rien — vrai `ApiClient`, vraies requêtes.
///
///   cd .../serveur && mkdir -p /tmp/S && cp tests/run_seeded.py server.py /tmp/S/
///   ( cd /tmp/S && PORT=5171 python3 run_seeded.py & )
///   LAFUGA_TEST_SERVER=http://127.0.0.1:5171 flutter test test/live_server_test.dart
///
/// Sans serveur il s'annonce ignoré plutôt que de passer pour rien.
///
/// ── CE QU'IL NE PEUT PAS FAIRE ────────────────────────────────────────────
/// Le SOCKET n'est pas testable ici. `flutter test` remplace le client HTTP
/// (toute requête répond 400, corps vide — d'où le `HttpOverrides.global =
/// null` ci-dessous), et même une fois cette substitution levée,
/// `socket_io_client` ne se connecte pas depuis le harnais de test : ni
/// `onConnect` ni `onConnectError` ne se déclenchent, la connexion reste
/// simplement en suspens. Vérifié en comparant notre `FugaSocket` au paquet
/// brut : les deux se taisent, alors qu'un client Python se connecte au même
/// serveur et reçoit bien `message_recu`.
///
/// C'est la raison pour laquelle aucun test n'a jamais couvert le chemin
/// « serveur → socket → application », et pourquoi les écrans ne doivent pas
/// dépendre du seul temps réel pour se mettre à jour (cf. `live_refresh_test`).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/messages.dart';
import 'package:lafuga/state/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final base = Platform.environment['LAFUGA_TEST_SERVER'];

  setUp(() async {
    // Sans cela, `flutter test` intercepte toute requête et répond 400 avec un
    // corps vide : le client croirait le serveur en panne.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
  });

  group('Serveur réel', () {
    if (base == null || base.isEmpty) {
      test(
        'ignoré : pas de LAFUGA_TEST_SERVER',
        () {},
        skip: 'LAFUGA_TEST_SERVER non défini',
      );
      return;
    }

    /// Inscrit un compte, ou se connecte s'il existe déjà.
    Future<OnlineClient> ouvrir(String pseudo) async {
      final client = OnlineClient(api: ApiClient(serverUrl: base));
      final inscription = await client.register(pseudo, 'motdepasse');
      if (!inscription.isOk) {
        final connexion = await client.login(pseudo, 'motdepasse');
        expect(
          connexion.isOk,
          isTrue,
          reason: 'connexion refusée : ${connexion.serverError}',
        );
      }
      return client;
    }

    testWidgets(
      'un message envoyé se retrouve dans la conversation',
      (tester) async {
        // `runAsync` : du temps réel, pas l'horloge simulée des tests.
        await tester.runAsync(() async {
          final n = DateTime.now().millisecondsSinceEpoch % 100000;
          final a = await ouvrir('LiveA$n');
          final b = await ouvrir('LiveB$n');
          addTearDown(a.close);
          addTearDown(b.close);

          final envoi = await a.sendMessage('LiveB$n', 'coucou du test');
          expect(envoi.isOk, isTrue, reason: 'envoi refusé : ${envoi.error}');

          final conv = await b.listConversation('LiveA$n');
          expect(
            conv.isOk,
            isTrue,
            reason: 'relecture refusée : ${conv.error}',
          );
          final messages = [
            for (final m in conv.get<List<dynamic>>('messages') ?? const [])
              if (m is Map) ChatMessage.fromJson(Map<String, dynamic>.from(m)),
          ];
          expect(
            messages.map((m) => m.text),
            contains('coucou du test'),
            reason:
                'le serveur ne rend pas le message que le client vient de '
                'lui confier',
          );
        });
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );

    testWidgets(
      'la liste des correspondances se lit',
      (tester) async {
        await tester.runAsync(() async {
          final n = DateTime.now().millisecondsSinceEpoch % 100000;
          final a = await ouvrir('LiveC$n');
          addTearDown(a.close);
          final r = await a.corrList();
          expect(r.isOk, isTrue, reason: 'corr_list refusé : ${r.error}');
          expect(
            r.get<List<dynamic>>('games'),
            isNotNull,
            reason:
                'le champ « games » manque : la relecture périodique de '
                'l écran de partie ne trouverait jamais sa partie',
          );
        });
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  });
}
