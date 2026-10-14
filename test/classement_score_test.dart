/// Le classement sous le pseudo, et le score réduit à son nombre.
///
/// Nino : « durant les parties, le classement de la personne doit être en
/// dessous du pseudo. Ainsi il ne sera jamais coupé. Le score lui ne doit plus
/// marquer 4 / ... d'un côté et 15 / ... de l'autre, mais juste 4 et 15. »
///
/// Sa capture d'écran montrait « ⭐ mesange  (1… » : le mélo écrit à la suite
/// du nom, mangé par l'ellipse dès que le bandeau manquait de place.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/game/clock.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/net/scores_directs.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/corr_game_screen.dart';
import 'package:lafuga/ui/screens/online_game_screen.dart';
import 'package:lafuga/ui/widgets/player_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_game_test.dart' show FakeSocket, makeGame;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
    clearReplayCache();
    // Les scores connus vivent toute la session : sans ce ménage, un cas
    // hériterait de ce qu'un autre a appris.
    ScoresDirects.clear();
  });
  tearDown(resetScale);

  /// Un bandeau à la hauteur qu'il a VRAIMENT en partie : douze parts sur les
  /// cent quatre de `GameLayout`, sur un écran de téléphone.
  Future<void> bandeau(
    WidgetTester tester, {
    required String nom,
    String? rating,
    String? subtitle,
    double largeur = 393,
  }) async {
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: largeur,
            height: 851 * 12 / 104,
            child: PlayerPanel(
              name: nom,
              rating: rating,
              subtitle: subtitle,
              clock: '∞',
              palette: paletteOf('original'),
              isWhite: true,
              isTurn: false,
              captures: const [],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Le classement sous le pseudo', () {
    testWidgets('il est SOUS le nom, et aligné avec lui', (tester) async {
      await bandeau(tester, nom: 'mesange', rating: '1530');

      final nom = tester.getRect(find.text('mesange', findRichText: true));
      final melo = tester.getRect(find.text('1530'));
      expect(
        melo.top,
        greaterThanOrEqualTo(nom.bottom - 1),
        reason: 'le classement doit être EN DESSOUS du pseudo',
      );
      expect(
        melo.left,
        closeTo(nom.left, 1),
        reason: 'les deux lignes commencent au même endroit',
      );
    });

    testWidgets('un pseudo à rallonge ne le coupe plus', (tester) async {
      // LE DÉFAUT DE LA CAPTURE. Sur la même ligne, « mesange  (1530) »
      // devenait « mesange  (1… ». Sur sa propre ligne, le nombre est entier
      // quelle que soit la longueur du nom.
      await bandeau(
        tester,
        nom: 'un pseudo vraiment interminable qui déborde largement',
        rating: '1530',
        largeur: 240,
      );

      expect(
        find.text('1530'),
        findsOneWidget,
        reason: 'le classement est un texte À LUI, que rien ne tronque',
      );
    });

    testWidgets('tout tient dans le bandeau, sans déborder', (tester) async {
      // Un débordement vertical ferait échouer ce cas tout seul : Flutter le
      // signale comme une erreur de test. On mesure en plus, pour dire où.
      await bandeau(tester, nom: 'mesange', rating: '1530', subtitle: '+8');

      final boite = tester.getRect(find.byType(PlayerPanel));
      for (final f in [
        find.text('mesange', findRichText: true),
        find.textContaining('1530'),
      ]) {
        final r = tester.getRect(f);
        expect(r.top, greaterThanOrEqualTo(boite.top - 0.5));
        expect(r.bottom, lessThanOrEqualTo(boite.bottom + 0.5));
      }
    });

    testWidgets('la variation de mélo accompagne le classement', (
      tester,
    ) async {
      // « +8 » en fin de partie : il rejoint la ligne du bas, pour que celle
      // du nom reste le nom.
      await bandeau(tester, nom: 'Nino', rating: '1530', subtitle: '+8');
      expect(find.textContaining('+8'), findsOneWidget);
      expect(
        find.text('Nino', findRichText: true),
        findsOneWidget,
        reason: 'la ligne du nom ne porte QUE le nom',
      );
    });

    testWidgets('sans classement, rien ne s ajoute', (tester) async {
      // Une partie locale n'a pas de mélo : le bandeau reste d'une ligne.
      await bandeau(tester, nom: 'Joueur 1');
      final panneau = tester.widget<PlayerPanel>(find.byType(PlayerPanel));
      expect(panneau.rating, isNull);
      expect(find.byType(Text), findsNWidgets(2), reason: 'le nom, le chrono');
    });
  });

  group('Le score en correspondance', () {
    late List<({String path, Map<String, dynamic> body})> appels;
    late OnlineClient client;

    setUp(() {
      appels = [];
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
              jsonEncode({'ok': true}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );
    });

    Future<void> ouvrir(WidgetTester tester) async {
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: CorrGameScreen(
            game: CorrGame.fromJson(const {
              'id': 'g1',
              'statut': 'en_cours',
              'adversaire': 'mesange',
              'adversaire_melo': 1530,
              'ma_couleur': 'Blanc',
              'turn': 'Blanc',
              'my_turn': true,
              'moves_text': '',
              'objectif': 'partie',
              'mon_score': 15,
              'score_adverse': 4,
            }),
            service: CorrespondenceService(client),
            myPseudo: 'nino',
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('JUSTE le nombre, plus de « / ... »', (tester) async {
      await ouvrir(tester);
      final scores = tester
          .widgetList<PlayerPanel>(find.byType(PlayerPanel))
          .map((p) => p.score)
          .toSet();
      expect(scores, {'15', '4'});
      expect(
        find.textContaining('/ ...'),
        findsNothing,
        reason: 'le dénominateur vide ne doit plus paraître nulle part',
      );
    });

    testWidgets('et le classement de l adversaire est sous son nom', (
      tester,
    ) async {
      await ouvrir(tester);
      final adverse = tester
          .widgetList<PlayerPanel>(find.byType(PlayerPanel))
          .firstWhere((p) => p.name == 'mesange');
      expect(adverse.rating, '1530');
      final nom = tester.getRect(find.text('mesange', findRichText: true));
      final melo = tester.getRect(find.text('1530'));
      expect(melo.top, greaterThanOrEqualTo(nom.bottom - 1));
    });
  });

  group('Le classement en direct', () {
    testWidgets('les deux joueurs ont le leur, sous leur nom', (tester) async {
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: OnlineGameScreen(
            game: makeGame(socket: FakeSocket(), cadence: Cadence.quinze),
            myPseudo: 'Nino',
          ),
        ),
      );
      await tester.pump();

      final panneaux = tester
          .widgetList<PlayerPanel>(find.byType(PlayerPanel))
          .toList();
      expect(
        {for (final p in panneaux) p.name},
        {'Nino', 'Adversaire'},
        reason: 'le mélo ne colle plus au nom',
      );
      expect(panneaux.every((p) => p.rating != null), isTrue);
      final nom = tester.getRect(find.text('Adversaire', findRichText: true));
      final melo = tester.getRect(find.text('1500').first);
      expect(melo.top, greaterThanOrEqualTo(nom.bottom - 1));
    });
  });

  group('Le score en direct', () {
    /// Un service connecté dont `/get_profile` répond ces deux nombres.
    ///
    /// La connexion se fait par le CLIENT et non par le service : celle du
    /// service ouvre en plus une socket, dont le minuteur de vingt secondes
    /// survit au cas de test. Il ne tombait pas ici — il est tombé sur la
    /// machine d'intégration, plus lente. Le client, lui, ne fait qu'un POST,
    /// et c'est tout ce dont ces caches ont besoin pour se croire connectés.
    ({OnlineService online, List<String> chemins}) serveur({
      required int moi,
      required int lui,
    }) {
      final chemins = <String>[];
      final client = OnlineClient(
        api: ApiClient(
          client: MockClient((req) async {
            chemins.add(req.url.path);
            return http.Response(
              jsonEncode({
                'ok': true,
                'token': 't',
                'pseudo': 'Nino',
                'h2h_direct_moi': moi,
                'h2h_direct_lui': lui,
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );
      return (online: OnlineService(client: client), chemins: chemins);
    }

    testWidgets('le cache lit les deux nombres du profil', (tester) async {
      final s = serveur(moi: 17, lui: 6);
      await s.online.client.login('Nino', 'mdp');
      expect(await ScoresDirects.resolve('celia', online: s.online), (
        mine: 17,
        theirs: 6,
      ));
      s.chemins.clear();
      await ScoresDirects.resolve('celia', online: s.online);
      expect(
        s.chemins,
        isNot(contains('/get_profile')),
        reason: 'la question ne se repose pas à chaque écran',
      );
    });

    testWidgets('mais la fin d une partie la repose', (tester) async {
      // Le serveur compte une victoire de plus : garder l'ancien nombre à
      // l'écran serait afficher un score faux jusqu'à la sortie de la partie.
      final s = serveur(moi: 17, lui: 6);
      await s.online.client.login('Nino', 'mdp');
      await ScoresDirects.resolve('celia', online: s.online);
      s.chemins.clear();
      await ScoresDirects.resolve('celia', online: s.online, force: true);
      expect(s.chemins, contains('/get_profile'));
    });

    testWidgets('le bandeau écrit MON compte et le SIEN', (tester) async {
      // Le cache garni d'avance : le chemin réseau est éprouvé juste au-dessus.
      ScoresDirects.remember('Adversaire', (mine: 17, theirs: 6));
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: OnlineGameScreen(
            game: makeGame(socket: FakeSocket(), cadence: Cadence.quinze),
            myPseudo: 'Nino',
          ),
        ),
      );
      await tester.pump();

      final panneaux = tester
          .widgetList<PlayerPanel>(find.byType(PlayerPanel))
          .toList();
      expect(
        {for (final p in panneaux) p.name: p.score},
        {'Nino': '17', 'Adversaire': '6'},
      );
      expect(
        find.textContaining('/'),
        findsNothing,
        reason: 'juste le nombre, sans dénominateur',
      );
    });

    testWidgets('sans réponse, aucun score plutôt qu un 0 - 0', (tester) async {
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: OnlineGameScreen(
            game: makeGame(socket: FakeSocket(), cadence: Cadence.quinze),
            myPseudo: 'Nino',
          ),
        ),
      );
      await tester.pump();
      final panneaux = tester.widgetList<PlayerPanel>(find.byType(PlayerPanel));
      expect(panneaux.every((p) => p.score == null), isTrue);
    });
  });
}
