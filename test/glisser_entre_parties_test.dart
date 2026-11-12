/// Glisser d'une partie de correspondance à la suivante.
///
/// Nino : « lorsque je suis sur une partie par correspondance, que je puisse
/// faire glisser l'écran vers la droite ou vers la gauche pour aller sur les
/// parties qui sont avant ou après dans la liste de mes parties par
/// correspondance sur le menu. Normalement, cela ne devrait pas poser de
/// problème car il n'y a aucun mouvement de glisser accepté dans le jeu. On
/// est obligé de saisir la pièce puis de cliquer sur l'endroit où on veut
/// qu'elle aille. »
///
/// C'est vrai, et c'est ce qui rend le geste libre. Il reste une chose à
/// tenir : le plateau prend la pièce AU CONTACT, avant qu'on sache que le
/// doigt va glisser. Un glissement ne doit donc rien laisser derrière lui.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/corr_game_screen.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:lafuga/ui/widgets/move_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cinq coups d'une vraie partie : de quoi faire déborder le bandeau sur un
/// écran étroit.
const _coups = 'Fa3-Sol4\nFa6-Sol5\nSol2-Fa3\n(Si7Si8)-Si6\nFa2-Fa4';

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

  CorrGame partie(String id, String adversaire, {String coups = ''}) =>
      CorrGame.fromJson({
        'id': id,
        'statut': 'en_cours',
        'adversaire': adversaire,
        'ma_couleur': 'Blanc',
        'turn': 'Blanc',
        'my_turn': true,
        'moves_text': coups,
        'objectif': 'partie',
      });

  final trois = [partie('g1', 'Ana'), partie('g2', 'Bob'), partie('g3', 'Cis')];

  /// L'écran ouvert sur [i], avec les trois parties pour voisines.
  Future<void> ouvrir(
    WidgetTester tester,
    int i, {
    List<CorrGame>? voisines,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CorrGameScreen(
          game: trois[i],
          service: service,
          myPseudo: 'nino',
          voisines: voisines ?? trois,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// La partie que l'écran montre en ce moment.
  String montree(WidgetTester tester) =>
      tester.widget<CorrGameScreen>(find.byType(CorrGameScreen)).game.id;

  Future<void> glisse(WidgetTester tester, double dx) async {
    await tester.drag(find.byType(GameBoardView), Offset(dx, 0));
    await tester.pumpAndSettle();
  }

  testWidgets('vers la gauche, la partie suivante', (tester) async {
    await ouvrir(tester, 0);
    expect(montree(tester), 'g1');

    await glisse(tester, -300);
    expect(montree(tester), 'g2');

    await glisse(tester, -300);
    expect(montree(tester), 'g3');
  });

  testWidgets('vers la droite, la précédente', (tester) async {
    await ouvrir(tester, 2);
    await glisse(tester, 300);
    expect(montree(tester), 'g2');
  });

  testWidgets('au bout de la liste, on ne va nulle part', (tester) async {
    await ouvrir(tester, 0);
    await glisse(tester, 300);
    expect(montree(tester), 'g1', reason: 'il n y a rien avant la première');

    await ouvrir(tester, 2);
    await glisse(tester, -300);
    expect(montree(tester), 'g3', reason: 'ni rien après la dernière');
  });

  testWidgets('un doigt qui dérape ne change pas de partie', (tester) async {
    await ouvrir(tester, 0);
    // Le quart de la largeur fait deux cents points sur l'écran des tests.
    await glisse(tester, -60);
    expect(montree(tester), 'g1');
  });

  // Une partie ouverte depuis un profil n'a pas de liste : rien à glisser.
  testWidgets('sans voisines, le geste ne fait rien', (tester) async {
    await ouvrir(tester, 0, voisines: const []);
    await glisse(tester, -300);
    expect(montree(tester), 'g1');
  });

  // Un bandeau qui PEUT défiler garde son geste : Flutter donne la main au
  // plus profond. Sans cela, on ne relirait plus les coups d'une longue
  // partie — le premier glissement changerait de partie. Un bandeau qui n'a
  // rien à faire défiler, lui, laisse passer : il n'accepte pas le geste.
  testWidgets('le bandeau des coups défile, il ne change pas de partie', (
    tester,
  ) async {
    // Un écran étroit : le bandeau déborde, donc il défile.
    tester.view.physicalSize = const Size(300, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: CorrGameScreen(
          game: partie('g1', 'Ana', coups: _coups),
          service: service,
          myPseudo: 'nino',
          voisines: [
            partie('g1', 'Ana', coups: _coups),
            trois[1],
            trois[2],
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bande = find.descendant(
      of: find.byType(MoveStrip),
      matching: find.byType(SingleChildScrollView),
    );
    final defilement = tester.widget<SingleChildScrollView>(bande).controller!;
    expect(
      defilement.position.maxScrollExtent,
      greaterThan(0),
      reason: 'test vain : le bandeau tient tout entier à l écran',
    );

    await tester.drag(bande, const Offset(-120, 0));
    await tester.pumpAndSettle();

    expect(montree(tester), 'g1');
    expect(defilement.offset, greaterThan(0), reason: 'c est lui qui a bougé');
  });

  // Le plateau prend la pièce au contact : le glissement doit la relâcher.
  testWidgets('un glissement ne laisse pas de pièce prise', (tester) async {
    await ouvrir(tester, 0);

    // Une pièce blanche, prise comme le doigt la prend : au contact.
    final depart = Board.initial();
    Cell? aPrendre;
    for (var c = 0; c < kCols && aPrendre == null; c++) {
      for (var r = 0; r < kRows; r++) {
        if (depart.at(c, r)?.camp == Camp.blanc) {
          aPrendre = Cell(c, r);
          break;
        }
      }
    }
    tester
        .widget<GameBoardView>(find.byType(GameBoardView))
        .onTapCell(aPrendre!);
    await tester.pumpAndSettle();
    expect(
      tester.widget<GameBoardView>(find.byType(GameBoardView)).selected,
      isNotNull,
      reason: 'test vain : aucune pièce prise',
    );

    // On glisse vers la droite depuis la PREMIÈRE : on ne va nulle part,
    // donc l'écran reste — et il doit avoir lâché sa pièce.
    await glisse(tester, 300);
    expect(montree(tester), 'g1');
    expect(
      tester.widget<GameBoardView>(find.byType(GameBoardView)).selected,
      isNull,
    );
  });
}
