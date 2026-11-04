/// Le classement : un volet qui défile, et qui laisse le bandeau vivant.
///
/// Nino : « lorsqu'il apparaît les boutons "standard/random" et "nino"
/// doivent rester accessibles. Le bouton "standard/random" ne doit pas
/// fermer le popup classement mais il continue à passer l'App d'un mode à
/// l'autre. Quand elle fait passer l'App en mode random, le popup se met à
/// afficher les meilleurs mélos de random, et vice et versa. »
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/account_screen.dart';
import 'package:lafuga/ui/screens/menu_screen.dart';
import 'package:lafuga/ui/widgets/classement_volet.dart';
import 'package:lafuga/ui/widgets/volet_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_realtime.dart';

const Map<String, Object> _launched = {'lang_chosen': true, 'tuto_seen': true};

/// Un classement du serveur : des pseudos qui disent de quel mode ils sont.
Map<String, dynamic> _classement({required bool random}) => {
  'ok': true,
  'random': random,
  'joueurs': [
    for (var i = 0; i < 3; i++)
      {
        'rang': i + 1,
        'pseudo': random ? 'rnd$i' : 'std$i',
        'melo': 1900 - i * 50,
        'photo': '',
      },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRealtime socket;
  late OnlineService online;
  late List<Map<String, dynamic>> demandes;

  setUp(() async {
    SharedPreferences.setMockInitialValues(_launched);
    await Settings.load();
    await Translations.load('fr');

    socket = FakeRealtime();
    demandes = [];
    final client = MockClient((request) async {
      final corps = jsonDecode(request.body) as Map<String, dynamic>;
      Map<String, dynamic> reponse = {'ok': true};
      if (request.url.path == '/login') {
        reponse = {'ok': true, 'token': 't', 'pseudo': 'Nino', 'melo': 1600};
      } else if (request.url.path == '/classement') {
        demandes.add(corps);
        reponse = _classement(random: corps['random'] == true);
      }
      return http.Response(
        jsonEncode(reponse),
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

  Future<void> ouvreLeClassement(WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: MenuScreen(online: online)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Classement'));
    await tester.tap(find.text('Classement'));
    await tester.pumpAndSettle();
  }

  testWidgets('il liste les joueurs du serveur, rang et mélo', (tester) async {
    await ouvreLeClassement(tester);

    expect(find.byType(ClassementVolet), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      expect(find.text('std$i'), findsOneWidget, reason: 'le pseudo');
      expect(find.text('${i + 1}'), findsOneWidget, reason: 'le rang');
      expect(find.text('${1900 - i * 50}'), findsOneWidget, reason: 'le mélo');
    }
    expect(demandes.single['random'], false);
  });

  testWidgets('le bandeau reste vivant : « standard » bascule le mode SANS '
      'refermer, et le classement change', (tester) async {
    await ouvreLeClassement(tester);
    expect(find.text('std0'), findsOneWidget);

    // La touche du bandeau est SOUS le voile du volet, et pourtant elle
    // répond : elle se dessine après lui.
    await tester.tap(find.text('Standard'));
    await tester.pumpAndSettle();

    expect(
      find.byType(ClassementVolet),
      findsOneWidget,
      reason: 'la touche du mode ne referme pas le classement',
    );
    expect(find.text('Random'), findsOneWidget, reason: 'le mode a basculé');
    expect(find.text('rnd0'), findsOneWidget, reason: 'le classement Random');
    expect(find.text('std0'), findsNothing);
    expect(demandes.last['random'], true);

    // Et le retour : la liste déjà reçue ne se redemande pas.
    await tester.tap(find.text('Random'));
    await tester.pumpAndSettle();
    expect(find.text('std0'), findsOneWidget);
    expect(demandes, hasLength(2), reason: 'les deux listes sont gardées');
  });

  testWidgets('toucher un joueur ouvre son profil', (tester) async {
    await ouvreLeClassement(tester);
    await tester.tap(find.text('std1'));
    await tester.pumpAndSettle();

    expect(find.byType(ClassementVolet), findsNothing);
    expect(find.byType(AccountScreen), findsOneWidget);
  });

  testWidgets('les favoris aussi laissent le bandeau accessible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: MenuScreen(online: online)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('\u2605'));
    await tester.tap(find.text('\u2605'));
    await tester.pumpAndSettle();
    expect(find.byType(PanneauDuVolet), findsOneWidget);

    // Nino : « ce serait bien que le popup favoris en question ainsi que les
    // autres popups qui s'affichent directement sur le menu laissent
    // également accessibles les boutons "nino" et "standard/random". »
    await tester.tap(find.text('Standard'));
    await tester.pumpAndSettle();
    expect(find.text('Random'), findsOneWidget);
    expect(
      find.byType(PanneauDuVolet),
      findsOneWidget,
      reason: 'le volet des favoris reste ouvert',
    );
  });

  testWidgets('le voile referme le volet, le bandeau non', (tester) async {
    await ouvreLeClassement(tester);
    // Un doigt au milieu de l'écran, hors du panneau : sur le voile.
    await tester.tapAt(const Offset(196, 835));
    await tester.pumpAndSettle();
    expect(find.byType(PanneauDuVolet), findsNothing);
  });
}
