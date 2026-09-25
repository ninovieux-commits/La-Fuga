/// Les parties jouées contre quelqu'un entrent dans l'historique EN LIGNE.
///
/// Kivy range TOUTES ses parties depuis le même endroit, correspondance
/// comprise : `online_<id>` pour une partie directe, `online_corr<id>` pour
/// une partie par correspondance, et le préfixe `online_` les réunit dans le
/// même historique. Ce port ne rangeait que les parties de l'écran de jeu
/// local — les parties en ligne et par correspondance n'entraient donc dans
/// l'historique de personne, ni le nôtre ni celui de l'adversaire.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/game/game_archive.dart';
import 'package:lafuga/i18n/translations.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/ui/screens/corr_game_screen.dart';
import 'package:lafuga/ui/screens/history_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_realtime.dart';

/// Un compte qui retient ce qu'on lui range.
final class _Account implements AccountGames {
  final List<Map<String, dynamic>> saved = [];

  @override
  bool get isLoggedIn => true;

  @override
  Future<void> saveGame(Map<String, dynamic> data) async => saved.add(data);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    clearReplayCache();
  });

  group('L identifiant range la partie du bon côté', () {
    test('une partie par correspondance est une partie EN LIGNE', () {
      final archive = buildOpponentArchive(
        myPseudo: 'Nino',
        opponent: 'Ana',
        myCamp: Camp.blanc,
        winner: Camp.blanc,
        method: 'fugue',
        history: const ['Do1-Do2'],
        corrGameId: '42',
      );
      expect(archive.uid, 'online_corr42');
      expect(
        archive.uid.startsWith('online_'),
        isTrue,
        reason: "c'est le préfixe que lit l'historique en ligne",
      );
    });

    test('une partie directe aussi', () {
      final archive = buildOpponentArchive(
        myPseudo: 'Nino',
        opponent: 'Ana',
        myCamp: Camp.noir,
        winner: Camp.noir,
        method: 'mat',
        history: const ['Do8-Do7'],
        onlineGameId: 'g7',
      );
      expect(archive.uid, 'online_g7');
    });

    test('le Blanc est le premier joueur, comme chez Kivy', () {
      final jeBlanc = buildOpponentArchive(
        myPseudo: 'Nino',
        opponent: 'Ana',
        myCamp: Camp.blanc,
        winner: Camp.blanc,
        method: 'fugue',
        history: const ['Do1-Do2'],
        corrGameId: '1',
      );
      expect(jeBlanc.meta.player1, 'Nino');
      expect(jeBlanc.meta.player2, 'Ana');
      expect(jeBlanc.meta.blanc, 'Nino');
      expect(jeBlanc.meta.result, '1-0');

      final jeNoir = buildOpponentArchive(
        myPseudo: 'Nino',
        opponent: 'Ana',
        myCamp: Camp.noir,
        winner: Camp.noir,
        method: 'fugue',
        history: const ['Do8-Do7'],
        corrGameId: '2',
      );
      expect(jeNoir.meta.player1, 'Ana', reason: 'Ana tient les Blancs');
      expect(jeNoir.meta.blanc, 'Ana');
      expect(
        jeNoir.meta.result,
        '0-1',
        reason: 'le second joueur, donc les Noirs, a gagné',
      );
    });

    test('une nulle se note ½-½', () {
      final archive = buildOpponentArchive(
        myPseudo: 'Nino',
        opponent: 'Ana',
        myCamp: Camp.blanc,
        winner: null,
        method: 'nulle',
        history: const ['Do1-Do2'],
        corrGameId: '3',
      );
      expect(archive.meta.result, '½-½');
    });
  });

  group('L écran de correspondance range la partie', () {
    CorrGame gameOf({
      required String statut,
      String moves = '',
      bool? won,
      String method = '',
    }) => CorrGame.fromJson({
      'id': '42',
      'statut': statut,
      'ma_couleur': 'Blanc',
      'adversaire': 'Ana',
      'turn': 'Blanc',
      'moves_text': moves,
      'my_turn': true,
      'resultat': won == null ? 'nulle' : (won ? '1-0' : '0-1'),
      'methode': method,
      'gagne': won,
    });

    Future<_Account> open(WidgetTester tester, CorrGame game) async {
      final account = _Account();
      await tester.pumpWidget(
        MaterialApp(
          home: CorrGameScreen(
            game: game,
            service: CorrespondenceService(OnlineClient(api: ApiClient())),
            myPseudo: 'Nino',
            archive: GameArchive(account: account),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return account;
    }

    testWidgets('une partie close par l adversaire y entre à l ouverture', (
      tester,
    ) async {
      final account = await open(
        tester,
        gameOf(
          statut: 'termine',
          moves: 'Fa1-Fa2\nFa8-Fa7',
          won: false,
          method: 'fugue',
        ),
      );

      expect(account.saved, hasLength(1), reason: 'rangée une seule fois');
      final saved = account.saved.single;
      expect(saved['game_uid'], 'online_corr42');
      expect(saved['joueur1'], 'Nino', reason: 'je tiens les Blancs');
      expect(saved['joueur2'], 'Ana');
      expect(saved['resultat'], '0-1', reason: 'Ana a gagné');
      expect(saved['methode'], 'fugue');
      expect('${saved['nmc_text']}', contains('Fa1-Fa2'));
      expect('${saved['nmc_text']}', contains('Fa8-Fa7'));
    });

    testWidgets('une partie en cours n y entre pas', (tester) async {
      final account = await open(
        tester,
        gameOf(statut: 'en_cours', moves: 'Fa1-Fa2'),
      );
      expect(account.saved, isEmpty);
    });
  });

  group('Les scores « Moi contre » ouvrent la bonne liste', () {
    /// Une partie telle que le serveur la rend dans `/list_games`.
    Map<String, dynamic> served(String uid, {String against = 'Ana'}) => {
      'game_uid': uid,
      'joueur1': 'Nino',
      'joueur2': against,
      'resultat': '1-0',
      'methode': 'fugue',
      'date': '2026-09-25 10:00',
    };

    Future<void> open(
      WidgetTester tester,
      List<Map<String, dynamic>> games,
      String mode,
    ) async {
      final calls = <Map<String, dynamic>>[];
      final online = OnlineService(
        client: OnlineClient(
          api: ApiClient(
            client: MockClient((request) async {
              calls.add(
                Map<String, dynamic>.from(jsonDecode(request.body) as Map),
              );
              return http.Response(
                jsonEncode({'ok': true, 'games': games}),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
          ),
        ),
        socketFactory: (_) => FakeRealtime(),
      );
      await online.login('Nino', 'mdp');
      await tester.pumpWidget(
        MaterialApp(
          home: HistoryScreen(online: online, opponent: 'Ana', h2hMode: mode),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Nombre de parties affichées : chaque carte nomme ses deux joueurs,
    /// « Nino  vs  Ana ».
    int rows(WidgetTester tester) =>
        find.textContaining(' vs ').evaluate().length;

    testWidgets('en correspondance, seule la partie corr est retenue', (
      tester,
    ) async {
      await open(tester, [
        served('online_corr42'),
        served('online_g7'),
        served('local_abc'),
        served('online_corr99', against: 'Quelqu un d autre'),
      ], 'corr');

      expect(find.textContaining('Aucune'), findsNothing);
      expect(
        rows(tester),
        1,
        reason:
            'la partie directe, la locale et celle contre un tiers sont '
            'écartées',
      );
    });

    testWidgets('en direct, la partie corr est écartée', (tester) async {
      await open(tester, [served('online_corr42')], 'direct');
      expect(
        find.textContaining('Aucune'),
        findsOneWidget,
        reason: 'la seule partie entre nous est une correspondance',
      );
    });
  });
}
