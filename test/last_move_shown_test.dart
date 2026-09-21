/// Le dernier coup est TOUJOURS indiqué, quel que soit le mode et qui a joué.
///
/// Kivy reconstruit la mise en évidence depuis la notation, dans
/// `_record_move`, et le fait donc aussi bien pour son propre coup que pour
/// celui de l'adversaire ou de Deep Grey. Ces tests fixent ce contrat : le
/// cadre a longtemps manqué pour les coups joués au doigt.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/game_screen.dart';
import 'package:lafuga/ui/widgets/board_painter.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Map<String, Object> _launched = {'lang_chosen': true, 'tuto_seen': true};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(_launched);
    await Settings.load();
    await Translations.load('fr');
  });

  GameBoardView viewOf(WidgetTester tester) =>
      tester.widget<GameBoardView>(find.byType(GameBoardView));

  BoardPiecesPainter painterOf(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((p) => p.painter)
      .whereType<BoardPiecesPainter>()
      .first;

  testWidgets('un coup joué au doigt est encadré', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(aiCamp: null)));
    await tester.pumpAndSettle();

    final view = viewOf(tester);
    final move = generateMoves(
      view.board,
      Camp.blanc,
    ).firstWhere((m) => m.movedCells.length == 1 && m.movedCells.first.onBoard);
    final to = move.movedCells.first;

    view.onTapCell(move.from);
    await tester.pump();
    view.onTapCell(to);
    await tester.pump();
    view.onTapCell(to); // revalider : le coup est joué
    await tester.pumpAndSettle();

    final last = viewOf(tester).lastMove;
    expect(
      last,
      isNotNull,
      reason: 'le dernier coup doit être mis en évidence',
    );
    expect(last!.framedCells, contains(move.from));
    expect(last.framedCells, contains(to));
    // Cadre NOIR pour un coup blanc, blanc pour un coup noir.
    expect(last.camp, Camp.blanc);
  });

  testWidgets('et il glisse, comme les coups de Deep Grey', (tester) async {
    await Settings.instance.setSlideSpeed(0.3);
    await tester.pumpWidget(const MaterialApp(home: GameScreen(aiCamp: null)));
    await tester.pumpAndSettle();

    final before = viewOf(tester).slideToken;
    final view = viewOf(tester);
    final move = generateMoves(
      view.board,
      Camp.blanc,
    ).firstWhere((m) => m.movedCells.length == 1 && m.movedCells.first.onBoard);

    view.onTapCell(move.from);
    await tester.pump();
    view.onTapCell(move.movedCells.first);
    await tester.pump();

    expect(
      viewOf(tester).slideToken,
      greaterThan(before),
      reason: 'le déplacement glisse dès le geste, sans attendre la validation',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('le cadre se dessine au-dessus des pièces', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(aiCamp: null)));
    await tester.pumpAndSettle();

    final view = viewOf(tester);
    view.onTapCell(const Cell(0, 1));
    await tester.pump();

    // La sélection est portée par le peintre des pièces, qui trace ses cadres
    // après avoir posé les pièces.
    expect(painterOf(tester).selected, const Cell(0, 1));
  });
}
