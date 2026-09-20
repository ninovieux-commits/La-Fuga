/// Messagerie : la liste des conversations, et une conversation.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/messages.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prefs d'une appli déjà lancée une fois : ni choix de langue, ni tuto —
/// ils n'apparaissent qu'au tout premier démarrage.
const Map<String, Object> _launched = {'lang_chosen': true, 'tuto_seen': true};

/// Serveur simulé : répond ce qu'on lui dit, et retient ce qu'on lui envoie.
final class _Server {
  final List<({String path, Map<String, dynamic> body})> calls = [];
  final Map<String, Map<String, dynamic>> replies = {};

  http.Client get client => MockClient((request) async {
    calls.add((
      path: request.url.path,
      body: Map<String, dynamic>.from(jsonDecode(request.body) as Map),
    ));
    return http.Response(
      jsonEncode(replies[request.url.path] ?? {'ok': true}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  bool called(String path) => calls.any((c) => c.path == path);

  Map<String, dynamic> bodyOf(String path) =>
      calls.lastWhere((c) => c.path == path).body;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Server server;
  late OnlineService online;

  setUp(() async {
    SharedPreferences.setMockInitialValues(_launched);
    await Settings.load();
    await Translations.load('fr');
    server = _Server();
    online = OnlineService(
      client: OnlineClient(api: ApiClient(client: server.client)),
    );
  });

  group('Avatar', () {
    test("Deep Grey a sa photo, quelle que soit l'orthographe", () {
      expect(avatarPhotoFor('Deep Grey'), 'deepgrey');
      expect(avatarPhotoFor('  deepgrey '), 'deepgrey');
    });

    test('les autres gardent la leur', () {
      expect(avatarPhotoFor('Nino', 'dragon|Nurse'), 'dragon|Nurse');
      expect(avatarPhotoFor('Nino'), '');
    });
  });

  group('Liste des conversations', () {
    /// Connexion préalable, hors du temps simulé des tests de widgets.
    Future<void> logIn() async {
      server.replies['/login'] = {'ok': true, 'token': 't', 'pseudo': 'Nino'};
      await online.login('Nino', 'mdp');
    }

    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ConversationsScreen(online: online)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('sans compte, on demande la connexion', (tester) async {
      await open(tester);
      expect(find.text('Connexion requise'), findsOneWidget);
      expect(server.called('/list_conversations'), isFalse);
    });

    testWidgets('chaque conversation montre son aperçu et ses non-lus', (
      tester,
    ) async {
      await tester.runAsync(logIn);
      server.replies['/list_conversations'] = {
        'ok': true,
        'conversations': [
          {
            'pseudo': 'Ana',
            'last_text': 'À toi de jouer',
            'unread': 3,
            'last_de_moi': false,
          },
          {'pseudo': 'Bob', 'last_text': 'ok', 'last_de_moi': true},
        ],
      };

      await open(tester);

      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('À toi de jouer'), findsOneWidget);
      expect(find.text('3'), findsOneWidget, reason: 'la pastille des non-lus');
      expect(
        find.text('Vous : ok'),
        findsOneWidget,
        reason: 'mon propre dernier message est préfixé',
      );
    });

    testWidgets('aucune conversation, on le dit', (tester) async {
      await tester.runAsync(logIn);
      server.replies['/list_conversations'] = {
        'ok': true,
        'conversations': const [],
      };

      await open(tester);

      expect(find.text('Aucune conversation pour le moment.'), findsOneWidget);
    });
  });

  group('Conversation', () {
    Future<void> open(WidgetTester tester, {String pseudo = 'Ana'}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(online: online, pseudo: pseudo),
        ),
      );
      await tester.pumpAndSettle();
    }

    setUp(() async {
      server.replies['/login'] = {'ok': true, 'token': 't', 'pseudo': 'Nino'};
      await online.login('Nino', 'mdp');
    });

    testWidgets('ouvrir la conversation la marque comme lue', (tester) async {
      server.replies['/list_conversation'] = {'ok': true, 'messages': []};
      await open(tester);

      expect(server.called('/mark_read'), isTrue);
      expect(server.bodyOf('/mark_read')['pseudo'], 'Ana');
      expect(find.text('Aucun message. Écrivez le premier !'), findsOneWidget);
    });

    testWidgets('les messages s affichent des deux côtés', (tester) async {
      server.replies['/list_conversation'] = {
        'ok': true,
        'messages': [
          {'texte': 'Salut', 'de_moi': false},
          {'texte': 'Salut à toi', 'de_moi': true},
        ],
      };
      await open(tester);

      expect(find.text('Salut'), findsOneWidget);
      expect(find.text('Salut à toi'), findsOneWidget);
    });

    testWidgets('un message envoyé apparaît tout de suite', (tester) async {
      server.replies['/list_conversation'] = {'ok': true, 'messages': []};
      await open(tester);

      await tester.enterText(find.byType(TextField), 'Bien joué');
      await tester.tap(find.text('Envoyer'));
      await tester.pump();

      expect(
        find.text('Bien joué'),
        findsOneWidget,
        reason: 'affichage optimiste, avant la réponse du serveur',
      );

      await tester.pumpAndSettle();
      expect(server.bodyOf('/send_message')['pseudo'], 'Ana');
      expect(server.bodyOf('/send_message')['text'], 'Bien joué');
    });

    testWidgets('un envoi refusé est signalé, pas effacé', (tester) async {
      server.replies['/list_conversation'] = {'ok': true, 'messages': []};
      server.replies['/send_message'] = {'ok': false, 'error': 'bloqué'};
      await open(tester);

      await tester.enterText(find.byType(TextField), 'Coucou');
      await tester.tap(find.text('Envoyer'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Coucou'), findsOneWidget);
      expect(find.textContaining('non envoyé'), findsOneWidget);
    });

    testWidgets('un message vide ne part pas', (tester) async {
      server.replies['/list_conversation'] = {'ok': true, 'messages': []};
      await open(tester);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Envoyer'));
      await tester.pumpAndSettle();

      expect(server.called('/send_message'), isFalse);
    });

    testWidgets('une conversation indisponible le dit', (tester) async {
      server.replies['/list_conversation'] = {'ok': false, 'error': 'oups'};
      await open(tester);

      expect(find.text('Conversation indisponible.'), findsOneWidget);
    });
  });
}
