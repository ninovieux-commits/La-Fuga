/// Salon en ligne : matchmaking et défis, sans serveur.
library;

import 'dart:async';
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
import 'package:lafuga/ui/screens/online_lobby_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Connexion temps réel simulée.
final class _FakeRealtime implements RealtimeSocket {
  final Map<String, void Function(Map<String, dynamic>)> handlers = {};
  final List<({String name, Map<String, dynamic> data})> sent = [];
  final StreamController<bool> _state = StreamController<bool>.broadcast();

  @override
  bool isConnected = true;

  @override
  Stream<bool> get onConnectionChanged => _state.stream;

  void emit(String event, Map<String, dynamic> data) =>
      handlers[event]?.call(data);

  bool didSend(String name) => sent.any((e) => e.name == name);

  Map<String, dynamic>? lastOf(String name) {
    for (final e in sent.reversed) {
      if (e.name == name) return e.data;
    }
    return null;
  }

  void _record(String name, [Map<String, dynamic> data = const {}]) =>
      sent.add((name: name, data: data));

  @override
  void on(String event, void Function(Map<String, dynamic>) handler) =>
      handlers[event] = handler;

  @override
  void off(String event) => handlers.remove(event);

  @override
  Future<void> connect(String token) async => isConnected = true;

  @override
  void disconnect() => isConnected = false;

  @override
  void dispose() => _state.close();

  @override
  void chercherPartie({
    required String objectif,
    required String cadence,
    bool random = false,
  }) => _record('chercher_partie', {
    'objectif': objectif,
    'cadence': cadence,
    'random': random,
  });

  @override
  void annulerRecherche() => _record('annuler_recherche');

  @override
  void defier({
    required String pseudoCible,
    required String objectif,
    required String cadence,
    bool random = false,
  }) => _record('defier', {
    'pseudo_cible': pseudoCible,
    'objectif': objectif,
    'cadence': cadence,
    'random': random,
  });

  @override
  void annulerDefi(String defiId) =>
      _record('annuler_defi', {'defi_id': defiId});

  @override
  void repondreDefi(String defiId, bool accepte) =>
      _record('repondre_defi', {'defi_id': defiId, 'accepte': accepte});

  @override
  void jouerCoup({
    required String gameId,
    required String notation,
    int? clockBlanc,
    int? clockNoir,
    int? clockMe,
  }) => _record('jouer_coup');

  @override
  void proposerNulle(String gameId) => _record('proposer_nulle');

  @override
  void finPartie({
    required String gameId,
    required String methode,
    String? loserColor,
  }) => _record('fin_partie');

  @override
  void chat(String gameId, String texte) => _record('chat');

  @override
  void pretPartieSuivante(String gameId) => _record('pret_partie_suivante');

  @override
  void abandonnerMatch(String gameId) => _record('abandonner_match');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRealtime socket;
  late OnlineService online;
  late Map<String, Map<String, dynamic>> replies;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.load();
    await Translations.load('fr');

    socket = _FakeRealtime();
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
    await tester.pumpWidget(
      MaterialApp(home: OnlineLobbyScreen(online: online)),
    );
    await tester.pumpAndSettle();
  }

  group('Matchmaking', () {
    testWidgets('chercher une partie envoie objectif, cadence et random', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.text('Chercher une partie'));
      // Pas de pumpAndSettle : l'indicateur de recherche tourne sans fin.
      await tester.pump();

      expect(socket.lastOf('chercher_partie')!['cadence'], '15');
      expect(socket.lastOf('chercher_partie')!['objectif'], 'partie');
      expect(find.text('Annuler'), findsOneWidget);
    });

    testWidgets('annuler la recherche prévient le serveur', (tester) async {
      await open(tester);
      await tester.tap(find.text('Chercher une partie'));
      await tester.pump();

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(socket.didSend('annuler_recherche'), isTrue);
      expect(find.text('Chercher une partie'), findsOneWidget);
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

      await tester.enterText(find.byType(TextField), 'Ana');
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

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
      await tester.enterText(find.byType(TextField), 'Ana');
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
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
        find.byType(OnlineLobbyScreen),
        findsOneWidget,
        reason: 'et le salon reste ouvert',
      );
    });

    testWidgets('une cible indisponible est signalée', (tester) async {
      replies['/search_user'] = {'ok': true, 'pseudo': 'Ana'};
      await open(tester);
      await tester.enterText(find.byType(TextField), 'Ana');
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
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

      await tester.enterText(find.byType(TextField), 'Zzz');
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      expect(find.textContaining('introuvable'), findsOneWidget);
      expect(socket.didSend('defier'), isFalse);
    });
  });
}
