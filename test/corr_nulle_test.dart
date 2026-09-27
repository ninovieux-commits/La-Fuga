/// La nulle en correspondance : un bandeau, pas une popup.
///
/// Nino : « Il faut pas un popup, on doit pouvoir voir l'entièreté du plateau
/// et pouvoir accéder à l'analyse avant de décider si on accepte ou pas la
/// nulle. »
///
/// Et le ½ ne se touche qu'une fois son coup joué : tant qu'on a le trait, on
/// joue, on ne négocie pas. Éteint plutôt que caché, pour qu'on voie qu'il est
/// là et pourquoi il ne répond pas.
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
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/corr_game_screen.dart';
import 'package:lafuga/ui/widgets/draw_offer_panel.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:lafuga/ui/widgets/game_top_bar.dart';
import 'package:lafuga/ui/widgets/player_panel.dart';
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

  bool appele(String chemin) => appels.any((a) => a.path == chemin);
  Map<String, dynamic>? corps(String chemin) {
    for (final a in appels.reversed) {
      if (a.path == chemin) return a.body;
    }
    return null;
  }

  Map<String, dynamic> jeuJson({
    bool monTour = true,
    bool nulleARepondre = false,
    bool nulleParMoi = false,
    String coups = '',
  }) => {
    'id': 'g1',
    'statut': 'en_cours',
    'adversaire': 'mesange',
    'adversaire_melo': 1520,
    'ma_couleur': 'Blanc',
    'turn': monTour ? 'Blanc' : 'Noir',
    'my_turn': monTour,
    'moves_text': coups,
    'objectif': 'partie',
    'nulle_a_repondre': nulleARepondre,
    'nulle_proposeur': nulleARepondre ? 'mesange' : '',
    'nulle_proposee_par_moi': nulleParMoi,
  };

  Future<void> ouvrir(WidgetTester tester, Map<String, dynamic> j) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CorrGameScreen(
          game: CorrGame.fromJson(j),
          service: CorrespondenceService(client),
          myPseudo: 'nino',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Le bouton ½', () {
    testWidgets('il est LÀ, mais éteint, quand c est à moi de jouer', (
      tester,
    ) async {
      await ouvrir(tester, jeuJson(monTour: true));

      expect(
        find.text('½'),
        findsOneWidget,
        reason: 'le ½ doit rester visible : caché, il n apprend rien',
      );

      await tester.tap(find.text('½'));
      await tester.pumpAndSettle();
      expect(
        appele('/corr_proposer_nulle'),
        isFalse,
        reason: 'on a pu proposer la nulle alors qu on avait le trait',
      );
    });

    testWidgets('il s allume une fois mon coup joué', (tester) async {
      await ouvrir(tester, jeuJson(monTour: false, coups: 'Do1-Do2'));

      await tester.tap(find.text('½'));
      await tester.pumpAndSettle();
      expect(appele('/corr_proposer_nulle'), isTrue);
      expect(corps('/corr_proposer_nulle')!['game_id'], 'g1');
    });

    testWidgets('proposée, on ne la repropose pas', (tester) async {
      await ouvrir(
        tester,
        jeuJson(monTour: false, nulleParMoi: true, coups: 'Do1-Do2'),
      );
      final panneaux = tester
          .widgetList<PlayerPanel>(find.byType(PlayerPanel))
          .where((p) => p.drawOffered);
      expect(
        panneaux.length,
        1,
        reason: 'le ½ doit s allumer chez celui qui a proposé',
      );
    });

    testWidgets('on ne propose rien sur une partie finie', (tester) async {
      final j = jeuJson(monTour: false)
        ..['statut'] = 'termine'
        ..['resultat'] = 'nulle';
      await ouvrir(tester, j);
      expect(find.text('½'), findsNothing);
    });
  });

  group('Le ½ éteint, quand on appuie quand même', () {
    testWidgets('il dit ce qui manque : jouer son coup', (tester) async {
      // L'infobulle demande de rester appuyé, et personne ne le fait. La
      // question se pose au moment de l'appui : c'est là qu'on répond.
      await ouvrir(tester, jeuJson(monTour: true));
      await tester.tap(find.text('½'));
      await tester.pumpAndSettle();

      expect(
        find.text('Jouez votre coup pour pouvoir proposer la nulle'),
        findsOneWidget,
      );
      expect(appele('/corr_proposer_nulle'), isFalse);
    });

    testWidgets('et quand c est une nulle qui attend, il le dit aussi', (
      tester,
    ) async {
      await ouvrir(
        tester,
        jeuJson(monTour: false, nulleARepondre: true, coups: 'Do1-Do2'),
      );
      await tester.tap(find.text('½'));
      await tester.pumpAndSettle();

      expect(
        find.text('Répondez d abord à la nulle proposée'),
        findsOneWidget,
        reason: 'le motif du blocage n est pas celui qu on croit',
      );
    });

    testWidgets('allumé, il ne dit rien : il propose', (tester) async {
      await ouvrir(tester, jeuJson(monTour: false, coups: 'Do1-Do2'));
      await tester.tap(find.text('½'));
      await tester.pumpAndSettle();

      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'une explication s est affichée alors que le geste a marché',
      );
      expect(appele('/corr_proposer_nulle'), isTrue);
    });
  });

  group('L offre reçue', () {
    testWidgets('elle prend la place du panneau de l adversaire', (
      tester,
    ) async {
      await ouvrir(tester, jeuJson(monTour: true, nulleARepondre: true));

      expect(find.byType(DrawOfferPanel), findsOneWidget);
      expect(
        find.byType(PlayerPanel),
        findsOneWidget,
        reason: 'le mien doit rester : c est celui d en face qui cède la place',
      );
      expect(find.textContaining('mesange'), findsWidgets);
    });

    testWidgets('AUCUNE popup : le plateau reste entier', (tester) async {
      await ouvrir(tester, jeuJson(monTour: true, nulleARepondre: true));

      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'une popup masque la position qu on doit pouvoir regarder',
      );
      expect(find.byType(GameBoardView), findsOneWidget);
    });

    testWidgets('l analyse reste atteignable pendant qu on décide', (
      tester,
    ) async {
      await ouvrir(tester, jeuJson(monTour: true, nulleARepondre: true));
      final barre = tester.widget<GameTopBar>(find.byType(GameTopBar));
      expect(
        barre.onAnalyse,
        isNotNull,
        reason: 'on doit pouvoir analyser avant d accepter une nulle',
      );
    });

    testWidgets('accepter clôt la partie', (tester) async {
      await ouvrir(tester, jeuJson(monTour: true, nulleARepondre: true));
      await tester.tap(find.text('Accepter'));
      await tester.pumpAndSettle();

      expect(corps('/corr_repondre_nulle')!['accepte'], isTrue);
    });

    testWidgets('refuser laisse la partie continuer', (tester) async {
      reponses['/corr_list'] = {
        'ok': true,
        'games': [jeuJson(monTour: true)],
      };
      await ouvrir(tester, jeuJson(monTour: true, nulleARepondre: true));
      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();

      expect(corps('/corr_repondre_nulle')!['accepte'], isFalse);
      expect(
        find.byType(DrawOfferPanel),
        findsNothing,
        reason: 'l offre refusée doit disparaître du bandeau',
      );
      expect(find.byType(PlayerPanel), findsNWidgets(2));
    });

    testWidgets('le ½ est éteint tant qu on doit répondre', (tester) async {
      await ouvrir(
        tester,
        jeuJson(monTour: false, nulleARepondre: true, coups: 'Do1-Do2'),
      );
      await tester.tap(find.text('½'));
      await tester.pumpAndSettle();
      expect(
        appele('/corr_proposer_nulle'),
        isFalse,
        reason: 'répondre d abord, proposer ensuite',
      );
    });
  });

  group('Une offre qui arrive pendant qu on regarde', () {
    testWidgets('le sondage la voit, sans qu on quitte la partie', (
      tester,
    ) async {
      // Le piège : une nulle ne change NI les coups NI le statut. La garde du
      // sondage la laissait passer, et l offre n apparaissait qu en rouvrant
      // la partie.
      await ouvrir(tester, jeuJson(monTour: true, coups: 'Do1-Do2'));
      expect(find.byType(DrawOfferPanel), findsNothing);

      reponses['/corr_list'] = {
        'ok': true,
        'games': [
          jeuJson(monTour: true, nulleARepondre: true, coups: 'Do1-Do2'),
        ],
      };
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(
        find.byType(DrawOfferPanel),
        findsOneWidget,
        reason: 'l offre est restée invisible jusqu à la réouverture',
      );
    });
  });
}
