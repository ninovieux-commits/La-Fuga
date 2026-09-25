/// Le mode analyse : on explore, on se trompe, on revient, on essaie autre
/// chose.
///
/// Trois contrats, tous nés d'un défaut constaté en jeu :
///  - le plateau garde le sens qu'il avait sur l'écran d'où l'on vient ;
///  - reculer d'un coup n'enferme pas dans la suite déjà jouée ;
///  - l'absence de bandeaux dit qu'on analyse au lieu de jouer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/game_screen.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:lafuga/ui/widgets/move_strip.dart';
import 'package:lafuga/ui/widgets/player_panel.dart';
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
  });

  GameBoardView viewOf(WidgetTester tester) =>
      tester.widget<GameBoardView>(find.byType(GameBoardView));

  MoveStrip stripOf(WidgetTester tester) =>
      tester.widget<MoveStrip>(find.byType(MoveStrip));

  /// Joue un coup simple du camp donné : sélection, case d'arrivée, validation.
  Future<String> playSimpleMove(
    WidgetTester tester,
    Camp camp, {
    int skip = 0,
  }) async {
    final view = viewOf(tester);
    final moves = generateMoves(view.board, camp)
        .where((m) => m.movedCells.length == 1 && m.movedCells.first.onBoard)
        .toList();
    final move = moves[skip];
    final to = move.movedCells.first;
    view.onTapCell(move.from);
    await tester.pump();
    view.onTapCell(to);
    await tester.pump();
    view.onTapCell(to); // revalider : le coup part
    await tester.pumpAndSettle();
    return '${move.from} → $to';
  }

  testWidgets('le plateau garde le sens de l écran d où l on vient', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(aiCamp: null, analysis: true, initialFlipped: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      viewOf(tester).flipped,
      isFalse,
      reason: 'les Noirs restent en bas, comme sur la partie quittée',
    );
  });

  testWidgets('sans consigne, le plateau garde son sens habituel', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: GameScreen(aiCamp: null, analysis: true)),
    );
    await tester.pumpAndSettle();
    expect(viewOf(tester).flipped, isTrue);
  });

  testWidgets('en analyse, les bandeaux disparaissent', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: GameScreen(aiCamp: null, analysis: true)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPanel), findsNothing);
  });

  testWidgets('en partie, les deux bandeaux sont là', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(aiCamp: null)));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPanel), findsNWidgets(2));
  });

  testWidgets('reculer d un coup puis en jouer un autre', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: GameScreen(aiCamp: null, analysis: true)),
    );
    await tester.pumpAndSettle();

    await playSimpleMove(tester, Camp.blanc);
    await playSimpleMove(tester, Camp.noir);
    final joues = stripOf(tester).moves.toList();
    expect(joues, hasLength(2));

    // On revient sur le premier coup.
    stripOf(tester).onSelect(0);
    await tester.pumpAndSettle();
    expect(stripOf(tester).activeIndex, 0);
    expect(
      viewOf(tester).board.key,
      isNot(equals(joues.length)),
      reason: 'la position affichée est celle d apres le premier coup',
    );

    // Et on part sur une AUTRE suite : le deuxième coup est remplacé.
    final autre = await playSimpleMove(tester, Camp.noir, skip: 1);
    final apres = stripOf(tester).moves.toList();

    expect(apres, hasLength(2), reason: 'la ligne repart du premier coup');
    expect(apres.first, joues.first, reason: 'le premier coup est gardé');
    expect(
      apres.last,
      isNot(joues.last),
      reason: 'le deuxième coup n est plus celui d avant ($autre)',
    );
    expect(stripOf(tester).activeIndex, isNull, reason: 'on est au présent');
  });

  testWidgets('hors analyse, reculer ne laisse pas jouer', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(aiCamp: null)));
    await tester.pumpAndSettle();

    await playSimpleMove(tester, Camp.blanc);
    await playSimpleMove(tester, Camp.noir);
    final joues = stripOf(tester).moves.toList();

    stripOf(tester).onSelect(0);
    await tester.pumpAndSettle();

    final view = viewOf(tester);
    final move = generateMoves(view.board, Camp.noir).first;
    view.onTapCell(move.from);
    await tester.pumpAndSettle();

    expect(
      stripOf(tester).moves,
      joues,
      reason: 'une vraie partie ne se réécrit pas',
    );
  });
}
