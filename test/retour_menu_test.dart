/// Une touche qui promet le menu doit rendre le MENU.
///
/// Nino : « il y a aussi dans l'app des boutons "revenir au menu" qui ne
/// renvoient pas au menu mais juste en arrière. Ils devraient donc dire
/// retour. »
///
/// Deux réponses, selon ce que la touche doit faire :
///
///   - celles qui QUITTENT UNE PARTIE promettent le menu depuis Kivy, où
///     elles l'affichaient vraiment. Elles le rendent de nouveau : on dépile
///     jusqu'à la première route, qui est le menu.
///   - celle du PROFIL rend l'écran d'où l'on vient — la fiche d'un joueur
///     l'ouvre depuis une partie, une conversation, l'historique. Elle ne
///     promet donc plus le menu : elle dit « Retour ».
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/avatar_photos.dart';
import 'package:lafuga/net/decors_connus.dart';
import 'package:lafuga/net/devises_connues.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/retour_menu.dart';
import 'package:lafuga/ui/screens/account_screen.dart';
import 'package:lafuga/ui/screens/corr_game_screen.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OnlineClient client;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    AvatarPhotos.clear();
    DecorsConnus.clear();
    DevisesConnues.clear();

    client = OnlineClient(
      api: ApiClient(
        client: MockClient(
          (req) async => http.Response(
            jsonEncode({
              'ok': true,
              'token': 't',
              'pseudo': 'nino',
              'melo': 1530,
              'description': '',
              'theme': 'original',
              'photo': 'nurse',
              'games': const [],
              'followers': const [],
              'following': const [],
              'blocked': const [],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      ),
    );
    final online = OnlineService(client: client);
    await online.client.login('nino', 'mdp');
    final precedent = OnlineService.instance;
    OnlineService.instance = online;
    addTearDown(() => OnlineService.instance = precedent);
  });

  /// Une pile à trois étages : le menu, un écran quelconque, puis l'écran
  /// qu'on veut quitter. C'est la pile que le défi fabrique quand il s'ouvre
  /// depuis une conversation.
  Future<void> empile(WidgetTester tester, Widget dernier) async {
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cle = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: cle,
        home: const Scaffold(body: Center(child: Text('LE MENU'))),
      ),
    );
    cle.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('AU MILIEU'))),
      ),
    );
    await tester.pumpAndSettle();
    cle.currentState!.push(MaterialPageRoute<void>(builder: (_) => dernier));
    await tester.pumpAndSettle();
  }

  group('Dépiler jusqu au menu', () {
    testWidgets('retourAuMenu saute TOUT ce qu il y a entre', (tester) async {
      await empile(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => retourAuMenu(context),
                child: const Text('quitter'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('LE MENU'), findsNothing);

      await tester.tap(find.text('quitter'));
      await tester.pumpAndSettle();

      expect(find.text('LE MENU'), findsOneWidget);
      expect(
        find.text('AU MILIEU'),
        findsNothing,
        reason:
            'un simple pop se serait arrêté là, sous une touche qui '
            'promettait le menu',
      );
    });
  });

  group('Quitter une partie', () {
    Map<String, dynamic> finie() => const {
      'id': 'g1',
      'statut': 'termine',
      'adversaire': 'Ana',
      'adversaire_melo': 1600,
      'ma_couleur': 'Blanc',
      'turn': 'Blanc',
      'my_turn': false,
      'mon_score': 1,
      'score_adverse': 0,
      'objectif': 'partie',
      'moves_text': '',
      'is_defieur': false,
      'random_code': '',
    };

    testWidgets('« Retour au menu » rend le MENU, pas l écran d avant', (
      tester,
    ) async {
      await empile(
        tester,
        CorrGameScreen(
          game: CorrGame.fromJson(finie()),
          service: CorrespondenceService(client),
          myPseudo: 'nino',
        ),
      );

      // La touche du bandeau de jeu n est pas une `FugaButton` : on la
      // cherche par son libellé.
      final menu = find.text(T('Retour au menu'));
      expect(menu, findsOneWidget, reason: 'la partie est finie : elle y est');
      await tester.tap(menu);
      await tester.pumpAndSettle();

      expect(find.text('LE MENU'), findsOneWidget);
      expect(find.text('AU MILIEU'), findsNothing);
    });
  });

  group('Le profil, lui, revient en arrière', () {
    testWidgets('sa touche dit « Retour », et non le menu', (tester) async {
      await empile(
        tester,
        AccountScreen(online: OnlineService.instance, pseudo: 'mesange'),
      );

      expect(find.widgetWithText(FugaButton, T('Retour')), findsOneWidget);
      expect(
        find.widgetWithText(FugaButton, T('Revenir au menu')),
        findsNothing,
        reason: 'la fiche d un joueur l ouvre depuis n importe où',
      );
    });

    testWidgets('et elle rend bien l écran d où l on vient', (tester) async {
      await empile(
        tester,
        AccountScreen(online: OnlineService.instance, pseudo: 'mesange'),
      );
      await tester.tap(find.widgetWithText(FugaButton, T('Retour')));
      await tester.pumpAndSettle();

      expect(find.text('AU MILIEU'), findsOneWidget);
      expect(
        find.text('LE MENU'),
        findsNothing,
        reason: '« Retour » rend l écran d avant, pas le menu',
      );
    });
  });
}
