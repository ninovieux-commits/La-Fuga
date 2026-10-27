/// Le dernier coup est TOUJOURS indiqué, quel que soit le mode et qui a joué.
///
/// Kivy reconstruit la mise en évidence depuis la notation, dans
/// `_record_move`, et le fait donc aussi bien pour son propre coup que pour
/// celui de l'adversaire ou de Deep Grey. Ces tests fixent ce contrat : le
/// cadre a longtemps manqué pour les coups joués au doigt.
///
/// Et il manquait aussi en REVOYANT un coup passé : on retrouvait la position
/// sans voir ce qui venait de s'y jouer, alors que c'est tout ce qu'on venait
/// chercher. La correspondance et la partie en ligne l'encadraient ; l'écran
/// local, non. Nino : « Oui aligne le local aussi ».
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

  group('En revoyant un coup passé', () {
    /// Joue un coup au doigt et rend ses deux cases.
    Future<(Cell, Cell)> joue(WidgetTester tester, Camp camp) async {
      final view = viewOf(tester);
      final move = generateMoves(view.board, camp).firstWhere(
        (m) => m.movedCells.length == 1 && m.movedCells.first.onBoard,
      );
      final to = move.movedCells.first;
      for (final cell in [move.from, to, to]) {
        viewOf(tester).onTapCell(cell);
        await tester.pumpAndSettle();
      }
      return (move.from, to);
    }

    testWidgets('c est CE coup qui est encadré, pas le dernier joué', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: GameScreen(aiCamp: null)),
      );
      await tester.pumpAndSettle();

      final (premierDe, premierVers) = await joue(tester, Camp.blanc);
      final (secondDe, secondVers) = await joue(tester, Camp.noir);
      expect(viewOf(tester).lastMove!.framedCells, contains(secondVers));

      // Un pas en arrière : on regarde le PREMIER coup.
      await tester.tap(find.byTooltip(T('Coup précédent')));
      await tester.pumpAndSettle();

      final vu = viewOf(tester).lastMove;
      expect(
        vu,
        isNotNull,
        reason: 'l écran local n encadrait rien pendant la revue',
      );
      expect(vu!.framedCells, contains(premierDe));
      expect(vu.framedCells, contains(premierVers));
      expect(
        vu.framedCells,
        isNot(contains(secondVers)),
        reason: 'ce n est pas le coup qu on regarde',
      );
      expect(vu.camp, Camp.blanc, reason: 'le premier coup est blanc');
    });

    testWidgets('la position de départ n encadre rien : aucun coup n y mène', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: GameScreen(aiCamp: null)),
      );
      await tester.pumpAndSettle();
      await joue(tester, Camp.blanc);

      await tester.tap(find.byTooltip(T('Coup précédent')));
      await tester.pumpAndSettle();
      expect(viewOf(tester).lastMove, isNull);
    });

    testWidgets('revenu au présent, c est le dernier coup qui est encadré', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: GameScreen(aiCamp: null)),
      );
      await tester.pumpAndSettle();
      await joue(tester, Camp.blanc);
      final (_, secondVers) = await joue(tester, Camp.noir);

      await tester.tap(find.byTooltip(T('Coup précédent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(T('Coup suivant')));
      await tester.pumpAndSettle();

      final vu = viewOf(tester).lastMove;
      expect(vu, isNotNull);
      expect(vu!.framedCells, contains(secondVers));
      expect(vu.camp, Camp.noir);
    });
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
