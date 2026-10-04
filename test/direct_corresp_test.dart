/// La correspondance en direct, et le filet qui reste derrière.
///
/// Nino : « on peut en profiter pour améliorer le système de direct dans les
/// boîtes de messages, dans les parties corresp et éventuellement les aperçus
/// corresp ? »
///
/// La correspondance n'émettait rien. Le serveur n'envoyait que des
/// notifications push — donc rien à une application ouverte, et rien du tout
/// si le joueur avait coupé ses notifications. Les trois écrans concernés
/// n'avaient qu'un recours : redemander la liste toutes les quatre secondes.
///
/// Le serveur prévient maintenant au même endroit qu'il notifie, sous
/// `maj_directe` et avec la même charge utile (`patch_direct.py`, éprouvé par
/// `tests/test_direct.py` : 9/9 en vingt millisecondes, contre 1/9 avant).
/// Ces tests-ci couvrent le côté application : ce qu'on fait de l'événement,
/// et ce qu'on garde comme filet quand il n'arrive pas.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/corr_hub.dart';
import 'package:lafuga/net/filet_relecture.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/net/socket_client.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/corr_game_screen.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Ce que le direct de la correspondance laisse passer', () {
    test('un coup joué arrive, avec la partie qu il concerne', () {
      final hub = CorrHub();
      final vus = <CorrChange>[];
      hub.changes.listen(vus.add);
      hub.receive({'type': 'corr_turn', 'game_id': '42', 'coup': 'Mi2-Mi3'});
      return Future<void>.delayed(Duration.zero, () {
        expect(vus, [(type: 'corr_turn', gameId: '42')]);
      });
    });

    test('tout ce qui touche à la correspondance passe', () {
      for (final type in [
        'corr_turn',
        'corr_fin',
        'corr_nulle',
        'corr_chat',
        'corr_maj',
        'defi_corr',
      ]) {
        expect(
          CorrHub.concerneCorresp(type),
          isTrue,
          reason: '« $type » devrait réveiller les écrans de correspondance',
        );
      }
    });

    test('mais pas un message privé', () {
      // Les messages ont leur propre chemin (`message_recu`, et MessageHub
      // derrière). Les laisser passer ici ferait relire toute la liste des
      // parties à chaque message reçu.
      expect(CorrHub.concerneCorresp('message'), isFalse);
    });

    test('et un événement sans type est ignoré', () async {
      final hub = CorrHub();
      final vus = <CorrChange>[];
      hub.changes.listen(vus.add);
      hub.receive({});
      hub.receive({'type': ''});
      hub.receive({'type': 'message', 'sender': 'Ana'});
      await Future<void>.delayed(Duration.zero);
      expect(vus, isEmpty);
    });

    test('sans game_id, le changement passe quand même', () async {
      // Un écran qui suit UNE partie l'ignorera ; le menu, lui, relira sa
      // liste. Mieux vaut un rafraîchissement de trop qu'un aperçu figé.
      final hub = CorrHub();
      final vus = <CorrChange>[];
      hub.changes.listen(vus.add);
      hub.receive({'type': 'defi_corr'});
      await Future<void>.delayed(Duration.zero);
      expect(vus, [(type: 'defi_corr', gameId: '')]);
    });

    test('l événement écouté est bien celui du serveur', () {
      expect(FugaEvents.majDirecte, 'maj_directe');
      expect(
        FugaEvents.all,
        contains(FugaEvents.majDirecte),
        reason: 'sans cela la connexion ne le transmettrait à personne',
      );
    });
  });

  group('Le filet derrière le temps réel', () {
    final t0 = DateTime(2026, 10, 4, 12, 0, 0);

    test('sans direct, on relit à chaque battement', () {
      final filet = FiletRelecture();
      filet.note(t0);
      // Même juste après une relecture : si la socket est morte, c'est le
      // seul moyen d'apprendre quoi que ce soit.
      expect(
        filet.fautRelire(
          directVivant: false,
          maintenant: t0.add(const Duration(seconds: 4)),
        ),
        isTrue,
      );
    });

    test('avec le direct, on espace', () {
      final filet = FiletRelecture();
      filet.note(t0);
      expect(
        filet.fautRelire(
          directVivant: true,
          maintenant: t0.add(const Duration(seconds: 4)),
        ),
        isFalse,
        reason: 'le direct a déjà prévenu : cette requête ne sert à rien',
      );
      expect(
        filet.fautRelire(
          directVivant: true,
          maintenant: t0.add(const Duration(seconds: 29)),
        ),
        isFalse,
      );
      expect(
        filet.fautRelire(
          directVivant: true,
          maintenant: t0.add(const Duration(seconds: 30)),
        ),
        isTrue,
        reason: 'au bout de trente secondes on rattrape ce qu il aurait manqué',
      );
    });

    test('la toute première relecture part tout de suite', () {
      expect(FiletRelecture().fautRelire(directVivant: true), isTrue);
    });

    test('et la socket qui tombe fait reprendre le rythme rapide', () {
      final filet = FiletRelecture();
      filet.note(t0);
      final juste = t0.add(const Duration(seconds: 1));
      expect(filet.fautRelire(directVivant: true, maintenant: juste), isFalse);
      expect(filet.fautRelire(directVivant: false, maintenant: juste), isTrue);
    });
  });

  group('La partie ouverte se réveille sur le direct', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'lang_chosen': true,
        'tuto_seen': true,
      });
      await Settings.load();
      await Translations.load('fr');
      // Une instance neuve : le hub d'une autre épreuve garderait ses
      // abonnés.
      OnlineService.instance = OnlineService();
    });

    testWidgets('le coup adverse apparaît sans attendre le battement', (
      tester,
    ) async {
      var coups = 'Do2-Do3';
      final appels = <String>[];
      final client = OnlineClient(
        api: ApiClient(
          client: MockClient((request) async {
            appels.add(request.url.path);
            return http.Response(
              jsonEncode({
                'ok': true,
                'games': [
                  {
                    'id': 'g1',
                    'statut': 'en_cours',
                    'adversaire': 'Ana',
                    'adversaire_melo': 1600,
                    'ma_couleur': 'Blanc',
                    'turn': 'Noir',
                    'my_turn': false,
                    'mon_score': 0,
                    'score_adverse': 0,
                    'objectif': 'partie',
                    'moves_text': coups,
                    'is_defieur': false,
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );
      clearReplayCache();

      await tester.pumpWidget(
        MaterialApp(
          home: CorrGameScreen(
            game: CorrGame.fromJson({
              'id': 'g1',
              'statut': 'en_cours',
              'adversaire': 'Ana',
              'adversaire_melo': 1600,
              'ma_couleur': 'Blanc',
              'turn': 'Noir',
              'my_turn': false,
              'mon_score': 0,
              'score_adverse': 0,
              'objectif': 'partie',
              'moves_text': coups,
              'is_defieur': false,
            }),
            service: CorrespondenceService(client),
            myPseudo: 'nino',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final avant = tester
          .widget<GameBoardView>(find.byType(GameBoardView))
          .board
          .render();

      // L'adversaire joue, et le serveur le dit tout de suite.
      coups = 'Do2-Do3\nDo7-Do6';
      clearReplayCache();
      OnlineService.instance.corr.receive({
        'type': 'corr_turn',
        'game_id': 'g1',
      });
      // UNE SECONDE : bien avant le battement de quatre, qui aurait fini par
      // le voir de toute façon. C'est le direct qu'on mesure, pas le filet.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(
        tester.widget<GameBoardView>(find.byType(GameBoardView)).board.render(),
        isNot(avant),
        reason: 'le coup adverse aurait dû arriver par le direct',
      );
    });

    testWidgets('mais pas sur une AUTRE partie', (tester) async {
      var appels = 0;
      final client = OnlineClient(
        api: ApiClient(
          client: MockClient((request) async {
            appels++;
            return http.Response(
              jsonEncode({
                'ok': true,
                'games': [
                  {
                    'id': 'g1',
                    'statut': 'en_cours',
                    'adversaire': 'Ana',
                    'adversaire_melo': 1600,
                    'ma_couleur': 'Blanc',
                    'turn': 'Noir',
                    'my_turn': false,
                    'mon_score': 0,
                    'score_adverse': 0,
                    'objectif': 'partie',
                    'moves_text': 'Do2-Do3',
                    'is_defieur': false,
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );
      clearReplayCache();
      await tester.pumpWidget(
        MaterialApp(
          home: CorrGameScreen(
            game: CorrGame.fromJson({
              'id': 'g1',
              'statut': 'en_cours',
              'adversaire': 'Ana',
              'adversaire_melo': 1600,
              'ma_couleur': 'Blanc',
              'turn': 'Noir',
              'my_turn': false,
              'mon_score': 0,
              'score_adverse': 0,
              'objectif': 'partie',
              'moves_text': 'Do2-Do3',
              'is_defieur': false,
            }),
            service: CorrespondenceService(client),
            myPseudo: 'nino',
          ),
        ),
      );
      await tester.pumpAndSettle();
      appels = 0;

      OnlineService.instance.corr.receive({
        'type': 'corr_turn',
        'game_id': 'une-autre',
      });
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(
        appels,
        0,
        reason: 'un coup joué ailleurs ne doit pas redessiner ce plateau',
      );
    });
  });
}
