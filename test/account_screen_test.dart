/// Écran de compte : mon profil (modifiable) et celui des autres.
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
import 'package:lafuga/ui/screens/photo_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prefs d'une appli déjà lancée une fois : ni choix de langue, ni tuto —
/// ils n'apparaissent qu'au tout premier démarrage.
const Map<String, Object> _launched = {'lang_chosen': true, 'tuto_seen': true};

/// Serveur simulé : chaque route répond ce qu'on lui a dit de répondre, et
/// l'on peut relire ce qui lui a été envoyé.
final class _Server {
  final List<({String path, Map<String, dynamic> body})> calls = [];
  final Map<String, Map<String, dynamic>> replies = {};

  http.Client get client => MockClient((request) async {
    final path = request.url.path;
    calls.add((
      path: path,
      body: Map<String, dynamic>.from(jsonDecode(request.body) as Map),
    ));
    return http.Response(
      jsonEncode(replies[path] ?? {'ok': true}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  bool called(String path) => calls.any((c) => c.path == path);

  Map<String, dynamic> bodyOf(String path) =>
      calls.lastWhere((c) => c.path == path).body;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Server server;
  late OnlineService online;

  setUp(() async {
    SharedPreferences.setMockInitialValues(_launched);
    await Settings.load();
    await Translations.load('fr');
    server = _Server();
    online = OnlineService(
      client: OnlineClient(api: ApiClient(client: server.client)),
    );
  });

  Map<String, dynamic> profile({
    bool isSelf = true,
    String pseudo = 'Nino',
    Map<String, dynamic> extra = const {},
  }) => {
    'ok': true,
    'pseudo': pseudo,
    'is_self': isSelf,
    'melo': 1620,
    'melo_random': 1480,
    'email': 'nino@exemple.fr',
    'photo': 'dragon|Héritier',
    'description': 'Joue vite.',
    'followers': [
      {'pseudo': 'Ana', 'melo': 1700, 'online': true},
    ],
    'following': const [],
    'blocked': [
      {'pseudo': 'Zed', 'melo': 1300},
    ],
    'h2h_direct_moi': 3,
    'h2h_direct_lui': 1,
    'h2h_corr_moi': 0,
    'h2h_corr_lui': 2,
    ...extra,
  };

  /// Amène une section plus bas dans la page à l'écran.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, {String? pseudo}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AccountScreen(online: online, pseudo: pseudo),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('mon profil montre pseudo, mélos et description', (tester) async {
    server.replies['/get_profile'] = profile();
    await open(tester);

    // Kivy n'a pas de barre de titre sur le profil : le pseudo n'apparaît
    // qu'une fois, dans la fiche d'identité.
    expect(find.text('Nino'), findsOneWidget);
    expect(find.text('Revenir au menu'), findsOneWidget);
    expect(find.text('Se déconnecter'), findsOneWidget);
    expect(find.textContaining('1620'), findsOneWidget);
    expect(find.textContaining('1480'), findsOneWidget, reason: 'mélo Random');
    expect(find.text('Joue vite.'), findsOneWidget);
    expect(find.text('nino@exemple.fr'), findsOneWidget);
  });

  testWidgets('mon profil se modifie, celui des autres non', (tester) async {
    server.replies['/get_profile'] = profile();
    await open(tester);

    expect(find.text('Changer la photo'), findsOneWidget);
    expect(find.text('Modifier la description'), findsOneWidget);
    await scrollTo(tester, find.text('Joueurs bloqués'));
    expect(find.text('Joueurs bloqués'), findsOneWidget);
    expect(find.text('Zed'), findsOneWidget);
  });

  testWidgets('le profil d un autre montre le tête-à-tête, pas les réglages', (
    tester,
  ) async {
    server.replies['/get_profile'] = profile(isSelf: false, pseudo: 'Ana');
    await open(tester, pseudo: 'Ana');

    expect(server.bodyOf('/get_profile')['pseudo'], 'Ana');
    expect(find.textContaining('3 - 1'), findsOneWidget, reason: 'en direct');
    expect(find.textContaining('0 - 2'), findsOneWidget, reason: 'corresp.');
    expect(find.text('Changer la photo'), findsNothing);
    expect(find.text('Adresse mail'), findsNothing);
    expect(find.text('Joueurs bloqués'), findsNothing);
  });

  testWidgets('les notifications viennent d account_info et se basculent', (
    tester,
  ) async {
    server.replies['/get_profile'] = profile();
    server.replies['/account_info'] = {
      'ok': true,
      'notif': {'mail': true, 'turn': false},
    };
    await open(tester);

    // La liste est longue : on descend jusqu'à la case avant de la lire.
    await tester.scrollUntilVisible(
      find.textContaining("quand c'est à moi de jouer"),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final turn = find.ancestor(
      of: find.textContaining("quand c'est à moi de jouer"),
      matching: find.byType(CheckboxListTile),
    );
    expect(tester.widget<CheckboxListTile>(turn).value, isFalse);

    // La case doit être ENTIÈRE à l'écran : la barre du bas la recouvrait en
    // partie, et le toucher tombait à côté.
    await tester.ensureVisible(turn);
    await tester.pumpAndSettle();
    await tester.tap(turn);
    await tester.pumpAndSettle();

    expect(server.called('/set_notif_prefs'), isTrue);
    expect(server.bodyOf('/set_notif_prefs')['turn'], isTrue);
    expect(tester.widget<CheckboxListTile>(turn).value, isTrue);
  });

  testWidgets(
    'interrupteur général éteint, les autres cases ne répondent plus',
    (tester) async {
      server.replies['/get_profile'] = profile();
      server.replies['/account_info'] = {
        'ok': true,
        'notif': {'mail': false},
      };
      await open(tester);

      await tester.scrollUntilVisible(
        find.textContaining('quand je reçois un message'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final msg = find.ancestor(
        of: find.textContaining('quand je reçois un message'),
        matching: find.byType(CheckboxListTile),
      );
      expect(tester.widget<CheckboxListTile>(msg).onChanged, isNull);
      expect(tester.widget<CheckboxListTile>(msg).value, isFalse);
    },
  );

  testWidgets('la description s enregistre', (tester) async {
    server.replies['/get_profile'] = profile();
    await open(tester);

    await tester.tap(find.text('Modifier la description'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Nouvelle description');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(
      server.bodyOf('/set_description')['description'],
      'Nouvelle description',
    );
  });

  testWidgets('un joueur bloqué se débloque', (tester) async {
    server.replies['/get_profile'] = profile();
    await open(tester);

    await scrollTo(tester, find.text('Débloquer'));
    await tester.tap(find.text('Débloquer'));
    await tester.pumpAndSettle();

    expect(server.bodyOf('/unblock_user')['pseudo'], 'Zed');
  });

  testWidgets('on choisit sa photo dans la galerie', (tester) async {
    server.replies['/get_profile'] = profile();
    await open(tester);

    await tester.tap(find.text('Changer la photo'));
    await tester.pumpAndSettle();

    expect(find.byType(PhotoPickerScreen), findsOneWidget);
    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();

    expect(server.bodyOf('/set_photo')['photo'], 'deepgrey');
  });

  testWidgets('un profil introuvable le dit', (tester) async {
    server.replies['/get_profile'] = {'ok': false, 'error': 'inconnu'};
    await open(tester);

    expect(find.text('Profil indisponible.'), findsOneWidget);
  });

  test('la galerie propose Deep Grey, les logos, puis les pièces', () {
    final choices = photoChoices();

    expect(choices.first, 'deepgrey');
    expect(choices[1], startsWith('logo|'));
    expect(choices, contains('dragon|Héritier'));
    expect(choices, contains('dragon|Héritier|Noir'));
    expect(
      choices.toSet().length,
      choices.length,
      reason: 'aucune photo en double',
    );
  });
}
