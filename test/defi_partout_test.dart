/// Défier depuis n'importe quel écran — la correspondance, la conversation.
///
/// Nino : « oui câble le défi depuis la correspondance et la boîte de
/// dialogue ».
///
/// Un seul écran sait mener un défi : le menu, qui reste branché au serveur
/// sous tous les autres. Il pose donc sa façon de défier dans `DefiRelais`, et
/// la fiche d'un joueur s'en sert d'où qu'elle soit ouverte. Les cas ci-dessous
/// vérifient que le défi PART vraiment — jusqu'à la socket — et non qu'une
/// touche a changé de couleur.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/game/defi_relais.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/avatar_photos.dart';
import 'package:lafuga/net/decors_connus.dart';
import 'package:lafuga/net/favoris_connus.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/net/scores_directs.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:lafuga/game/clock.dart';
import 'package:lafuga/ui/screens/corr_game_screen.dart';
import 'package:lafuga/ui/screens/online_game_screen.dart';
import 'package:lafuga/ui/screens/menu_screen.dart';
import 'package:lafuga/ui/screens/replay_screen.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:lafuga/ui/widgets/player_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_game_test.dart' show FakeSocket, makeGame;
import 'support/fake_realtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRealtime socket;
  late OnlineService online;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
    AvatarPhotos.clear();
    DecorsConnus.clear();
    ScoresDirects.clear();
    FavorisConnus.instance.oublie();
    DefiRelais.oublie();
    clearReplayCache();

    socket = FakeRealtime();
    online = OnlineService(
      client: OnlineClient(
        api: ApiClient(
          client: MockClient(
            (req) async => http.Response(
              jsonEncode({
                'ok': true,
                'token': 't',
                'pseudo': 'nino',
                'melo': 1530,
                'messages': const [],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        ),
      ),
      socketFactory: (_) => socket,
    );
    await online.login('nino', 'mdp');
    await online.connectSocket();
    // L'écran de partie passe par le singleton : les tests en posent un.
    final precedent = OnlineService.instance;
    OnlineService.instance = online;
    addTearDown(() => OnlineService.instance = precedent);
  });
  tearDown(() {
    DefiRelais.oublie();
    resetScale();
  });

  /// Des images, mais pas « jusqu'à ce que plus rien ne bouge ».
  ///
  /// `pumpAndSettle` ne rend jamais la main quand le MENU est dessous : il
  /// relit la correspondance à intervalles réguliers, et chaque relecture
  /// demande une image. En avançant d'un temps BORNÉ, les animations de
  /// dialogue (150 ms) ont fini et le reste continue de tourner, comme sur un
  /// vrai téléphone.
  Future<void> calme(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Pose un écran par-dessus ce qui est déjà là, sans attendre son retour.
  Future<void> pousse(WidgetTester tester, Widget ecran, Finder dessous) async {
    // SANS attendre : `push` ne rend la main qu'au retour de l'écran, et le
    // cas de test resterait planté là jusqu'à sa mort.
    unawaited(
      Navigator.of(
        tester.element(dessous),
      ).push(MaterialPageRoute<void>(builder: (_) => ecran)),
    );
    await calme(tester);
  }

  /// Le menu ouvert — c'est lui qui pose le relais — et un écran par-dessus.
  Future<void> parDessusLeMenu(WidgetTester tester, Widget ecran) async {
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: MenuScreen(online: online)));
    await tester.pumpAndSettle();
    // SANS attendre : `push` ne rend la main qu'au retour de l'écran, et le
    // cas de test resterait planté là jusqu'à sa mort.
    unawaited(
      Navigator.of(
        tester.element(find.byType(MenuScreen)),
      ).push(MaterialPageRoute<void>(builder: (_) => ecran)),
    );
    await calme(tester);
  }

  /// La partie de correspondance contre mesange.
  CorrGame partieCorr() => CorrGame.fromJson(const {
    'id': 'g1',
    'statut': 'en_cours',
    'adversaire': 'mesange',
    'adversaire_melo': 1530,
    'ma_couleur': 'Blanc',
    'turn': 'Blanc',
    'my_turn': true,
    'moves_text': '',
    'objectif': 'partie',
  });

  group('Le relais', () {
    test('sans personne pour mener le défi, il n est pas prêt', () {
      expect(DefiRelais.pret, isFalse);
    });

    test('posé, il transmet le pseudo', () async {
      String? defie;
      DefiRelais.pose((p) async => defie = p);
      expect(DefiRelais.pret, isTrue);
      await DefiRelais.defier('mesange');
      expect(defie, 'mesange');
    });

    testWidgets('le MENU le pose en se branchant', (tester) async {
      await tester.pumpWidget(MaterialApp(home: MenuScreen(online: online)));
      await tester.pumpAndSettle();
      expect(
        DefiRelais.pret,
        isTrue,
        reason: 'le menu est à l écoute : il sait mener un défi',
      );
    });
  });

  group('Depuis une partie de correspondance', () {
    testWidgets('la touche « Défier » est pleine, et le défi PART', (
      tester,
    ) async {
      await parDessusLeMenu(
        tester,
        CorrGameScreen(
          game: partieCorr(),
          service: CorrespondenceService(online.client),
          myPseudo: 'nino',
        ),
      );

      await tester.tap(find.text('mesange', findRichText: true));
      await calme(tester);
      final defier = find.widgetWithText(FugaButton, T('Défier'));
      expect(tester.widget<FugaButton>(defier).onPressed, isNotNull);
      expect(
        // DANS la fiche : depuis que TOUTE touche hors service est hachurée,
        // le ½ du bandeau resté derrière l'est aussi, et il n'est pas le
        // sujet.
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byKey(kHachuresKey),
        ),
        findsNothing,
      );

      await tester.tap(defier);
      await calme(tester);

      expect(socket.lastOf('defier')?['pseudo_cible'], 'mesange');
      expect(
        find.textContaining(T('Défi envoyé à %s…').replaceAll('%s', 'mesange')),
        findsOneWidget,
        reason: 'le dialogue d attente du menu paraît PAR-DESSUS la partie',
      );
    });
  });

  group('Depuis la boîte de discussion', () {
    testWidgets('le défi part, et on reste où l on était', (tester) async {
      await parDessusLeMenu(
        tester,
        ConversationScreen(online: online, pseudo: 'mesange'),
      );

      await tester.tap(find.text('mesange', findRichText: true));
      await calme(tester);
      await tester.tap(find.widgetWithText(FugaButton, T('Défier')));
      await calme(tester);

      expect(socket.lastOf('defier')?['pseudo_cible'], 'mesange');
      expect(
        find.byType(ConversationScreen),
        findsOneWidget,
        reason: 'la conversation reste ouverte sous le dialogue d attente',
      );
    });

    testWidgets('mais PAS pendant une partie EN DIRECT', (tester) async {
      // Nino : « de partout tant qu'une partie en direct n'est pas en
      // cours ». C'est l'écran de partie qui pose cet état — la touche se
      // hachure donc aussi dans le chat ouvert depuis cette partie, sans que
      // la conversation ait à le savoir.
      await parDessusLeMenu(
        tester,
        OnlineGameScreen(
          game: makeGame(socket: FakeSocket(), cadence: Cadence.quinze),
          myPseudo: 'nino',
        ),
      );
      expect(DefiRelais.pret, isFalse);

      await pousse(
        tester,
        ConversationScreen(online: online, pseudo: 'mesange'),
        find.byType(OnlineGameScreen),
      );
      await tester.tap(find.text('mesange', findRichText: true));
      await calme(tester);

      expect(
        // DANS la fiche : depuis que TOUTE touche hors service est hachurée,
        // le ½ du bandeau resté derrière l'est aussi, et il n'est pas le
        // sujet.
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byKey(kHachuresKey),
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FugaButton, T('Défier')));
      await calme(tester);
      expect(socket.lastOf('defier'), isNull);
    });
  });

  group('Quand la partie en direct se termine', () {
    testWidgets('la touche redevient pleine', (tester) async {
      await parDessusLeMenu(
        tester,
        OnlineGameScreen(
          game: makeGame(socket: FakeSocket(), cadence: Cadence.quinze),
          myPseudo: 'nino',
        ),
      );
      expect(DefiRelais.pret, isFalse);

      Navigator.of(tester.element(find.byType(OnlineGameScreen))).pop();
      await calme(tester);
      expect(
        DefiRelais.pret,
        isTrue,
        reason: 'la partie fermée, on peut de nouveau défier',
      );
    });
  });

  group('Depuis une partie de l historique', () {
    /// Une partie rejouée, nino contre mesange.
    const nmc =
        '[Date "2026-10-14"]\n'
        '[Joueur1 "nino"]\n'
        '[Joueur2 "mesange"]\n'
        '[Blanc "nino"]\n'
        '[Cadence "15"]\n\n'
        '1.Do2-Do3/Do7-Do6';

    testWidgets('le défi part de là aussi', (tester) async {
      // Nino : « et depuis l'historique ».
      await parDessusLeMenu(tester, ReplayScreen(nmc: nmc, online: online));

      await tester.tap(find.text('mesange', findRichText: true));
      await calme(tester);
      final defier = find.widgetWithText(FugaButton, T('Défier'));
      expect(tester.widget<FugaButton>(defier).onPressed, isNotNull);
      expect(
        // DANS la fiche : depuis que TOUTE touche hors service est hachurée,
        // le ½ du bandeau resté derrière l'est aussi, et il n'est pas le
        // sujet.
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byKey(kHachuresKey),
        ),
        findsNothing,
      );

      await tester.tap(defier);
      await calme(tester);
      expect(socket.lastOf('defier')?['pseudo_cible'], 'mesange');
    });
  });

  group('Sans menu à l écoute', () {
    testWidgets('la touche est hachurée : personne ne mènerait le défi', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(online: online, pseudo: 'mesange'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('mesange', findRichText: true));
      await tester.pumpAndSettle();
      expect(
        // DANS la fiche : depuis que TOUTE touche hors service est hachurée,
        // le ½ du bandeau resté derrière l'est aussi, et il n'est pas le
        // sujet.
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byKey(kHachuresKey),
        ),
        findsOneWidget,
      );
    });
  });
}
