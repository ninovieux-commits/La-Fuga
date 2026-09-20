/// Le menu, côté serveur : matchmaking et défis, sans serveur.
///
/// Comme en Kivy, tout part du menu : pas d'écran de salon.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/net/socket_client.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/menu_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_realtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRealtime socket;
  late OnlineService online;
  late Map<String, Map<String, dynamic>> replies;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.load();
    await Translations.load('fr');

    socket = FakeRealtime();
    replies = {
      '/login': {'ok': true, 'token': 't', 'pseudo': 'Nino', 'melo': 1600},
    };
    final client = MockClient((request) async {
      final body = jsonEncode(replies[request.url.path] ?? {'ok': true});
      return http.Response(
        body,
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    online = OnlineService(
      client: OnlineClient(api: ApiClient(client: client)),
      socketFactory: (_) => socket,
    );
    await online.login('Nino', 'mdp');
    await online.connectSocket();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: MenuScreen(online: online)));
    await tester.pumpAndSettle();
  }

  /// Cherche un joueur : on valide le champ, comme en Kivy.
  Future<void> searchFor(WidgetTester tester, String pseudo) async {
    await tester.enterText(find.byType(TextField).first, pseudo);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  group('Matchmaking', () {
    testWidgets('chercher une partie envoie objectif, cadence et random', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.text('Jouer en ligne'));
      await tester.pumpAndSettle();

      expect(socket.lastOf('chercher_partie')!['cadence'], '15');
      expect(socket.lastOf('chercher_partie')!['objectif'], 'partie');
      expect(find.textContaining("Recherche d'un adversaire"), findsOneWidget);
      expect(find.text('Annuler'), findsOneWidget);
    });

    testWidgets('annuler la recherche prévient le serveur', (tester) async {
      await open(tester);
      await tester.tap(find.text('Jouer en ligne'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(socket.didSend('annuler_recherche'), isTrue);
      expect(find.text('Jouer en ligne'), findsOneWidget);
    });
  });

  group('Défis', () {
    testWidgets('chercher un joueur ouvre sa fiche, puis on le défie', (
      tester,
    ) async {
      replies['/search_user'] = {
        'ok': true,
        'pseudo': 'Ana',
        'melo': 1700,
        'melo_random': 1400,
        'online': true,
        'h2h_direct_moi': 2,
        'h2h_direct_lui': 1,
      };
      await open(tester);

      await searchFor(tester, 'Ana');

      // « Ana » est aussi dans le champ de recherche : la fiche s'ajoute.
      expect(find.text('Ana'), findsNWidgets(2));
      expect(find.textContaining('1700'), findsOneWidget);
      expect(find.textContaining('2 - 1'), findsOneWidget);

      await tester.tap(find.text('Défier'));
      await tester.pumpAndSettle();

      expect(socket.lastOf('defier')!['pseudo_cible'], 'Ana');
      expect(find.textContaining('En attente de sa réponse.'), findsOneWidget);
    });

    testWidgets('un refus referme l attente et le dit', (tester) async {
      replies['/search_user'] = {'ok': true, 'pseudo': 'Ana'};
      await open(tester);
      await searchFor(tester, 'Ana');
      await tester.tap(find.text('Défier'));
      await tester.pumpAndSettle();

      socket.emit(FugaEvents.defiRefuse, {'cible': 'Ana'});
      await tester.pumpAndSettle();

      expect(
        find.textContaining('En attente de sa réponse.'),
        findsNothing,
        reason: 'le popup d attente se referme',
      );
      expect(find.textContaining('a refusé votre défi'), findsOneWidget);
      expect(
        find.byType(MenuScreen),
        findsOneWidget,
        reason: 'et le menu reste ouvert',
      );
    });

    testWidgets('une cible indisponible est signalée', (tester) async {
      replies['/search_user'] = {'ok': true, 'pseudo': 'Ana'};
      await open(tester);
      await searchFor(tester, 'Ana');
      await tester.tap(find.text('Défier'));
      await tester.pumpAndSettle();

      socket.emit(FugaEvents.defiEchec, {'raison': 'bloque'});
      await tester.pumpAndSettle();

      expect(find.textContaining('blocage'), findsOneWidget);
    });

    testWidgets('un défi reçu se refuse, et la réponse part', (tester) async {
      await open(tester);

      socket.emit(FugaEvents.defiRecu, {
        'defi_id': 'd7',
        'defieur': 'Bob',
        'defieur_melo': 1610,
        'cadence': '5',
      });
      await tester.pumpAndSettle();

      expect(find.textContaining('Bob'), findsOneWidget);
      expect(find.textContaining('vous défie'), findsOneWidget);

      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();

      expect(socket.lastOf('repondre_defi'), {
        'defi_id': 'd7',
        'accepte': false,
      });
    });

    testWidgets('un joueur introuvable ne bloque rien', (tester) async {
      replies['/search_user'] = {'ok': false, 'error': 'inconnu'};
      await open(tester);

      await searchFor(tester, 'Zzz');

      expect(find.textContaining('introuvable'), findsOneWidget);
      expect(socket.didSend('defier'), isFalse);
    });
  });
}
