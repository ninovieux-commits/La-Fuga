/// Voir un message depuis la partie ne vaut PAS l'avoir lu.
///
/// Nino : « Quand on voit le message depuis la partie comme ça, le message ne
/// doit pas être considéré comme lu. Les pastilles rouges doivent rester
/// jusqu'à ce qu'on ait ouvert la boîte. »
///
/// La bulle en jeu ne reçoit que des textes — un `Stream<String>` — et n'a
/// donc aucun moyen de toucher à la boîte aux lettres. C'est voulu : la
/// lecture se décide dans la conversation, et nulle part ailleurs. Ces tests
/// le tiennent de bout en bout, à l'écran : la pastille s'allume, la bulle
/// passe et s'efface, la pastille est toujours là, et le serveur n'a reçu
/// aucun `/mark_read`.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:lafuga/ui/screens/corr_game_screen.dart';
import 'package:lafuga/ui/screens/online_game_screen.dart';
import 'package:lafuga/ui/widgets/bulles_en_jeu.dart';
import 'package:lafuga/ui/widgets/unread_dot.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_game_test.dart' show FakeSocket, makeGame;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
  });

  Map<String, dynamic> partie() => {
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
  };

  /// Une partie de correspondance ouverte contre Ana, et le compte des
  /// chemins que le serveur a vus passer.
  Future<List<String>> ouvrePartie(WidgetTester tester) async {
    final chemins = <String>[];
    final client = OnlineClient(
      api: ApiClient(
        client: MockClient((request) async {
          chemins.add(request.url.path);
          return http.Response(
            jsonEncode(switch (request.url.path) {
              '/corr_list' => {
                'ok': true,
                'games': [partie()],
              },
              '/list_conversation' => {'ok': true, 'messages': const []},
              _ => {'ok': true},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    OnlineService.instance = OnlineService(client: client);
    clearReplayCache();
    await tester.pumpWidget(
      MaterialApp(
        home: CorrGameScreen(
          game: CorrGame.fromJson(partie()),
          service: CorrespondenceService(client),
          myPseudo: 'nino',
        ),
      ),
    );
    await tester.pumpAndSettle();
    return chemins;
  }

  /// La pastille de la touche « Chat » est-elle allumée ?
  bool pastilleAllumee(WidgetTester tester) {
    final dot = find.ancestor(
      of: find.text('Chat'),
      matching: find.byType(UnreadDot),
    );
    expect(dot, findsOneWidget, reason: 'la touche Chat a perdu sa pastille');
    return tester.widget<UnreadDot>(dot).show;
  }

  group('En correspondance', () {
    testWidgets('la bulle paraît, la pastille s allume', (tester) async {
      await ouvrePartie(tester);
      expect(
        pastilleAllumee(tester),
        isFalse,
        reason: 'rien à signaler encore',
      );

      OnlineService.instance.messages.receive({'de': 'Ana', 'texte': 'coucou'});
      await tester.pumpAndSettle();

      expect(
        find.text('coucou'),
        findsOneWidget,
        reason: 'la bulle doit passer',
      );
      expect(
        pastilleAllumee(tester),
        isTrue,
        reason: 'un message non lu, donc la pastille',
      );
    });

    testWidgets('la bulle s efface, la pastille RESTE', (tester) async {
      await ouvrePartie(tester);
      OnlineService.instance.messages.receive({'de': 'Ana', 'texte': 'coucou'});
      await tester.pumpAndSettle();

      // Les cinq secondes passent, et un peu plus.
      await tester.pump(kBulleEnJeuDuree + const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(
        find.text('coucou'),
        findsNothing,
        reason: 'la bulle a fait son temps',
      );
      expect(
        pastilleAllumee(tester),
        isTrue,
        reason: 'avoir VU la bulle ne vaut pas avoir lu le message',
      );
      expect(
        OnlineService.instance.messages.unreadFrom('Ana'),
        1,
        reason: 'le non-lu doit rester entier',
      );
    });

    testWidgets('le serveur ne reçoit AUCUN mark_read', (tester) async {
      final chemins = await ouvrePartie(tester);
      OnlineService.instance.messages.receive({'de': 'Ana', 'texte': 'un'});
      await tester.pumpAndSettle();
      OnlineService.instance.messages.receive({'de': 'Ana', 'texte': 'deux'});
      await tester.pump(kBulleEnJeuDuree + const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(
        chemins,
        isNot(contains('/mark_read')),
        reason: 'la partie déclarerait les messages lus à notre place',
      );
      expect(
        OnlineService.instance.messages.unreadFrom('Ana'),
        2,
        reason: 'deux messages vus en jeu, deux messages encore à lire',
      );
    });

    testWidgets('ouvrir la BOÎTE, et là seulement, éteint la pastille', (
      tester,
    ) async {
      // Sans quoi les trois tests d'au-dessus passeraient même si la pastille
      // ne s'éteignait jamais.
      final chemins = await ouvrePartie(tester);
      OnlineService.instance.messages.receive({'de': 'Ana', 'texte': 'coucou'});
      await tester.pumpAndSettle();
      expect(pastilleAllumee(tester), isTrue);

      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationScreen), findsOneWidget);
      expect(chemins, contains('/mark_read'), reason: 'la boîte, elle, le dit');

      // On revient à la partie : plus rien à signaler.
      Navigator.of(tester.element(find.byType(ConversationScreen))).pop();
      await tester.pumpAndSettle();
      expect(pastilleAllumee(tester), isFalse);
      expect(OnlineService.instance.messages.unreadFrom('Ana'), 0);
    });
  });

  group('En ligne', () {
    /// Une partie en ligne contre « Adversaire », et les chemins vus passer.
    Future<List<String>> ouvrePartieEnLigne(WidgetTester tester) async {
      final chemins = <String>[];
      final client = OnlineClient(
        api: ApiClient(
          client: MockClient((request) async {
            chemins.add(request.url.path);
            return http.Response(
              jsonEncode({'ok': true, 'messages': const []}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );
      OnlineService.instance = OnlineService(client: client);
      await tester.pumpWidget(
        MaterialApp(
          home: OnlineGameScreen(
            game: makeGame(socket: FakeSocket()),
            myPseudo: 'Nino',
          ),
        ),
      );
      await tester.pumpAndSettle();
      return chemins;
    }

    testWidgets('la bulle passe, la pastille reste, rien n est déclaré lu', (
      tester,
    ) async {
      final chemins = await ouvrePartieEnLigne(tester);
      expect(pastilleAllumee(tester), isFalse);

      OnlineService.instance.messages.receive({
        'de': 'Adversaire',
        'texte': 'coucou',
      });
      await tester.pumpAndSettle();
      expect(find.text('coucou'), findsOneWidget);
      expect(pastilleAllumee(tester), isTrue);

      await tester.pump(kBulleEnJeuDuree + const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('coucou'), findsNothing);
      expect(
        pastilleAllumee(tester),
        isTrue,
        reason: 'avoir VU la bulle ne vaut pas avoir lu le message',
      );
      expect(OnlineService.instance.messages.unreadFrom('Adversaire'), 1);
      expect(chemins, isNot(contains('/mark_read')));
    });

    testWidgets('ouvrir la boîte éteint la pastille', (tester) async {
      final chemins = await ouvrePartieEnLigne(tester);
      OnlineService.instance.messages.receive({
        'de': 'Adversaire',
        'texte': 'coucou',
      });
      await tester.pumpAndSettle();
      expect(pastilleAllumee(tester), isTrue);

      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationScreen), findsOneWidget);
      expect(chemins, contains('/mark_read'));

      Navigator.of(tester.element(find.byType(ConversationScreen))).pop();
      await tester.pumpAndSettle();
      expect(pastilleAllumee(tester), isFalse);
      expect(OnlineService.instance.messages.unreadFrom('Adversaire'), 0);
    });
  });
}
