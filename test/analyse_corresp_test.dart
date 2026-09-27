/// L'analyse d'une partie de correspondance part de CE QU'ON REGARDE.
///
/// Nino : « en partie corresp, le mode analyse doit pouvoir être lancé depuis
/// la position affichée, et pas seulement depuis la position dernier coup
/// joué. Elle doit aussi pouvoir permettre de remonter jusqu'au premier coup
/// de la partie si on est en analyse, pour tester d'autres variantes
/// éventuelles. »
///
/// Deux choses, donc : le point de départ, et le passé qu'on emporte avec.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/literal_replay.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/notation.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/clock.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/corr_game_screen.dart';
import 'package:lafuga/ui/screens/game_screen.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:lafuga/ui/widgets/game_top_bar.dart';
import 'package:lafuga/ui/widgets/move_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cinq coups d'une vraie partie, assez pour qu'il y ait un « avant ».
const _coups = ['Fa3-Sol4', 'Fa6-Sol5', 'Sol2-Fa3', '(Si7Si8)-Si6', 'Fa2-Fa4'];

Board _apres(int nombre) {
  var b = Board.initial();
  for (final coup in _coups.take(nombre)) {
    b = applyNotationLiterally(b, coup).board;
  }
  return b;
}

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
    clearReplayCache();
    setScaleSize(const Size(400, 800));
    client = OnlineClient(
      api: ApiClient(
        client: MockClient(
          (r) async => http.Response(
            jsonEncode({'ok': true}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      ),
    );
  });

  Future<void> ouvrirCorr(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CorrGameScreen(
          game: CorrGame.fromJson({
            'id': 'g1',
            'statut': 'en_cours',
            'adversaire': 'celia',
            'ma_couleur': 'Blanc',
            'turn': 'Blanc',
            'my_turn': true,
            'moves_text': _coups.join('\n'),
            'objectif': 'partie',
          }),
          service: CorrespondenceService(client),
          myPseudo: 'nino',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Le point de départ de l analyse', () {
    testWidgets('sans rien revoir : le dernier coup', (tester) async {
      await ouvrirCorr(tester);
      tester.widget<GameTopBar>(find.byType(GameTopBar)).onAnalyse!();
      await tester.pumpAndSettle();

      final ecran = tester.widget<GameScreen>(find.byType(GameScreen));
      expect(ecran.initialMoves, _coups);
      expect(ecran.analysis, isTrue);
      expect(
        ecran.aiCamp,
        isNull,
        reason: 'Deep Grey soufflerait le coup d une partie en cours',
      );
    });

    testWidgets('en revoyant le coup 2 : c est le coup 2 qu on analyse', (
      tester,
    ) async {
      await ouvrirCorr(tester);
      tester.widget<MoveStrip>(find.byType(MoveStrip)).onSelect(1);
      await tester.pumpAndSettle();

      tester.widget<GameTopBar>(find.byType(GameTopBar)).onAnalyse!();
      await tester.pumpAndSettle();

      final ecran = tester.widget<GameScreen>(find.byType(GameScreen));
      expect(
        ecran.initialMoves,
        _coups.take(2).toList(),
        reason: 'l analyse repart du dernier coup, pas de celui affiché',
      );

      final vue = tester.widget<GameBoardView>(find.byType(GameBoardView));
      expect(
        vue.board.positionKey(Camp.blanc),
        _apres(2).positionKey(Camp.blanc),
        reason: 'la position analysée n est pas celle qu on regardait',
      );
    });
  });

  group('Ce qu on emporte : le passé de la partie', () {
    Future<void> ouvrirAnalyse(WidgetTester tester, int jusque) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            cadence: Cadence.zen,
            aiCamp: null,
            initialBoard: Board.initial(),
            initialTurn: Camp.blanc,
            initialMoves: _coups.take(jusque).toList(),
            analysis: true,
            analysisFromCorr: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('les coups d avant sont là, jusqu au premier', (tester) async {
      await ouvrirAnalyse(tester, 4);
      final bandeau = tester.widget<MoveStrip>(find.byType(MoveStrip));
      expect(
        bandeau.moves,
        _coups.take(4).toList(),
        reason: 'sans son histoire, l analyse ne mène nulle part en arrière',
      );
    });

    testWidgets('et on peut remonter jusqu au premier coup', (tester) async {
      await ouvrirAnalyse(tester, 4);
      tester.widget<MoveStrip>(find.byType(MoveStrip)).onSelect(0);
      await tester.pumpAndSettle();

      final vue = tester.widget<GameBoardView>(find.byType(GameBoardView));
      expect(
        vue.board.positionKey(Camp.noir),
        _apres(1).positionKey(Camp.noir),
        reason: 'la flèche ne remonte pas jusqu au premier coup',
      );
    });

    testWidgets('la position de départ est bien celle des coups rejoués', (
      tester,
    ) async {
      await ouvrirAnalyse(tester, 3);
      final vue = tester.widget<GameBoardView>(find.byType(GameBoardView));
      expect(
        vue.board.positionKey(Camp.noir),
        _apres(3).positionKey(Camp.noir),
      );
    });

    testWidgets('on peut y jouer une variante depuis un coup passé', (
      tester,
    ) async {
      // C'est tout l'objet : remonter, puis essayer autre chose.
      await ouvrirAnalyse(tester, 4);
      tester.widget<MoveStrip>(find.byType(MoveStrip)).onSelect(0);
      await tester.pumpAndSettle();

      // Les Noirs jouent : on prend un coup légal AUTRE que celui de la
      // partie, choisi par le générateur plutôt que deviné.
      final autre = generateMoves(_apres(1), Camp.noir).firstWhere(
        (m) =>
            m.movedCells.length == 1 &&
            m.movedCells.first.onBoard &&
            notationOfMove(m) != _coups[1],
        orElse: () => throw StateError('aucun autre coup noir'),
      );
      final vue = tester.widget<GameBoardView>(find.byType(GameBoardView));
      final vers = autre.movedCells.first;
      vue.onTapCell(autre.from);
      await tester.pump();
      vue.onTapCell(vers);
      await tester.pump();
      // Retoucher l'arrivée valide le coup, comme au doigt.
      vue.onTapCell(vers);
      await tester.pumpAndSettle();

      final bandeau = tester.widget<MoveStrip>(find.byType(MoveStrip));
      expect(
        bandeau.moves.length,
        2,
        reason: 'la variante n a pas remplacé la suite de la partie',
      );
      expect(bandeau.moves.first, _coups.first);
      expect(
        bandeau.moves.last,
        isNot(_coups[1]),
        reason: 'c est le coup de la partie, pas la variante',
      );
    });
  });
}
