/// Le mode immersion : les bandeaux disparaissent, au pincement.
///
/// Nino : « quand on agrandit le plateau par pincement, les bandeaux
/// disparaissent et on passe en mode "immersion". En revanche sans aucune
/// action de la part du joueur le plateau est réduit pour laisser les
/// bandeaux. [...] En mode immersion les chronos doivent être affichés dans
/// le ralliement. »
///
/// C'est ce qui rend la chose automatique, et c'est pour cela qu'amincir les
/// bandeaux ne suffisait pas : ce qui n'est plus affiché n'a plus à rentrer,
/// donc aucune forme d'écran ne peut la prendre en défaut.
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
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/widgets/board_geometry.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:lafuga/ui/widgets/move_strip.dart';
import 'package:lafuga/ui/widgets/player_panel.dart';
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

  testWidgets('écarter les doigts fait disparaître les bandeaux', (
    tester,
  ) async {
    await ouvrir(tester, kTablette);
    final avant = hauteurDuPlateau(tester);
    expect(Settings.instance.immersion, isFalse);

    await pince(tester, 2);

    expect(Settings.instance.immersion, isTrue);
    expect(
      hauteurDuPlateau(tester),
      greaterThan(avant),
      reason: 'les bandeaux ont rendu toute leur hauteur au plateau',
    );
    expect(
      find.byType(PlayerPanel),
      findsNothing,
      reason: 'les bandeaux de joueur ont disparu',
    );
    // Nino : « les bandeaux fins doivent disparaître aussi, c'est un mode
    // immersion. »
    expect(
      find.byType(MoveStrip),
      findsNothing,
      reason: 'la bande des coups aussi',
    );
    expect(
      hauteurDuPlateau(tester),
      kTablette.height,
      reason: 'il ne reste que le plateau, sur toute la hauteur',
    );
  });

  testWidgets('et les rapprocher le ramène', (tester) async {
    await ouvrir(tester, kTablette);
    final normal = hauteurDuPlateau(tester);

    await pince(tester, 2);
    expect(Settings.instance.immersion, isTrue);

    await pince(tester, 0.5);
    expect(Settings.instance.immersion, isFalse);
    expect(hauteurDuPlateau(tester), normal);
  });

  // Le choix se garde : c'est une façon de voir, pas un geste à refaire.
  testWidgets('le choix survit à la fermeture de l écran', (tester) async {
    await ouvrir(tester, kTablette);
    await pince(tester, 2);
    expect(Settings.instance.immersion, isTrue);

    await tester.pumpWidget(const SizedBox());
    await ouvrir(tester, kTablette);
    expect(Settings.instance.immersion, isTrue);
  });

  // Nino : « sur mon téléphone et les autres téléphones de taille normale ça
  // doit rester identique à ce qu'on a déjà. » C'est l'état PAR DÉFAUT qui
  // doit être identique : sans rien demander, les bandeaux sont là.
  testWidgets('un téléphone s ouvre avec ses bandeaux, comme avant', (
    tester,
  ) async {
    await ouvrir(tester, kTelephone);
    expect(find.byType(PlayerPanel), findsNWidgets(2));
    expect(Settings.instance.immersion, isFalse);
  });

  // Et le geste y marche aussi : il n'y a pas de raison de le refuser.
  testWidgets('et le pincement y fait de la place au plateau', (tester) async {
    await ouvrir(tester, kTelephone);
    final avant = hauteurDuPlateau(tester);

    await pince(tester, 2);

    expect(find.byType(PlayerPanel), findsNothing);
    expect(hauteurDuPlateau(tester), greaterThan(avant));
  });

  // Nino : « en mode immersion les chronos doivent être affichés dans le
  // ralliement. » Sans bandeau pour les porter, c'est là qu'ils vont.
  group('Les chronos dans les ralliements', () {
    Future<BoardGeometry> poseLePlateau(
      WidgetTester tester, {
      String? haut,
      String? bas,
      bool flipped = true,
    }) async {
      setScaleSize(kTelephone);
      const boite = Size(350, 500);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: boite.width,
                height: boite.height,
                child: GameBoardView(
                  board: Board.initial(),
                  palette: paletteOf('original'),
                  flipped: flipped,
                  onTapCell: (_) {},
                  chronoHaut: haut,
                  chronoBas: bas,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return BoardGeometry(size: boite, flipped: flipped);
    }

    testWidgets('chacun dans sa bande, en haut et en bas', (tester) async {
      final g = await poseLePlateau(tester, haut: '5:00', bas: '4:59');
      final plateau = tester.getRect(find.byType(GameBoardView));

      for (final (texte, indice) in [('5:00', 0), ('4:59', kExtRows - 1)]) {
        final mot = tester.getRect(find.text(texte));
        final bande = g.rowToY(g.indexToRow(indice));
        expect(
          mot.center.dy - plateau.top,
          closeTo(bande + g.cellSize / 2, g.cellSize / 2),
          reason: '$texte doit être dans la bande de ralliement',
        );
      }
    });

    // Nino : « les chronos en immersion doivent être à droite dans l'espace
    // prévu pour le ralliement. »
    testWidgets('à droite, dans la dernière case', (tester) async {
      final g = await poseLePlateau(tester, haut: '5:00');
      final plateau = tester.getRect(find.byType(GameBoardView));
      final mot = tester.getRect(find.text('5:00'));

      final borDroit = plateau.left + g.originX + g.cellSize * kCols;
      expect(
        mot.right,
        lessThanOrEqualTo(borDroit + 0.5),
        reason: 'il ne sort pas du plateau',
      );
      expect(
        mot.center.dx,
        greaterThan(borDroit - g.cellSize * 1.5),
        reason: 'et il tient dans la dernière case, ou presque',
      );
    });

    // Nino : « le chrono doit être sur un soulignage rectangle blanc
    // transparent pour rester lisible peu importe le thème. »
    testWidgets('sur une plaque blanche translucide', (tester) async {
      await poseLePlateau(tester, haut: '5:00');
      final plaques = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) {
            final d = c.decoration;
            return d is BoxDecoration && d.color == kPlaqueDuChrono;
          });
      expect(plaques, hasLength(1));
      expect(
        kPlaqueDuChrono.a,
        lessThan(1.0),
        reason: 'on doit voir la case au travers',
      );
      expect(kPlaqueDuChrono.r, 1.0, reason: 'et elle est blanche');
    });

    testWidgets('et rien du tout quand on ne les donne pas', (tester) async {
      await poseLePlateau(tester);
      expect(find.text('5:00'), findsNothing);
    });
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
