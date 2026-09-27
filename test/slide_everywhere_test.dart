/// Les pièces glissent, partout et tout le temps.
///
/// Nino : « la glissée doit marcher partout : quand je joue, quand
/// l'adversaire joue, en local, en ligne, en correspondance, en analyse, dans
/// l'historique, contre Deep Grey, et même quand on navigue avec les flèches
/// ou le bandeau du bas. Pour un multisaut adverse, on doit voir la pièce
/// passer par là où les petits carrés s'affichent. »
///
/// Ce qui manquait, précisément :
///   — le multisaut coupait en ligne droite, du départ à l'arrivée ;
///   — le lecteur d'historique et l'analyse n'animaient RIEN : le plateau
///     sautait d'une position à l'autre ;
///   — la navigation (flèches, bandeau) n'animait rien non plus ;
///   — en correspondance, le coup de l'adversaire apparaissait déjà joué, et
///     le bandeau du bas ne répondait pas du tout.
library;

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/engine/move.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/game/last_move.dart';
import 'package:lafuga/game/move_controller.dart';
import 'package:lafuga/game/nmc.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/screens/corr_game_screen.dart';
import 'package:lafuga/ui/screens/game_screen.dart';
import 'package:lafuga/ui/screens/replay_screen.dart';
import 'package:lafuga/ui/widgets/board_geometry.dart';
import 'package:lafuga/ui/widgets/board_painter.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    clearReplayCache();
  });

  GameBoardView vue(WidgetTester tester) =>
      tester.widget<GameBoardView>(find.byType(GameBoardView));

  group('Le multisaut passe par ses atterrissages', () {
    final g = BoardGeometry(size: const Size(350, 500), flipped: true);

    test('à mi-parcours, la pièce est SUR le petit carré', () {
      // Do1 → Do3 → Mi3 : deux bonds. À la moitié du temps, la pièce doit être
      // exactement sur Do3, pas au milieu du segment Do1–Mi3.
      const chemin = [Cell(0, 0), Cell(0, 2), Cell(2, 2)];
      final milieu = slidePosition(g, chemin, 0.5);
      expect(milieu, g.cellRect(0, 2), reason: 'elle coupe au lieu de passer');

      final droite = slidePosition(g, const [Cell(0, 0), Cell(2, 2)], 0.5);
      expect(
        milieu,
        isNot(droite),
        reason: 'le chemin ne change rien : le multisaut coupe toujours',
      );
    });

    test('elle part du départ et finit à l arrivée', () {
      const chemin = [Cell(0, 0), Cell(0, 2), Cell(2, 2)];
      expect(slidePosition(g, chemin, 0), g.cellRect(0, 0));
      expect(slidePosition(g, chemin, 1), g.cellRect(2, 2));
    });

    test('au quart, elle est à mi-chemin du PREMIER bond', () {
      const chemin = [Cell(0, 0), Cell(0, 2), Cell(2, 2)];
      final attendu = Rect.lerp(g.cellRect(0, 0), g.cellRect(0, 2), 0.5)!;
      expect(slidePosition(g, chemin, 0.25), attendu);
    });

    testWidgets('et le PEINTRE s en sert : la pièce est peinte là-bas', (
      tester,
    ) async {
      // Les cas ci-dessus éprouvent le calcul de position. Ils ne disent rien
      // de son emploi : en supprimant le chemin dans le peintre, ils passaient
      // tous. Ici on peint pour de vrai et on compte les pixels posés.
      const taille = Size(350, 500);
      const chemin = [Cell(0, 2)]; // atterrissage intermédiaire
      const depart = Cell(0, 0);
      const arrivee = Cell(2, 2);

      Future<Map<String, int>> peindre({required bool avecChemin}) async {
        final compte = <String, int>{};
        await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          FlyingPiecesPainter(
            geometry: g,
            palette: paletteOf(kDefaultTheme),
            slides: const [(Piece.blancNurse, depart, arrivee)],
            progress: 0.5,
            jumpPath: avecChemin ? chemin : const [],
          ).paint(Canvas(recorder), taille);
          final image = await recorder.endRecording().toImage(
            taille.width.toInt(),
            taille.height.toInt(),
          );
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          int dans(Rect zone) {
            var n = 0;
            for (var y = zone.top.ceil(); y < zone.bottom.floor(); y++) {
              for (var x = zone.left.ceil(); x < zone.right.floor(); x++) {
                if (x < 0 || y < 0 || x >= image.width || y >= image.height) {
                  continue;
                }
                if (data.getUint8((y * image.width + x) * 4 + 3) != 0) n++;
              }
            }
            return n;
          }

          compte['atterrissage'] = dans(g.cellRect(0, 2));
          compte['milieu droit'] = dans(
            Rect.lerp(g.cellRect(0, 0), g.cellRect(2, 2), 0.5)!,
          );
        });
        return compte;
      }

      final avec = await peindre(avecChemin: true);
      final sans = await peindre(avecChemin: false);

      expect(
        sans['milieu droit'],
        greaterThan(0),
        reason: 'sans chemin la pièce devrait couper : mesure sans valeur',
      );
      expect(
        avec['atterrissage'],
        greaterThan(0),
        reason:
            'le peintre ignore le chemin : la pièce coupe au lieu de '
            'passer par le petit carré',
      );
      expect(
        avec['milieu droit'],
        lessThan(sans['milieu droit']!),
        reason: 'la pièce est toujours sur la ligne droite',
      );
    });

    test('un coup ordinaire va tout droit', () {
      const chemin = [Cell(0, 0), Cell(0, 3)];
      expect(
        slidePosition(g, chemin, 0.5),
        Rect.lerp(g.cellRect(0, 0), g.cellRect(0, 3), 0.5),
      );
    });
  });

  group('Un coup construit ailleurs garde son chemin', () {
    test('Deep Grey, le réseau, la relecture : le multisaut ne coupe pas', () {
      // Le générateur ne retient que l'ARRIVÉE d'un saut : le chemin n'est
      // porté par aucun coup. `applyGeneratedMove` ne le transmettait donc
      // pas, et la pièce de Deep Grey coupait en ligne droite là où la nôtre
      // passait par ses atterrissages.
      final board = Board.empty();
      board.set(0, 0, Piece.blancHeritier);
      board.set(0, 1, Piece.blancNurse);
      board.set(0, 3, Piece.blancNurse);
      board.set(6, 7, Piece.noirHeritier);
      final game = MoveController(board: board);

      final multisaut = generateMoves(game.board, Camp.blanc)
          .where(
            (m) =>
                m.kind == MoveKind.jump &&
                jumpPathOf(game.board, m.from, m.to).isNotEmpty,
          )
          .toList();
      if (multisaut.isEmpty) {
        fail('aucun multisaut dans cette position : le test ne prouve rien');
      }

      final result = game.applyGeneratedMove(multisaut.first);
      expect(
        result.jumpPath,
        isNotEmpty,
        reason: 'le coup arrive sans son chemin : la pièce coupera tout droit',
      );
      expect(
        result.jumpPath,
        jumpPathOf(board, multisaut.first.from, multisaut.first.to),
      );
    });
  });

  group('Le lecteur d historique anime la navigation', () {
    String partie() => buildNmc(
      const NmcMeta(
        date: '2026-09-27',
        player1: 'Nino',
        player2: 'Ana',
        blanc: 'Nino',
        objectif: 'partie',
        cadence: 'zen',
        result: '1-0',
        method: 'mat',
        points: '1',
      ),
      ['Do2-Do3', 'Do7-Do6', 'Ré2-Ré3'],
    );

    testWidgets('avancer fait glisser les pièces', (tester) async {
      await tester.pumpWidget(MaterialApp(home: ReplayScreen(nmc: partie())));
      await tester.pumpAndSettle();
      final jeton = vue(tester).slideToken;

      await tester.tap(find.text('>'));
      await tester.pump();

      expect(
        vue(tester).slides,
        isNotEmpty,
        reason: 'le plateau saute d une position à l autre sans rien animer',
      );
      expect(vue(tester).slideToken, greaterThan(jeton));
      await tester.pumpAndSettle();
    });

    testWidgets('reculer aussi', (tester) async {
      await tester.pumpWidget(MaterialApp(home: ReplayScreen(nmc: partie())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('>'));
      await tester.pumpAndSettle();
      final jeton = vue(tester).slideToken;

      await tester.tap(find.text('<'));
      await tester.pump();

      expect(vue(tester).slides, isNotEmpty, reason: 'reculer n anime rien');
      expect(vue(tester).slideToken, greaterThan(jeton));
      await tester.pumpAndSettle();
    });
  });

  group('La partie locale anime la navigation', () {
    testWidgets('revenir sur un coup le rejoue', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: GameScreen(aiCamp: null)),
      );
      await tester.pumpAndSettle();

      // Deux coups, pour avoir de quoi naviguer.
      for (var i = 0; i < 2; i++) {
        final v = vue(tester);
        final camp = i == 0 ? Camp.blanc : Camp.noir;
        final coup = generateMoves(v.board, camp).firstWhere(
          (m) => m.movedCells.length == 1 && m.movedCells.first.onBoard,
        );
        v.onTapCell(coup.from);
        await tester.pump();
        v.onTapCell(coup.movedCells.first);
        await tester.pump();
        v.onTapCell(coup.movedCells.first);
        await tester.pumpAndSettle();
      }

      final jeton = vue(tester).slideToken;
      await tester.tap(find.text('<'));
      await tester.pump();

      expect(
        vue(tester).slideToken,
        greaterThan(jeton),
        reason: 'la flèche ne rejoue pas le coup, elle le fait apparaître',
      );
      expect(vue(tester).slides, isNotEmpty);
      await tester.pumpAndSettle();
    });
  });

  group('Correspondance', () {
    /// Un client dont la partie peut changer entre deux appels.
    ({OnlineClient client, void Function(String) setMoves}) faux(
      String coupsInitiaux,
    ) {
      var coups = coupsInitiaux;
      final client = OnlineClient(
        api: ApiClient(
          client: MockClient((request) async {
            final corps = request.url.path == '/corr_list'
                ? {
                    'ok': true,
                    'games': [_partie(coups)],
                  }
                : {'ok': true};
            return http.Response(
              jsonEncode(corps),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );
      return (
        client: client,
        setMoves: (c) {
          coups = c;
          clearReplayCache();
        },
      );
    }

    Future<void> ouvrir(
      WidgetTester tester,
      OnlineClient client,
      String coups,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CorrGameScreen(
            game: CorrGame.fromJson(_partie(coups)),
            service: CorrespondenceService(client),
            myPseudo: 'nino',
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('à l ouverture, le dernier coup se joue sous les yeux', (
      tester,
    ) async {
      final f = faux('Do2-Do3\nDo7-Do6');
      await ouvrir(tester, f.client, 'Do2-Do3\nDo7-Do6');

      expect(
        vue(tester).slides,
        isNotEmpty,
        reason:
            'on tombe directement sur la position : le coup de '
            'l adversaire s est joué sans qu on le voie',
      );
      await tester.pumpAndSettle();
    });

    testWidgets('le coup adverse qui arrive se joue aussi', (tester) async {
      final f = faux('Do2-Do3');
      await ouvrir(tester, f.client, 'Do2-Do3');
      await tester.pumpAndSettle();
      final jeton = vue(tester).slideToken;

      f.setMoves('Do2-Do3\nDo7-Do6');
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();

      expect(
        vue(tester).slideToken,
        greaterThan(jeton),
        reason: 'le coup arrive sans être montré',
      );
      await tester.pumpAndSettle();
    });

    testWidgets('même le coup FINAL se joue sous les yeux', (tester) async {
      // « et ce même s'il s'agit du coup final ». Une partie finie s'ouvrait
      // sur sa position d'arrivée, verdict compris, sans qu'on ait rien vu.
      // La fugue est le cas limite : l'Héritier quitte le plateau, donc sa
      // glissée n'existe que si on la fabrique.
      final f = faux('Do2-Do3\nFa8*');
      await tester.pumpWidget(
        MaterialApp(
          home: CorrGameScreen(
            game: CorrGame.fromJson({
              ..._partie('Do2-Do3\nFa8*'),
              'statut': 'termine',
              'resultat': '0-1',
              'methode': 'fugue',
              'gagne': false,
              'my_turn': false,
            }),
            service: CorrespondenceService(f.client),
            myPseudo: 'nino',
          ),
        ),
      );
      await tester.pump();

      final v = vue(tester);
      expect(
        v.slides,
        isNotEmpty,
        reason:
            'la partie finie s ouvre sur sa position, sans montrer le '
            'coup qui l a close',
      );
      expect(
        [for (final (_, _, to) in v.slides) to],
        contains(rallyDisplayCell(Camp.noir)),
        reason: 'l Héritier qui fugue ne glisse pas jusqu à son ralliement',
      );
      await tester.pumpAndSettle();
    });

    testWidgets('le bandeau du bas répond enfin', (tester) async {
      final f = faux('Do2-Do3\nDo7-Do6');
      await ouvrir(tester, f.client, 'Do2-Do3\nDo7-Do6');
      await tester.pumpAndSettle();
      final finale = vue(tester).board.render();

      // La flèche « précédent » : les flèches ne faisaient RIEN.
      await tester.tap(find.text('<'));
      await tester.pumpAndSettle();

      expect(
        vue(tester).board.render(),
        isNot(finale),
        reason: 'les flèches du bandeau ne font rien en correspondance',
      );
    });

    testWidgets('revenir au dernier coup rend la partie jouable', (
      tester,
    ) async {
      final f = faux('Do2-Do3\nDo7-Do6');
      await ouvrir(tester, f.client, 'Do2-Do3\nDo7-Do6');
      await tester.pumpAndSettle();
      final finale = vue(tester).board.render();

      await tester.tap(find.text('<'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('>'));
      await tester.pumpAndSettle();

      expect(
        vue(tester).board.render(),
        finale,
        reason: 'on ne revient pas au présent : la partie reste bloquée',
      );
    });
  });
}

Map<String, dynamic> _partie(String coups) => {
  'id': 'g1',
  'statut': 'en_cours',
  'adversaire': 'Ana',
  'ma_couleur': 'Blanc',
  'turn': 'Blanc',
  'my_turn': true,
  'moves_text': coups,
  'objectif': 'partie',
};
