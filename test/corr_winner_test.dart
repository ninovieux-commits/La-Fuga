/// Qui gagne une partie de correspondance, et où elle se range.
///
/// Nino : « quand c'est ton adversaire qui joue le coup qui te fait gagner
/// (te fugue ou se mate), ça lui donne la victoire. Puis la partie n'apparaît
/// pas dans l'historique. »
///
/// DEUX bugs, et le second n'était pas celui qu'il croyait.
///
/// 1. Le gagnant n'est pas toujours celui qui joue. Pousser l'Héritier ADVERSE
///    dans son ralliement le fait fuguer, donc gagner ; éjecter son PROPRE
///    Héritier est un mat contre soi-même. Le serveur ne peut pas le déduire
///    du coup — il écrivait `winner_uid = me["id"]` — donc le client le lui
///    dit maintenant.
///
/// 2. L'historique : ce n'est pas le `.nmc`. Le serveur archivait la partie
///    sous `corr_<id>`, un identifiant qui ne commence ni par `online_` ni par
///    `local_` : aucun des deux onglets ne le montrait. La partie était bien
///    enregistrée, et invisible.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/corr_game_screen.dart';
import 'package:lafuga/ui/screens/history_screen.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<({String path, Map<String, dynamic> body})> appels;
  late Map<String, Map<String, dynamic>> reponses;
  late OnlineClient client;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    clearReplayCache();

    appels = [];
    reponses = {};
    client = OnlineClient(
      api: ApiClient(
        client: MockClient((request) async {
          appels.add((
            path: request.url.path,
            body: Map<String, dynamic>.from(
              jsonDecode(request.body) as Map<String, dynamic>,
            ),
          ));
          return http.Response(
            jsonEncode(reponses[request.url.path] ?? {'ok': true}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
  });

  Map<String, dynamic>? corps(String chemin) {
    for (final a in appels.reversed) {
      if (a.path == chemin) return a.body;
    }
    return null;
  }

  group('Le coup qui fait gagner l ADVERSAIRE', () {
    testWidgets('pousser son Héritier dans son ralliement : il gagne', (
      tester,
    ) async {
      // Je suis Noir. Je pousse l'Héritier BLANC dans le ralliement blanc :
      // il fugue, donc il gagne, alors que c'est moi qui joue.
      final depart = Board.empty();
      depart.set(3, 7, Piece.blancHeritier);
      depart.set(2, 5, const Piece(PieceType.garde, Camp.noir));
      depart.set(1, 5, const Piece(PieceType.garde, Camp.noir));
      depart.set(0, 0, Piece.noirHeritier);

      // Le coup gagnant existe-t-il vraiment dans cette position ?
      final gagnant = generateMoves(
        depart,
        Camp.noir,
      ).where((m) => m.fugueBy == Camp.blanc).toList();
      expect(
        gagnant,
        isNotEmpty,
        reason: 'aucune poussée gagnante : test vain',
      );

      final jeu = CorrGame.fromJson({
        'id': 'g9',
        'statut': 'en_cours',
        'adversaire': 'Ana',
        'ma_couleur': 'Noir',
        'turn': 'Noir',
        'my_turn': true,
        'moves_text': '',
        'objectif': 'partie',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: CorrGameScreen(
            game: jeu,
            service: CorrespondenceService(client),
            myPseudo: 'nino',
            initialBoard: depart,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Une poussée se joue en trois gestes : la pièce, sa case d'arrivée —
      // le déplacement en diagonale active la poussée du Garde — puis la case
      // à pousser. Ce troisième geste envoie l'Héritier dans son ralliement et
      // clôt la partie sur-le-champ.
      final vue = tester.widget<GameBoardView>(find.byType(GameBoardView));
      final coup = gagnant.first;
      vue.onTapCell(coup.from);
      await tester.pump();
      vue.onTapCell(coup.to);
      await tester.pump();
      vue.onTapCell(const Cell(3, 7));
      await tester.pumpAndSettle();

      final envoi = corps('/corr_jouer');
      expect(envoi, isNotNull, reason: 'le coup n a pas été envoyé');
      expect(envoi!['methode'], 'fugue');
      expect(
        envoi['gagnant'],
        'Blanc',
        reason:
            'le serveur ne peut pas deviner qui gagne : sans ce champ il '
            'donne la partie à celui qui vient de jouer, donc au perdant',
      );
    });

    testWidgets('un coup ordinaire n annonce aucun gagnant', (tester) async {
      final jeu = CorrGame.fromJson({
        'id': 'g9',
        'statut': 'en_cours',
        'adversaire': 'Ana',
        'ma_couleur': 'Blanc',
        'turn': 'Blanc',
        'my_turn': true,
        'moves_text': '',
        'objectif': 'partie',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: CorrGameScreen(
            game: jeu,
            service: CorrespondenceService(client),
            myPseudo: 'nino',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final vue = tester.widget<GameBoardView>(find.byType(GameBoardView));
      final coup = generateMoves(vue.board, Camp.blanc).firstWhere(
        (m) => m.movedCells.length == 1 && m.movedCells.first.onBoard,
      );
      vue.onTapCell(coup.from);
      await tester.pump();
      vue.onTapCell(coup.movedCells.first);
      await tester.pump();
      vue.onTapCell(coup.movedCells.first);
      await tester.pumpAndSettle();

      final envoi = corps('/corr_jouer');
      expect(envoi, isNotNull);
      expect(envoi!.containsKey('methode'), isFalse);
      expect(
        envoi.containsKey('gagnant'),
        isFalse,
        reason: 'la partie continue : annoncer un gagnant la clôturerait',
      );
    });
  });

  group('L historique montre les parties de correspondance', () {
    testWidgets('une partie archivée sous l ancien « corr_ » apparaît', (
      tester,
    ) async {
      // Ce que le serveur a écrit avant sa correction. Ces parties existent
      // déjà dans la base : elles doivent réapparaître sans y toucher.
      reponses['/login'] = {'ok': true, 'token': 't', 'pseudo': 'nino'};
      reponses['/list_games'] = {
        'ok': true,
        'games': [
          {
            'game_uid': 'corr_7',
            'joueur1': 'nino',
            'joueur2': 'Ana',
            'resultat': '0-1',
            'methode': 'fugue',
            'cadence': 'corr',
            'objectif': 'partie',
            'played_at': '1790000000',
          },
        ],
      };
      final service = OnlineService(client: client);
      addTearDown(service.dispose);
      await tester.runAsync(() => service.login('nino', 'mdp'));

      await tester.pumpWidget(
        MaterialApp(
          home: HistoryScreen(online: service, mode: HistoryMode.online),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Ana'),
        findsWidgets,
        reason:
            'la partie était bien archivée, sous un identifiant qu aucun '
            'onglet ne montrait : elle n apparaissait nulle part',
      );
    });

    testWidgets('elle ne déborde pas sur l onglet « En local »', (
      tester,
    ) async {
      reponses['/login'] = {'ok': true, 'token': 't', 'pseudo': 'nino'};
      reponses['/list_games'] = {
        'ok': true,
        'games': [
          {
            'game_uid': 'corr_7',
            'joueur1': 'nino',
            'joueur2': 'Ana',
            'resultat': '0-1',
            'methode': 'fugue',
            'cadence': 'corr',
            'objectif': 'partie',
            'played_at': '1790000000',
          },
        ],
      };
      final service = OnlineService(client: client);
      addTearDown(service.dispose);
      await tester.runAsync(() => service.login('nino', 'mdp'));

      await tester.pumpWidget(
        MaterialApp(
          home: HistoryScreen(online: service, mode: HistoryMode.local),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Ana'),
        findsNothing,
        reason: 'une partie en ligne s est invitée dans l historique local',
      );
    });
  });
}
