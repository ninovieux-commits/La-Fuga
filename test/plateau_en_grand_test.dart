/// Le plateau en grand : les bandeaux cèdent davantage, au pincement.
///
/// Nino, devant sa tablette : « avec éventuellement une touche pour placer le
/// plateau en grand comme sur l'image. Ou un geste (le geste générique pour
/// agrandir) ». Il a choisi le geste seul, et que les bandeaux s'amincissent
/// plutôt que d'être recouverts — ainsi le nom et le chrono restent lisibles.
///
/// Deux choses se vérifient ici, et la seconde est la raison pour laquelle la
/// prise de geste a déménagé : un pincement écarte les doigts HORIZONTALEMENT,
/// et la prise qui fait glisser d'une partie à l'autre gagnerait la main avant
/// celle du pincement. On changerait de partie en voulant agrandir.
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
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/corr_game_screen.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Une tablette : large par rapport à sa hauteur. C'est là que les bandeaux
/// ont quelque chose à céder.
const Size kTablette = Size(800, 1280);

/// Un téléphone : le plateau y prend déjà tout ce qu'il peut.
const Size kTelephone = Size(393, 851);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CorrespondenceService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    service = CorrespondenceService(
      OnlineClient(
        api: ApiClient(
          client: MockClient(
            (request) async => http.Response(
              jsonEncode({'ok': true}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        ),
      ),
    );
  });
  tearDown(resetScale);

  CorrGame partie(String id) => CorrGame.fromJson({
    'id': id,
    'statut': 'en_cours',
    'adversaire': 'Ana',
    'ma_couleur': 'Blanc',
    'turn': 'Blanc',
    'my_turn': true,
    'moves_text': '',
    'objectif': 'partie',
  });

  final deux = [partie('g1'), partie('g2')];

  Future<void> ouvrir(WidgetTester tester, Size ecran) async {
    setScaleSize(ecran);
    tester.view.physicalSize = ecran;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: CorrGameScreen(
          game: deux.first,
          service: service,
          myPseudo: 'nino',
          voisines: deux,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// La hauteur de la boîte du plateau.
  double hauteurDuPlateau(WidgetTester tester) =>
      tester.getSize(find.byType(GameBoardView)).height;

  String montree(WidgetTester tester) =>
      tester.widget<CorrGameScreen>(find.byType(CorrGameScreen)).game.id;

  /// Deux doigts qui s'écartent (ou se rapprochent) au centre de l'écran.
  ///
  /// [facteur] est ce que l'écart devient : deux pour un pincement qui
  /// double, un demi pour l'inverse.
  Future<void> pince(WidgetTester tester, double facteur) async {
    final centre = tester.getCenter(find.byType(GameBoardView));
    const depart = 60.0;
    final arrivee = depart * facteur;
    final g1 = await tester.startGesture(centre - const Offset(depart, 0));
    final g2 = await tester.startGesture(centre + const Offset(depart, 0));
    await tester.pump();
    for (var i = 1; i <= 6; i++) {
      final ecart = depart + (arrivee - depart) * i / 6;
      await g1.moveTo(centre - Offset(ecart, 0));
      await g2.moveTo(centre + Offset(ecart, 0));
      await tester.pump();
    }
    await g1.up();
    await g2.up();
    await tester.pumpAndSettle();
  }

  testWidgets('sur une tablette, écarter les doigts agrandit le plateau', (
    tester,
  ) async {
    await ouvrir(tester, kTablette);
    final avant = hauteurDuPlateau(tester);
    expect(Settings.instance.plateauEnGrand, isFalse);

    await pince(tester, 2);

    expect(Settings.instance.plateauEnGrand, isTrue);
    expect(
      hauteurDuPlateau(tester),
      greaterThan(avant),
      reason: 'les bandeaux ont cédé de la hauteur au plateau',
    );
  });

  testWidgets('et les rapprocher le ramène', (tester) async {
    await ouvrir(tester, kTablette);
    final normal = hauteurDuPlateau(tester);

    await pince(tester, 2);
    expect(Settings.instance.plateauEnGrand, isTrue);

    await pince(tester, 0.5);
    expect(Settings.instance.plateauEnGrand, isFalse);
    expect(hauteurDuPlateau(tester), normal);
  });

  // Le choix se garde : c'est une façon de voir, pas un geste à refaire.
  testWidgets('le choix survit à la fermeture de l écran', (tester) async {
    await ouvrir(tester, kTablette);
    await pince(tester, 2);
    expect(Settings.instance.plateauEnGrand, isTrue);

    await tester.pumpWidget(const SizedBox());
    await ouvrir(tester, kTablette);
    expect(Settings.instance.plateauEnGrand, isTrue);
  });

  // Nino : « donc que rien ne change sur tel ».
  testWidgets('sur un téléphone, le pincement ne change rien', (tester) async {
    await ouvrir(tester, kTelephone);
    final avant = hauteurDuPlateau(tester);

    await pince(tester, 2);

    expect(
      hauteurDuPlateau(tester),
      avant,
      reason: 'les bandeaux avaient déjà donné tout ce qui manquait',
    );
  });

  // LA RAISON DU DÉMÉNAGEMENT DE LA PRISE.
  testWidgets('un pincement ne change pas de partie', (tester) async {
    await ouvrir(tester, kTablette);
    expect(montree(tester), 'g1');

    await pince(tester, 2);

    expect(
      montree(tester),
      'g1',
      reason: 'deux doigts agrandissent ; ils ne tournent pas la page',
    );
  });
}
