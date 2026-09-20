/// L'écran de jeu, disposé comme celui de Kivy : barre du haut, panneaux des
/// joueurs avec pièces prises, et bandeau des coups navigable.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/game_screen.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:lafuga/ui/widgets/player_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.load();
    await Translations.load('fr');
  });

  /// Ouvre une partie locale : les deux camps sont joués sur l'appareil.
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(aiCamp: null)));
    await tester.pumpAndSettle();
  }

  /// Joue un coup simple du camp donné : sélectionner, déplacer, revalider.
  Future<void> playOneMove(WidgetTester tester, Camp camp) async {
    final view = tester.widget<GameBoardView>(find.byType(GameBoardView));
    final move = generateMoves(
      view.board,
      camp,
    ).firstWhere((m) => m.movedCells.length == 1 && m.movedCells.first.onBoard);
    final to = move.movedCells.first;

    view.onTapCell(move.from);
    await tester.pump();
    view.onTapCell(to);
    await tester.pump();
    view.onTapCell(to);
    await tester.pumpAndSettle();
  }

  testWidgets('les deux panneaux portent noms, chronos et pièces prises', (
    tester,
  ) async {
    await open(tester);

    expect(find.byType(PlayerPanel), findsNWidgets(2));
    expect(find.text('Joueur 1'), findsOneWidget);
    expect(find.text('Joueur 2'), findsOneWidget);
    expect(
      find.byType(CapturesStrip),
      findsNWidgets(2),
      reason: 'chacun voit ses prises',
    );
  });

  testWidgets('la barre du haut retourne le plateau', (tester) async {
    await open(tester);

    final before = tester.widget<GameBoardView>(find.byType(GameBoardView));
    await tester.tap(find.text('< >'));
    await tester.pumpAndSettle();

    final after = tester.widget<GameBoardView>(find.byType(GameBoardView));
    expect(after.flipped, isNot(before.flipped));
  });

  testWidgets('la barre du haut ramène au menu', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const GameScreen(aiCamp: null),
              ),
            ),
            child: const Text('jouer'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('jouer'));
    await tester.pumpAndSettle();
    expect(find.byType(GameScreen), findsOneWidget);

    await tester.tap(find.text('Retour au menu'));
    await tester.pumpAndSettle();

    expect(find.byType(GameScreen), findsNothing);
  });

  testWidgets('le bandeau des coups apparaît au premier coup', (tester) async {
    await open(tester);
    expect(find.textContaining('1.'), findsNothing);

    await playOneMove(tester, Camp.blanc);

    expect(find.textContaining('1.'), findsOneWidget);
  });

  testWidgets('on revoit un coup passé, puis on revient au présent', (
    tester,
  ) async {
    await open(tester);
    await playOneMove(tester, Camp.blanc);
    await playOneMove(tester, Camp.noir);

    final present = tester.widget<GameBoardView>(find.byType(GameBoardView));
    final presentKey = present.board.key;

    // Reculer d'un coup montre la position d'avant.
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    final past = tester.widget<GameBoardView>(find.byType(GameBoardView));
    expect(past.board.key, isNot(presentKey));
    expect(
      past.selected,
      isNull,
      reason: 'on ne joue pas en regardant le passé',
    );

    // Revenir au présent.
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(
      tester.widget<GameBoardView>(find.byType(GameBoardView)).board.key,
      presentKey,
    );
  });

  testWidgets('en analyse, ni abandon ni nulle', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: GameScreen(aiCamp: null, analysis: true)),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Abandonner'), findsNothing);
    expect(find.byTooltip('Proposer nulle'), findsNothing);
  });
}
