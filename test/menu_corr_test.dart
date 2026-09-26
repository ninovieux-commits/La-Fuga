/// Les emplacements de correspondance, sur le menu — comme en Kivy.
library;

import 'dart:async';
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
import 'package:lafuga/net/avatar_photos.dart';
import 'package:lafuga/ui/widgets/corr_slot.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:lafuga/ui/widgets/player_panel.dart';
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

  /// Quand elle n'est pas nulle, le serveur simulé attend qu'elle se réalise
  /// avant de répondre.
  Future<void>? slowdown;

  setUp(() async {
    SharedPreferences.setMockInitialValues(_launched);
    await Settings.load();
    await Translations.load('fr');

    socket = FakeRealtime();
    calls = [];
    replies = {
      '/login': {'ok': true, 'token': 't', 'pseudo': 'Nino', 'melo': 1600},
    };
    slowdown = null;
    final client = MockClient((request) async {
      calls.add((
        path: request.url.path,
        body: Map<String, dynamic>.from(jsonDecode(request.body) as Map),
      ));
      // Permet à un test de laisser une demande en l'air.
      if (slowdown != null) await slowdown;
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
    // Les écrans de partie lisent `OnlineService.instance` — ma photo hier,
    // celle de l'adversaire aujourd'hui. Sans ce branchement, le test
    // interrogerait un service vide et ne prouverait rien.
    OnlineService.instance = online;
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

  testWidgets('annuler un défi ENVOYÉ passe par l abandon, pas par la réponse', (
    tester,
  ) async {
    // Le serveur refuse `corr_repondre` au défieur — « Vous êtes le défieur » —
    // et c'est pour ça que la touche ne faisait rien. Kivy annule par
    // l'abandon, qui accepte le statut « defi ».
    replies['/corr_list'] = {
      'ok': true,
      'games': [game(statut: 'defi', myTurn: false, isDefieur: true)],
    };
    await open(tester);

    expect(find.text('En attente…'), findsOneWidget);
    await tapVisible(tester, find.text('Annuler'));

    expect(
      bodyOf('/corr_abandon'),
      isNotNull,
      reason: 'la touche Annuler n a appelé aucune route d abandon',
    );
    expect(bodyOf('/corr_abandon')!['game_id'], 'g1');
    expect(
      bodyOf('/corr_repondre'),
      isNull,
      reason:
          'corr_repondre est refusé au défieur : la touche resterait sans '
          'effet, exactement le bug signalé',
    );
  });

  testWidgets('la photo de l adversaire s affiche en correspondance', (
    tester,
  ) async {
    // Ni `corr_list` ni `partie_trouvee` ne portent la photo de l'adversaire :
    // il faut aller la chercher par son profil, comme Kivy. Sans ça, l'avatar
    // d'en face restait la pièce par défaut.
    AvatarPhotos.clear();
    replies['/corr_list'] = {
      'ok': true,
      'games': [game()],
    };
    replies['/get_profile'] = {'ok': true, 'pseudo': 'Ana', 'photo': 'nurse'};
    await open(tester);
    await tapVisible(tester, find.byType(CorrSlot).first);
    await tester.pumpAndSettle();

    final panneaux = tester
        .widgetList<PlayerPanel>(find.byType(PlayerPanel))
        .toList();
    expect(panneaux.length, 2, reason: 'les deux panneaux de joueur');
    expect(
      panneaux.map((p) => p.photo),
      contains('nurse'),
      reason:
          'aucun panneau ne porte la photo de l adversaire : '
          '${panneaux.map((p) => p.photo).toList()}',
    );
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

  testWidgets('la liste se tient à jour sans touche « Actualiser »', (
    tester,
  ) async {
    replies['/corr_list'] = {
      'ok': true,
      'games': [game()],
    };
    await open(tester);

    // Comme sur les sites de jeu : rien à toucher, ça s'actualise tout seul.
    expect(find.text('Actualiser'), findsNothing);
    final first = calls.where((c) => c.path == '/corr_list').length;
    expect(first, greaterThan(0), reason: 'la liste arrive à l ouverture');

    // Le battement redemande la liste sans qu'on ait rien fait, et souvent :
    // un coup de l'adversaire doit apparaître pendant qu'on regarde la grille.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(
      calls.where((c) => c.path == '/corr_list').length,
      greaterThan(first),
      reason: 'cinq secondes suffisent',
    );
  });

  testWidgets('en arrière-plan, le battement s arrête', (tester) async {
    replies['/corr_list'] = {
      'ok': true,
      'games': [game()],
    };
    await open(tester);

    int corrCalls() => calls.where((c) => c.path == '/corr_list').length;

    // L'application quitte le premier plan : interroger le serveur toutes les
    // quatre secondes pour un écran que personne ne regarde ne sert à rien.
    // Le passage doit suivre les étapes réelles d'Android.
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    final endormi = corrCalls();
    await tester.pump(const Duration(seconds: 20));
    await tester.pumpAndSettle();
    expect(corrCalls(), endormi, reason: 'plus rien ne part');

    // De retour, la liste se remet à jour tout de suite, et le battement
    // repart.
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(corrCalls(), greaterThan(endormi), reason: 'mise à jour immédiate');
    final reveille = corrCalls();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(corrCalls(), greaterThan(reveille), reason: 'le battement repart');
  });

  testWidgets('une demande lente n en fait pas partir dix', (tester) async {
    replies['/corr_list'] = {
      'ok': true,
      'games': [game()],
    };
    await open(tester);

    // Le serveur ne répond plus : la demande reste en l'air.
    final bloque = Completer<void>();
    slowdown = bloque.future;
    addTearDown(() {
      if (!bloque.isCompleted) bloque.complete();
    });

    final avant = calls.where((c) => c.path == '/corr_list').length;
    // Quatre battements passent pendant que la première demande attend.
    await tester.pump(const Duration(seconds: 17));
    expect(
      calls.where((c) => c.path == '/corr_list').length,
      avant + 1,
      reason: 'une seule demande en l air à la fois',
    );

    bloque.complete();
    await tester.pumpAndSettle();
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
