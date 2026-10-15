/// La devise de l'adversaire, montrée à l'ouverture de la partie.
///
/// Nino : « j'aimerai qu'au début d'une partie direct et à chaque fois qu'une
/// correspondance est ouverte, la devise du joueur apparaisse quelques
/// secondes sur la partie comme les messages. Mais ça ne doit pas apparaître
/// dans la boîte de chat. »
///
/// La dernière phrase est celle qui décide de tout : la devise n'est PAS un
/// message. Elle ne passe par aucun envoi, elle n'entre pas dans la
/// conversation, et le serveur de messages n'en entend jamais parler. Elle
/// est posée directement dans la bande des bulles de l'écran de jeu.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/clock.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/avatar_photos.dart';
import 'package:lafuga/net/decors_connus.dart';
import 'package:lafuga/net/devises_connues.dart';
import 'package:lafuga/net/favoris_connus.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/net/scores_directs.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/corr_game_screen.dart';
import 'package:lafuga/ui/screens/online_game_screen.dart';
import 'package:lafuga/ui/widgets/message_bubble.dart';
import 'package:lafuga/ui/widgets/player_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_game_test.dart' show FakeSocket, makeGame;

const String kSaDevise = 'Je joue vite et mal.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> chemins;
  late OnlineClient client;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    AvatarPhotos.clear();
    DecorsConnus.clear();
    DevisesConnues.clear();
    ScoresDirects.clear();
    FavorisConnus.instance.oublie();

    chemins = [];
    client = OnlineClient(
      api: ApiClient(
        client: MockClient((req) async {
          chemins.add(req.url.path);
          return http.Response(
            jsonEncode({
              'ok': true,
              'token': 't',
              'pseudo': 'nino',
              'melo': 1530,
              // Le profil de l'adversaire : c'est lui qui porte la devise.
              'description': kSaDevise,
              'theme': 'original',
              'photo': 'nurse',
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    final online = OnlineService(client: client);
    await online.client.login('nino', 'mdp');
    final precedent = OnlineService.instance;
    OnlineService.instance = online;
    addTearDown(() => OnlineService.instance = precedent);
  });
  tearDown(DevisesConnues.clear);

  Map<String, dynamic> partieJson() => const {
    'id': 'g1',
    'statut': 'en_cours',
    'adversaire': 'Ana',
    'adversaire_melo': 1600,
    'ma_couleur': 'Blanc',
    'turn': 'Blanc',
    'my_turn': true,
    'mon_score': 0,
    'score_adverse': 0,
    'objectif': 'partie',
    'moves_text': '',
    'is_defieur': false,
  };

  Future<void> correspondance(
    WidgetTester tester, {
    bool visiteur = false,
  }) async {
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: CorrGameScreen(
          game: CorrGame.fromJson(partieJson()),
          service: CorrespondenceService(client),
          myPseudo: 'nino',
          visiteur: visiteur,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> direct(WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: OnlineGameScreen(
          game: makeGame(
            socket: FakeSocket(),
            myCamp: Camp.blanc,
            cadence: Cadence.quinze,
          ),
          myPseudo: 'nino',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Elle paraît sur la partie', () {
    testWidgets('au début d une partie en DIRECT', (tester) async {
      await direct(tester);
      expect(find.text(kSaDevise), findsOneWidget);
      expect(
        tester.widget<MessageBubble>(find.byType(MessageBubble)).deMoi,
        isFalse,
        reason: 'c est SA devise : elle paraît comme un mot de lui',
      );
    });

    testWidgets('et à CHAQUE ouverture d une correspondance', (tester) async {
      // « À chaque fois qu'une correspondance est ouverte » : une partie de
      // correspondance s'ouvre et se referme vingt fois.
      await correspondance(tester);
      expect(find.text(kSaDevise), findsOneWidget);

      // On referme, on rouvre : elle revient, même si le profil est déjà en
      // cache et qu'aucune requête n'est repartie.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      await correspondance(tester);
      expect(
        find.text(kSaDevise),
        findsOneWidget,
        reason: 'elle doit reparaître à la deuxième ouverture',
      );
    });

    testWidgets('elle s efface comme un message', (tester) async {
      await direct(tester);
      expect(find.text(kSaDevise), findsOneWidget);
      await tester.pump(const Duration(seconds: 8));
      await tester.pump();
      expect(find.text(kSaDevise), findsNothing);
    });

    testWidgets('pas de devise, pas de bulle', (tester) async {
      DevisesConnues.retiens('Ana', '');
      await correspondance(tester);
      expect(find.byType(MessageBubble), findsNothing);
    });

    testWidgets('et JAMAIS en visiteur', (tester) async {
      // On regarde jouer deux autres personnes : leur bande ne nous dit rien.
      await correspondance(tester, visiteur: true);
      expect(find.text(kSaDevise), findsNothing);
    });
  });

  group('Mais elle n est pas un message', () {
    testWidgets('elle ne part par AUCUN envoi', (tester) async {
      // « Ça ne doit pas apparaître dans la boîte de chat. » Elle n'est pas
      // envoyée : elle est posée dans la bande, et là seulement.
      await correspondance(tester);
      expect(find.text(kSaDevise), findsOneWidget);
      expect(
        chemins.where((c) => c == '/send_message'),
        isEmpty,
        reason: 'une devise envoyée se retrouverait dans la conversation',
      );
    });
  });

  group('Mon mélo', () {
    testWidgets('est écrit sous mon pseudo, comme le sien', (tester) async {
      // Nino : « j'aimerai que mon mélo soit affiché (comme celui de mon
      // adversaire) ».
      await correspondance(tester);
      final panneaux = tester
          .widgetList<PlayerPanel>(find.byType(PlayerPanel))
          .toList();
      expect(panneaux.length, 2);
      expect(
        panneaux.map((p) => p.rating),
        containsAll(<String>['1530', '1600']),
        reason: 'le mien ET le sien : ${panneaux.map((p) => p.rating)}',
      );
    });
  });
}
