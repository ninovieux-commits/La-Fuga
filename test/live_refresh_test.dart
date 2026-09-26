/// Un écran ouvert se tient à jour tout seul.
///
/// Nino : « les messages ne marchent toujours pas en direct, on est obligés de
/// quitter la conv et de la relancer. Idem pour les parties en correspondance. »
///
/// Deux causes, pas une.
///
/// La correspondance passe entièrement par HTTP : le serveur n'émet AUCUN
/// événement temps réel pour elle. Le minuteur qui rafraîchit les aperçus
/// vivait dans le menu et nulle part ailleurs, donc une fois entré dans la
/// partie, plus rien ne relisait jamais le serveur. Quitter et revenir était
/// le seul moyen de voir le coup adverse — ce n'était pas un bug mystérieux,
/// c'était l'absence de tout mécanisme.
///
/// La conversation, elle, n'avait QUE l'événement `message_recu` pour se
/// réveiller. Quand il n'arrive pas — socket coupé, réseau mobile qui lâche la
/// connexion sans le dire, application revenue du fond — l'écran restait figé.
///
/// Ces tests n'utilisent délibérément AUCUN socket : ils vérifient que l'écran
/// se met à jour même quand le temps réel ne dit rien. C'est le filet, et c'est
/// lui qui manquait.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:lafuga/ui/screens/corr_game_screen.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Un client HTTP dont les réponses changent au fil des appels.
  ({OnlineClient client, List<String> chemins}) clientQuiRepond(
    Map<String, dynamic> Function(String chemin) repondre,
  ) {
    final chemins = <String>[];
    final client = OnlineClient(
      api: ApiClient(
        client: MockClient((request) async {
          chemins.add(request.url.path);
          return http.Response(
            jsonEncode(repondre(request.url.path)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    return (client: client, chemins: chemins);
  }

  Map<String, dynamic> partie({
    required String coups,
    String statut = 'en_cours',
    bool monTour = false,
  }) => {
    'id': 'g1',
    'statut': statut,
    'adversaire': 'Ana',
    'adversaire_melo': 1600,
    'ma_couleur': 'Blanc',
    'turn': monTour ? 'Blanc' : 'Noir',
    'my_turn': monTour,
    'mon_score': 0,
    'score_adverse': 0,
    'objectif': 'partie',
    'moves_text': coups,
    'is_defieur': false,
  };

  group('Partie de correspondance ouverte', () {
    testWidgets('le coup adverse arrive sans quitter l écran', (tester) async {
      var coups = 'Do2-Do3';
      final faux = clientQuiRepond(
        (chemin) => switch (chemin) {
          '/corr_list' => {
            'ok': true,
            'games': [partie(coups: coups)],
          },
          _ => {'ok': true},
        },
      );
      clearReplayCache();

      final jeu = CorrGame.fromJson(partie(coups: coups));
      await tester.pumpWidget(
        MaterialApp(
          home: CorrGameScreen(
            game: jeu,
            service: CorrespondenceService(faux.client),
            myPseudo: 'nino',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final avant = tester
          .widget<GameBoardView>(find.byType(GameBoardView))
          .board
          .render();

      // L'adversaire joue. Nous ne touchons à rien : ni navigation, ni socket.
      coups = 'Do2-Do3\nDo7-Do6';
      clearReplayCache();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      final apres = tester
          .widget<GameBoardView>(find.byType(GameBoardView))
          .board
          .render();
      expect(
        apres,
        isNot(avant),
        reason:
            'le coup adverse ne s affiche pas : il faut toujours quitter '
            'la partie et y revenir',
      );
      // Et c'est bien SA case qui a changé.
      expect(
        apres.length,
        avant.length,
        reason: 'le plateau n a pas la même forme : relecture cassée',
      );
    });

    testWidgets('sans coup nouveau, le plateau n est pas reconstruit', (
      tester,
    ) async {
      final faux = clientQuiRepond(
        (chemin) => switch (chemin) {
          '/corr_list' => {
            'ok': true,
            'games': [partie(coups: 'Do2-Do3')],
          },
          _ => {'ok': true},
        },
      );
      clearReplayCache();

      await tester.pumpWidget(
        MaterialApp(
          home: CorrGameScreen(
            game: CorrGame.fromJson(partie(coups: 'Do2-Do3')),
            service: CorrespondenceService(faux.client),
            myPseudo: 'nino',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final avant = tester.widget<GameBoardView>(find.byType(GameBoardView));

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(
        tester.widget<GameBoardView>(find.byType(GameBoardView)).board,
        same(avant.board),
        reason:
            'le plateau est reconstruit toutes les quatre secondes pour '
            'rien : la relecture coûte cher et le coup en cours trinque',
      );
      expect(
        faux.chemins.where((c) => c == '/corr_list').length,
        greaterThan(0),
        reason: 'aucune relecture n a été demandée : le test ne prouve rien',
      );
    });

    testWidgets('un coup en cours de composition n est pas effacé', (
      tester,
    ) async {
      // Le danger de toute actualisation automatique : écraser sous le doigt
      // la pièce qu'on est en train de déplacer.
      var coups = 'Do2-Do3';
      final faux = clientQuiRepond(
        (chemin) => switch (chemin) {
          '/corr_list' => {
            'ok': true,
            'games': [partie(coups: coups, monTour: true)],
          },
          _ => {'ok': true},
        },
      );
      clearReplayCache();

      await tester.pumpWidget(
        MaterialApp(
          home: CorrGameScreen(
            game: CorrGame.fromJson(partie(coups: coups, monTour: true)),
            service: CorrespondenceService(faux.client),
            myPseudo: 'nino',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // On commence un coup : une pièce est sélectionnée et déplacée. Le coup
      // est choisi dans les coups LÉGAUX de la position — taper une case au
      // hasard ne sélectionnait rien, et le test ne prouvait alors rien.
      final vue = tester.widget<GameBoardView>(find.byType(GameBoardView));
      // Une PHOTO, pas la référence : le contrôleur mute son plateau en place,
      // et comparer l'objet à lui-même aurait toujours dit « rien n'a changé ».
      final depart = vue.board.render();
      final coup = generateMoves(vue.board, Camp.blanc).firstWhere(
        (m) => m.movedCells.length == 1 && m.movedCells.first.onBoard,
        orElse: () => throw StateError('aucun coup blanc jouable'),
      );
      vue.onTapCell(coup.from);
      await tester.pump();
      vue.onTapCell(coup.movedCells.first);
      await tester.pump();

      final enCours = tester
          .widget<GameBoardView>(find.byType(GameBoardView))
          .board
          .render();
      expect(
        enCours,
        isNot(depart),
        reason: 'aucun coup n est en cours : le test ne prouve rien',
      );

      // Le serveur répond entre-temps ; l'actualisation doit se taire.
      coups = 'Do2-Do3\nDo7-Do6';
      clearReplayCache();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(
        tester.widget<GameBoardView>(find.byType(GameBoardView)).board.render(),
        enCours,
        reason: 'le coup en cours de composition a été effacé sous le doigt',
      );
    });
  });

  group('Conversation ouverte', () {
    testWidgets('un message arrive sans le moindre événement temps réel', (
      tester,
    ) async {
      var messages = <Map<String, dynamic>>[
        {'texte': 'salut', 'de_moi': false, 'created_at': 1},
      ];
      final faux = clientQuiRepond(
        (chemin) => switch (chemin) {
          '/list_conversation' => {'ok': true, 'messages': messages},
          _ => {'ok': true},
        },
      );
      final service = OnlineService(client: faux.client);
      addTearDown(service.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(online: service, pseudo: 'Ana'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('salut'), findsOneWidget);
      expect(find.text('et voilà'), findsNothing);

      // Ana écrit. Le socket ne dit RIEN — c'est tout l'objet du test.
      messages = [
        ...messages,
        {'texte': 'et voilà', 'de_moi': false, 'created_at': 2},
      ];
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(
        find.text('et voilà'),
        findsOneWidget,
        reason:
            'sans événement temps réel, la conversation reste figée : il '
            'faut la quitter et y revenir, ce que Nino décrit',
      );
    });

    testWidgets('rien de neuf : la conversation n est pas redessinée', (
      tester,
    ) async {
      final faux = clientQuiRepond(
        (chemin) => switch (chemin) {
          '/list_conversation' => {
            'ok': true,
            'messages': [
              {'texte': 'salut', 'de_moi': false, 'created_at': 1},
            ],
          },
          _ => {'ok': true},
        },
      );
      final service = OnlineService(client: faux.client);
      addTearDown(service.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(online: service, pseudo: 'Ana'),
        ),
      );
      await tester.pumpAndSettle();
      final lectures = faux.chemins.where((c) => c == '/mark_read').length;

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(
        faux.chemins.where((c) => c == '/list_conversation').length,
        greaterThan(1),
        reason: 'aucune relecture : le test ne prouve rien',
      );
      expect(
        faux.chemins.where((c) => c == '/mark_read').length,
        lectures,
        reason:
            'une écriture serveur toutes les quatre secondes alors que '
            'rien n a changé',
      );
    });
  });

  group('Une réponse vide n est pas une réussite', () {
    test('elle remonte comme une panne de transport', () async {
      final api = ApiClient(
        client: MockClient((_) async => http.Response('', 200)),
      );
      final r = await api.post('/list_conversation', const {});
      expect(r.isOk, isFalse);
      expect(
        r.error,
        isNotNull,
        reason:
            'un corps vide passait pour une réussite sans données : '
            'l appelant y lisait « aucun message »',
      );
      expect(
        r.isNetworkError,
        isTrue,
        reason:
            'le jeton doit rester valide : c est le transport qui a '
            'échoué, pas le serveur qui a refusé',
      );
    });
  });
}
