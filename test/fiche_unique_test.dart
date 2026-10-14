/// UN SEUL popup, le même partout, sur le nom comme sur la photo.
///
/// Nino : « le popup de l'image 1 doit remplacer celui de l'image 2 […] ce
/// même popup doit également apparaître si on clique sur le nom ou l'image de
/// profil où qu'ils soient (en partie, boîte de dialogue etc.), à part sur le
/// profil ou le popup en question. Ainsi il n'y a qu'un seul popup, toujours
/// le même. Ça doit aussi marcher depuis les parties dans l'historique. »
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/avatar_photos.dart';
import 'package:lafuga/net/decors_connus.dart';
import 'package:lafuga/net/favoris_connus.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/net/scores_directs.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:lafuga/ui/screens/replay_screen.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:lafuga/ui/widgets/fuga_header.dart';
import 'package:lafuga/ui/widgets/player_panel.dart';
import 'package:lafuga/ui/widgets/profile_photo.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Six coups, nino contre mesange — une partie de l'historique.
const String _nmc =
    '[Date "2026-10-14"]\n'
    '[Joueur1 "nino"]\n'
    '[Joueur2 "mesange"]\n'
    '[Blanc "nino"]\n'
    '[Cadence "15"]\n\n'
    '1.Do2-Do3/Do7-Do6';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Un service connecté, sans socket : `OnlineClient.login` ne fait qu'un
  /// POST, là où celui du service ouvrirait une socket et son minuteur.
  Future<OnlineService> connecte({String pseudo = 'nino'}) async {
    final client = OnlineClient(
      api: ApiClient(
        client: MockClient(
          (req) async => http.Response(
            jsonEncode({
              'ok': true,
              'token': 't',
              'pseudo': pseudo,
              'melo': 1530,
              'messages': const [],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      ),
    );
    await client.login(pseudo, 'mdp');
    return OnlineService(client: client);
  }

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
  });
  tearDown(resetScale);

  void telephone(WidgetTester tester) {
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('Le bandeau de partie', () {
    /// Le panneau, et ce qu'on a touché.
    Future<int Function()> panneau(WidgetTester tester) async {
      var touches = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 120,
              child: PlayerPanel(
                name: 'mesange',
                rating: '1530',
                clock: '∞',
                palette: paletteOf('original'),
                isWhite: true,
                isTurn: false,
                captures: const [],
                photo: 'insectes|Ladybug',
                onNameTap: () => touches++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return () => touches;
    }

    testWidgets('le NOM ouvre la fiche', (tester) async {
      final touches = await panneau(tester);
      await tester.tap(find.text('mesange', findRichText: true));
      await tester.pumpAndSettle();
      expect(touches(), 1);
    });

    testWidgets('et la PHOTO aussi', (tester) async {
      // Nino : « si on clique sur le nom ou l'image de profil ».
      final touches = await panneau(tester);
      await tester.tap(find.byType(ProfilePhoto));
      await tester.pumpAndSettle();
      expect(touches(), 1);
    });
  });

  group('L en-tête d une conversation', () {
    testWidgets('son titre est touchable', (tester) async {
      var touches = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FugaHeader(
              back: '< Retour',
              title: 'mesange',
              titleSize: 18,
              onTitleTap: () => touches++,
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('mesange', findRichText: true));
      await tester.pumpAndSettle();
      expect(touches, 1);
    });
  });

  group('Dans la boîte de discussion', () {
    Future<void> ouvrir(WidgetTester tester) async {
      telephone(tester);
      final online = await connecte();
      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(online: online, pseudo: 'mesange'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('le nom de l en-tête ouvre LA fiche', (tester) async {
      await ouvrir(tester);
      await tester.tap(find.text('mesange', findRichText: true));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.widgetWithText(FugaButton, T('Bloquer')), findsOneWidget);
      expect(find.widgetWithText(FugaButton, T('Défier')), findsOneWidget);
    });

    testWidgets('SA photo du bas aussi', (tester) async {
      await ouvrir(tester);
      await tester.tap(find.byType(ProfilePhoto).first);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.widgetWithText(FugaButton, T('Bloquer')), findsOneWidget);
    });

    testWidgets('et la MIENNE, qui n offre que le profil', (tester) async {
      // On ne se défie pas, on ne se met pas en favori, on ne se bloque pas.
      await ouvrir(tester);
      await tester.tap(find.byType(ProfilePhoto).last);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.widgetWithText(FugaButton, T('Profil')), findsOneWidget);
      expect(find.widgetWithText(FugaButton, T('Bloquer')), findsNothing);
      expect(find.widgetWithText(FugaButton, T('Défier')), findsNothing);
    });
  });

  group('Depuis une partie de l historique', () {
    testWidgets('le nom d un joueur ouvre LA fiche', (tester) async {
      // Nino : « ça doit aussi marcher depuis les parties dans l'historique. »
      telephone(tester);
      final online = await connecte();
      await tester.pumpWidget(
        MaterialApp(
          home: ReplayScreen(nmc: _nmc, online: online),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('mesange', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.widgetWithText(FugaButton, T('Bloquer')), findsOneWidget);
    });

    testWidgets('sans compte, le nom ne mène nulle part', (tester) async {
      // Hors ligne, il n'y a ni favori, ni blocage, ni profil : le geste
      // n'existe pas plutôt que de n'ouvrir rien.
      telephone(tester);
      await tester.pumpWidget(const MaterialApp(home: ReplayScreen(nmc: _nmc)));
      await tester.pumpAndSettle();

      final panneaux = tester.widgetList<PlayerPanel>(find.byType(PlayerPanel));
      expect(panneaux.every((p) => p.onNameTap == null), isTrue);
    });
  });
}
