/// Les emplacements de correspondance, sur le menu — comme en Kivy.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/corr_game_screen.dart';
import 'package:lafuga/ui/screens/menu_screen.dart';
import 'package:lafuga/ui/widgets/corr_slot.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_realtime.dart';

/// Prefs d'une appli déjà lancée une fois : ni choix de langue, ni tuto —
/// ils n'apparaissent qu'au tout premier démarrage.
const Map<String, Object> _launched = {'lang_chosen': true, 'tuto_seen': true};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRealtime socket;
  late OnlineService online;
  late Map<String, Map<String, dynamic>> replies;
  late List<({String path, Map<String, dynamic> body})> calls;

  setUp(() async {
    SharedPreferences.setMockInitialValues(_launched);
    await Settings.load();
    await Translations.load('fr');

    socket = FakeRealtime();
    calls = [];
    replies = {
      '/login': {'ok': true, 'token': 't', 'pseudo': 'Nino', 'melo': 1600},
    };
    final client = MockClient((request) async {
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
    online = OnlineService(
      client: OnlineClient(api: ApiClient(client: client)),
      socketFactory: (_) => socket,
    );
    await online.login('Nino', 'mdp');
  });

  Map<String, dynamic> game({
    String id = 'g1',
    String statut = 'en_cours',
    bool myTurn = true,
    bool isDefieur = false,
  }) => {
    'id': id,
    'statut': statut,
    'adversaire': 'Ana',
    'adversaire_melo': 1700,
    'ma_couleur': 'Blanc',
    'trait': 'Blanc',
    'my_turn': myTurn,
    'mon_score': 2,
    'score_adverse': 1,
    'is_defieur': isDefieur,
    'moves_text': '',
  };

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: MenuScreen(online: online)));
    await tester.pumpAndSettle();
  }

  /// Les plateaux sont en bas du menu : on les amène à l'écran avant de
  /// les toucher.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Map<String, dynamic>? bodyOf(String path) {
    for (final c in calls.reversed) {
      if (c.path == path) return c.body;
    }
    return null;
  }

  testWidgets('une partie en cours montre l adversaire, le score et le tour', (
    tester,
  ) async {
    replies['/corr_list'] = {
      'ok': true,
      'games': [game()],
    };
    await open(tester);

    expect(find.textContaining('Ana'), findsWidgets);
    expect(find.textContaining('2 - 1'), findsOneWidget);
    expect(find.text('À vous de jouer'), findsOneWidget);
  });

  testWidgets('un défi reçu propose Accepter et Refuser', (tester) async {
    replies['/corr_list'] = {
      'ok': true,
      'games': [game(statut: 'defi', myTurn: false)],
    };
    await open(tester);

    expect(find.textContaining('vous défie'), findsOneWidget);
    await tapVisible(tester, find.text('Accepter'));

    expect(bodyOf('/corr_repondre')!['game_id'], 'g1');
    expect(bodyOf('/corr_repondre')!['accepte'], isTrue);
  });

  testWidgets('un défi envoyé attend, et s annule', (tester) async {
    replies['/corr_list'] = {
      'ok': true,
      'games': [game(statut: 'defi', myTurn: false, isDefieur: true)],
    };
    await open(tester);

    expect(find.text('En attente…'), findsOneWidget);
    await tapVisible(tester, find.text('Annuler'));

    expect(bodyOf('/corr_repondre')!['accepte'], isFalse);
  });

  testWidgets('une partie terminée se referme', (tester) async {
    replies['/corr_list'] = {
      'ok': true,
      'games': [
        {...game(statut: 'termine', myTurn: false), 'resultat': '1-0'},
      ],
    };
    await open(tester);

    expect(find.text('Fermer'), findsOneWidget);
    await tapVisible(tester, find.text('Fermer'));

    expect(bodyOf('/corr_close')!['game_id'], 'g1');
  });

  testWidgets('toucher une partie en cours l ouvre', (tester) async {
    replies['/corr_list'] = {
      'ok': true,
      'games': [game()],
    };
    await open(tester);

    await tapVisible(tester, find.byType(CorrSlot).first);

    expect(find.byType(CorrGameScreen), findsOneWidget);
  });

  testWidgets('la partie de correspondance offre les touches de Kivy', (
    tester,
  ) async {
    replies['/corr_list'] = {
      'ok': true,
      'games': [game()],
    };
    await open(tester);
    await tapVisible(tester, find.byType(CorrSlot).first);

    // `_update_action_buttons` : chat ET analyse en correspondance.
    expect(find.text('< >'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Analyser'), findsOneWidget);
    expect(find.text('Deep Grey'), findsNothing);
    expect(find.text('Rapide'), findsNothing);

    // `_update_side_buttons` : abandon de mon côté, pas de ½ — le temps est
    // illimité, on abandonne si ça traîne.
    expect(find.byTooltip('Abandonner'), findsOneWidget);
    expect(find.byTooltip('Proposer nulle'), findsNothing);
  });

  testWidgets('après avoir joué, on reste sur la partie', (tester) async {
    replies['/corr_list'] = {
      'ok': true,
      'games': [game()],
    };
    await open(tester);
    await tapVisible(tester, find.byType(CorrSlot).first);

    // Un coup blanc quelconque : sélectionner, déplacer, revalider.
    final view = tester.widget<GameBoardView>(find.byType(GameBoardView));
    final move = generateMoves(
      view.board,
      Camp.blanc,
    ).firstWhere((m) => m.movedCells.length == 1 && m.movedCells.first.onBoard);
    view.onTapCell(move.from);
    await tester.pump();
    view.onTapCell(move.movedCells.first);
    await tester.pump();
    view.onTapCell(move.movedCells.first);
    await tester.pumpAndSettle();

    expect(bodyOf('/corr_jouer')!['game_id'], 'g1');
    // Kivy laisse le joueur devant sa position : on ne le renvoie pas au menu.
    expect(find.byType(CorrGameScreen), findsOneWidget);
    expect(find.byType(MenuScreen), findsNothing);
  });

  testWidgets('une case vide propose de défier un favori', (tester) async {
    replies['/corr_list'] = {'ok': true, 'games': const []};
    replies['/list_favorites'] = {
      'ok': true,
      'favorites': [
        {'pseudo': 'Bob', 'melo': 1450, 'online': true},
      ],
    };
    await open(tester);

    // Sans partie, la grille montre deux cases vides.
    expect(find.byType(CorrSlot), findsNWidgets(2));
    await tapVisible(tester, find.byType(CorrSlot).first);

    expect(find.textContaining('Défier un favori'), findsOneWidget);
    // Le nom est un bouton à part : il mène au profil, il ne défie pas.
    expect(
      find.ancestor(of: find.text('Bob'), matching: find.byType(TextButton)),
      findsOneWidget,
    );
    await tapVisible(tester, find.text('Défier'));

    expect(bodyOf('/corr_defier')!['pseudo'], 'Bob');
  });
}
