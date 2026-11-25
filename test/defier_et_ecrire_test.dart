/// Défier n'importe qui, en direct OU par correspondance — et lui écrire.
///
/// Nino : « tous les boutons défier doivent lancer un popup avec [direct] et
/// [correspondance] ce qui fait qu'on est plus obligés de passer par les
/// plateaux vides pour lancer une corresp, et qu'on peut en jouer contre des
/// gens qui ne sont pas dans les favoris en les recherchant simplement. Sur
/// le profil, ajoute d'une ligne : "actions : [défier] [message]". Sur le
/// popup fiche joueur, ajout d'une touche "[message]". […] Dans les boîtes de
/// messages, ajout d'une touche "[nouveau]" qui ouvre un popup avec tous les
/// favoris. »
///
/// Avant cela, une partie par correspondance ne partait que d'une case VIDE
/// de la grille du menu, qui ne proposait que les favoris : on ne pouvait pas
/// jouer par correspondance contre quelqu'un qu'on venait de chercher, ni lui
/// écrire sans l'avoir d'abord mis en favori.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/game/defi_relais.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/favoris_connus.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/account_screen.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:lafuga/ui/screens/menu_screen.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/widgets/player_card.dart';
import 'package:lafuga/ui/widgets/volet_menu.dart';
import 'package:lafuga/ui/widgets/choix_du_defi.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_realtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<({String path, Map<String, dynamic> body})> appels;
  late Map<String, Map<String, dynamic>> reponses;
  late OnlineService online;
  late FakeRealtime socket;

  const ecranTeste = Size(393, 851);

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
    FavorisConnus.instance.oublie();
    DefiRelais.oublie();

    appels = [];
    reponses = {
      '/login': {'ok': true, 'token': 't', 'pseudo': 'nino', 'melo': 1600},
    };
    socket = FakeRealtime();
    online = OnlineService(
      client: OnlineClient(
        api: ApiClient(
          client: MockClient((req) async {
            appels.add((
              path: req.url.path,
              body: Map<String, dynamic>.from(jsonDecode(req.body) as Map),
            ));
            return http.Response(
              jsonEncode(reponses[req.url.path] ?? {'ok': true}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      ),
      socketFactory: (_) => socket,
    );
  });
  tearDown(() {
    resetScale();
    DefiRelais.oublie();
  });

  Map<String, dynamic>? corpsDe(String path) {
    for (final a in appels.reversed) {
      if (a.path == path) return a.body;
    }
    return null;
  }

  Map<String, dynamic> profil({String pseudo = 'mesange', bool moi = false}) =>
      {
        'ok': true,
        'pseudo': pseudo,
        'is_self': moi,
        'melo': 1530,
        'melo_random': 1500,
        'description': '',
        'followers': const [],
        'following': const [],
        'blocked': const [],
        'h2h_direct_moi': 8,
        'h2h_direct_lui': 8,
      };

  Future<void> ecran(
    WidgetTester tester,
    Widget quoi, {
    Size taille = ecranTeste,
  }) async {
    await online.client.login('nino', 'mdp');
    setScaleSize(taille);
    tester.view.physicalSize = taille;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: quoi));
    await tester.pumpAndSettle();
  }

  group('Le popup du défi', () {
    /// Un écran de rien, avec une seule touche « Défier ».
    Future<void> uneTouche(WidgetTester tester) => ecran(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FugaButton(
              text: T('Défier'),
              onPressed: () => lancerUnDefi(context, 'mesange'),
            ),
          ),
        ),
      ),
    );

    testWidgets('il propose les DEUX, et nomme la personne', (tester) async {
      DefiRelais.pose((_) async {}, correspondance: (_) async {});
      await uneTouche(tester);
      await tester.tap(find.widgetWithText(FugaButton, T('Défier')));
      await tester.pumpAndSettle();

      expect(find.textContaining('mesange'), findsOneWidget);
      expect(find.widgetWithText(FugaButton, T('En direct')), findsOneWidget);
      expect(
        find.widgetWithText(FugaButton, T('Correspondance')),
        findsOneWidget,
      );
    });

    testWidgets('« Correspondance » passe par le relais de correspondance', (
      tester,
    ) async {
      String? direct;
      String? corresp;
      DefiRelais.pose(
        (p) async => direct = p,
        correspondance: (p) async => corresp = p,
      );
      await uneTouche(tester);
      await tester.tap(find.widgetWithText(FugaButton, T('Défier')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FugaButton, T('Correspondance')));
      await tester.pumpAndSettle();

      expect(corresp, 'mesange');
      expect(direct, isNull, reason: 'on n a pas demandé une partie en direct');
    });

    testWidgets('« En direct » passe par l autre', (tester) async {
      String? direct;
      String? corresp;
      DefiRelais.pose(
        (p) async => direct = p,
        correspondance: (p) async => corresp = p,
      );
      await uneTouche(tester);
      await tester.tap(find.widgetWithText(FugaButton, T('Défier')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FugaButton, T('En direct')));
      await tester.pumpAndSettle();

      expect(direct, 'mesange');
      expect(corresp, isNull);
    });

    testWidgets('refermer n envoie rien', (tester) async {
      String? direct;
      String? corresp;
      DefiRelais.pose(
        (p) async => direct = p,
        correspondance: (p) async => corresp = p,
      );
      await uneTouche(tester);
      await tester.tap(find.widgetWithText(FugaButton, T('Défier')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FugaButton, T('Fermer')));
      await tester.pumpAndSettle();

      expect(direct, isNull);
      expect(corresp, isNull);
    });

    // Nino, en voyant sa fiche pendant une partie : « lors d'une partie en
    // direct, ce popup doit avoir la touche défier désactivée. » La touche
    // désigne maintenant le CHOIX entre les deux défis : c'est donc le choix
    // entier qui s'éteint, et non seulement sa moitié directe.
    test('une partie en direct éteint les deux', () {
      DefiRelais.pose((_) async {}, correspondance: (_) async {});
      expect(DefiRelais.disponible, isTrue);

      DefiRelais.enPartieDirecte = true;
      expect(DefiRelais.pret, isFalse);
      expect(DefiRelais.pretCorresp, isFalse);
      expect(DefiRelais.disponible, isFalse);
    });

    test('sans personne pour la mener, rien non plus', () {
      expect(DefiRelais.disponible, isFalse);
    });
  });

  // LE CŒUR DE LA DEMANDE : une correspondance contre quelqu'un qui n'est pas
  // dans mes favoris, trouvé par la recherche.
  group('Depuis la recherche du menu', () {
    testWidgets('une partie par CORRESPONDANCE part, sans passer par une case '
        'vide', (tester) async {
      reponses['/search_user'] = profil(pseudo: 'Ana');
      reponses['/corr_list'] = {'ok': true, 'games': const []};
      await ecran(tester, MenuScreen(online: online));

      await tester.enterText(find.byKey(kBarreRechercheKey), 'Ana');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FugaButton, T('Défier')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FugaButton, T('Correspondance')));
      await tester.pumpAndSettle();

      // La suite est celle d'une case vide : d'où part la partie, puis la
      // couleur. On cherche DANS le popup : le menu porte déjà une étiquette
      // « Standard » derrière, et la confondre ne prouverait rien.
      Finder dans(String texte) => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FugaButton, texte),
      );
      expect(corpsDe('/corr_defier'), isNull);
      await tester.tap(dans(T('Standard')));
      await tester.pumpAndSettle();
      await tester.tap(dans(T('Aléatoire')));
      await tester.pumpAndSettle();

      final defi = corpsDe('/corr_defier');
      expect(defi, isNotNull);
      expect(defi!['pseudo'], 'Ana');
      expect(defi['mode'], 'standard');
      expect(
        socket.lastOf('defier'),
        isNull,
        reason: 'aucun défi EN DIRECT n a été lancé',
      );
    });
  });

  // Nino, devant le volet « Mes favoris » du menu : « et celui-là, il
  // défile ? » Il défile depuis toujours — sa hauteur est un plafond et sa
  // touche « Fermer » se tient SOUS ce qui défile —, mais rien ne le
  // vérifiait.
  group('Le volet des favoris, sur le menu', () {
    testWidgets('vingt favoris : il défile, et « Fermer » reste', (
      tester,
    ) async {
      reponses['/corr_list'] = {'ok': true, 'games': const []};
      reponses['/list_favorites'] = {
        'ok': true,
        'favorites': [
          for (var i = 0; i < 20; i++)
            {'pseudo': 'joueur$i', 'melo': 1500, 'online': false},
        ],
      };
      await ecran(tester, MenuScreen(online: online));
      await tester.tap(find.widgetWithText(FugaButton, '★'));
      await tester.pumpAndSettle();

      final volet = tester.getRect(find.byType(PanneauDuVolet));
      expect(volet.height, lessThanOrEqualTo(ecranTeste.height * 0.68 + 1));
      expect(volet.bottom, lessThanOrEqualTo(ecranTeste.height));

      final fermer = find.descendant(
        of: find.byType(PanneauDuVolet),
        matching: find.widgetWithText(FugaButton, T('Fermer')),
      );
      final place = tester.getRect(fermer);
      expect(place.bottom, lessThanOrEqualTo(volet.bottom));

      final dernier = find.text('joueur19');
      expect(dernier, findsNothing, reason: 'il attend hors de la liste');
      await tester.scrollUntilVisible(
        dernier,
        80,
        scrollable: find.descendant(
          of: find.byType(PanneauDuVolet),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();

      expect(dernier, findsOneWidget);
      expect(
        tester.getRect(fermer),
        place,
        reason: 'la liste a défilé sous elle, elle est restée',
      );
    });
  });

  group('Sur le profil de quelqu un', () {
    testWidgets('une ligne « Actions : » avec ses deux touches', (
      tester,
    ) async {
      DefiRelais.pose((_) async {}, correspondance: (_) async {});
      reponses['/get_profile'] = profil();
      await ecran(tester, AccountScreen(online: online, pseudo: 'mesange'));

      expect(find.text(T('Actions :')), findsOneWidget);
      expect(find.widgetWithText(FugaButton, T('Défier')), findsOneWidget);
      expect(find.widgetWithText(FugaButton, T('Message')), findsOneWidget);
    });

    testWidgets('« Message » ouvre sa boîte', (tester) async {
      reponses['/get_profile'] = profil();
      await ecran(tester, AccountScreen(online: online, pseudo: 'mesange'));

      await tester.tap(find.widgetWithText(FugaButton, T('Message')));
      await tester.pumpAndSettle();

      expect(find.byType(ConversationScreen), findsOneWidget);
    });

    testWidgets('« Défier » ouvre le choix des deux', (tester) async {
      DefiRelais.pose((_) async {}, correspondance: (_) async {});
      reponses['/get_profile'] = profil();
      await ecran(tester, AccountScreen(online: online, pseudo: 'mesange'));

      await tester.tap(find.widgetWithText(FugaButton, T('Défier')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FugaButton, T('En direct')), findsOneWidget);
    });

    testWidgets('rien de tout cela sur MON profil', (tester) async {
      reponses['/get_profile'] = profil(pseudo: 'nino', moi: true);
      await ecran(tester, AccountScreen(online: online));

      expect(find.text(T('Actions :')), findsNothing);
      expect(find.widgetWithText(FugaButton, T('Message')), findsNothing);
    });
  });

  // Nino, devant la fiche et ses six touches : « et celui-là, il défile ? »
  group('La fiche du joueur sur un petit écran', () {
    /// Un écran COURT : six touches, deux scores et trois lignes de texte n'y
    /// tiennent plus d'un seul tenant.
    const petit = Size(393, 480);

    Future<void> ouvreLaFiche(WidgetTester tester) async {
      reponses['/get_profile'] = profil();
      await ecran(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showPlayerCard(
                  context,
                  online: online,
                  palette: paletteOf('original'),
                  pseudo: 'mesange',
                ),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
        taille: petit,
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('elle défile, et rien ne déborde', (tester) async {
      await ouvreLaFiche(tester);

      final fiche = tester.getRect(find.byType(AlertDialog));
      expect(fiche.top, greaterThanOrEqualTo(0));
      expect(fiche.bottom, lessThanOrEqualTo(petit.height));
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Scrollable),
        ),
        findsWidgets,
        reason: 'ce qui ne tient pas se va chercher',
      );
    });

    testWidgets('et la dernière touche s atteint quand même', (tester) async {
      await ouvreLaFiche(tester);
      final fermer = find.widgetWithText(FugaButton, T('Fermer'));
      expect(
        tester.getRect(fermer).bottom,
        greaterThan(tester.getRect(find.byType(AlertDialog)).bottom),
        reason: 'elle commence hors de vue : sans défilement, elle est perdue',
      );

      await tester.scrollUntilVisible(fermer, 60);
      await tester.pumpAndSettle();
      await tester.tap(fermer);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('La liste des messages', () {
    testWidgets('« Nouveau » montre tous mes favoris', (tester) async {
      reponses['/list_conversations'] = {'ok': true, 'conversations': const []};
      reponses['/list_favorites'] = {
        'ok': true,
        'favorites': const [
          {'pseudo': 'celia', 'melo': 1395, 'online': true},
          {'pseudo': 'Vem', 'melo': 1500, 'online': false},
        ],
      };
      await ecran(tester, ConversationsScreen(online: online));

      await tester.tap(find.widgetWithText(FugaButton, T('Nouveau')));
      await tester.pumpAndSettle();

      expect(find.text(T('Nouveau message')), findsOneWidget);
      expect(find.widgetWithText(FugaButton, 'celia'), findsOneWidget);
      expect(find.widgetWithText(FugaButton, 'Vem'), findsOneWidget);
    });

    testWidgets('et toucher un pseudo ouvre sa boîte', (tester) async {
      reponses['/list_conversations'] = {'ok': true, 'conversations': const []};
      reponses['/list_favorites'] = {
        'ok': true,
        'favorites': const [
          {'pseudo': 'celia', 'melo': 1395, 'online': true},
        ],
      };
      await ecran(tester, ConversationsScreen(online: online));

      await tester.tap(find.widgetWithText(FugaButton, T('Nouveau')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FugaButton, 'celia'));
      await tester.pumpAndSettle();

      expect(find.byType(ConversationScreen), findsOneWidget);
    });

    // Nino : « si il y a beaucoup de favoris, ça défile ? »
    testWidgets('avec vingt favoris, le popup DÉFILE au lieu de déborder', (
      tester,
    ) async {
      reponses['/list_conversations'] = {'ok': true, 'conversations': const []};
      reponses['/list_favorites'] = {
        'ok': true,
        'favorites': [
          for (var i = 0; i < 20; i++)
            {'pseudo': 'joueur$i', 'melo': 1500, 'online': false},
        ],
      };
      await ecran(tester, ConversationsScreen(online: online));
      await tester.tap(find.widgetWithText(FugaButton, T('Nouveau')));
      await tester.pumpAndSettle();

      // Il ne dépasse pas de l'écran : sa hauteur est plafonnée.
      // Le popup ne déborde pas de l'écran.
      final liste = tester.getRect(find.byType(ListView));
      expect(liste.top, greaterThanOrEqualTo(0));
      expect(liste.bottom, lessThanOrEqualTo(ecranTeste.height));
      expect(liste.height, lessThanOrEqualTo(ecranTeste.height * 0.45 + 1));

      // Le premier est là, le dernier n'est même pas encore dessiné : il
      // attend hors de la liste, et seul un défilement l'amène.
      expect(find.widgetWithText(FugaButton, 'joueur0'), findsOneWidget);
      final dernier = find.widgetWithText(FugaButton, 'joueur19');
      expect(dernier, findsNothing);

      // ET « FERMER » NE BOUGE PAS : elle se tient sous ce qui défile.
      final fermer = find.widgetWithText(FugaButton, T('Fermer'));
      final place = tester.getRect(fermer);
      expect(place.bottom, lessThanOrEqualTo(ecranTeste.height));
      expect(place.top, greaterThanOrEqualTo(liste.bottom - 1));

      await tester.scrollUntilVisible(
        dernier,
        80,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(fermer),
        place,
        reason: 'la liste a défilé sous elle, elle est restée',
      );
      await tester.tap(dernier);
      await tester.pumpAndSettle();

      expect(find.byType(ConversationScreen), findsOneWidget);
    });

    testWidgets('sans favori, elle le dit au lieu de ne rien montrer', (
      tester,
    ) async {
      reponses['/list_conversations'] = {'ok': true, 'conversations': const []};
      reponses['/list_favorites'] = {'ok': true, 'favorites': const []};
      await ecran(tester, ConversationsScreen(online: online));

      await tester.tap(find.widgetWithText(FugaButton, T('Nouveau')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(T('Aucun favori.').split('\n').first),
        findsOneWidget,
      );
    });
  });
}
