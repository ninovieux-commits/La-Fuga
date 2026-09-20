/// Le glissement des pièces — l'équivalent d'`animate_slide` (main.py).
///
/// Kivy anime CHAQUE coup, et le réglage « Vitesse de glissée des pièces »
/// en fixe la durée (0 = instantané). Sans cette animation, les pièces se
/// téléportent et le réglage ne commande rien.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/widgets/board_painter.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:lafuga/ui/screens/game_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.load();
    await Translations.load('fr');
  });

  /// Le peintre des pièces, tel qu'il est à cet instant.
  BoardPiecesPainter painterOf(WidgetTester tester) {
    final paints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
    return paints.map((p) => p.painter).whereType<BoardPiecesPainter>().first;
  }

  testWidgets('une pièce qui glisse n est pas encore sur sa case', (
    tester,
  ) async {
    await Settings.instance.setSlideSpeed(0.4);

    final board = Board.initial();
    const piece = Piece(PieceType.soldat, Camp.blanc);
    var token = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              Expanded(
                child: GameBoardView(
                  board: board,
                  palette: paletteOf(kDefaultTheme),
                  flipped: true,
                  onTapCell: (_) {},
                  slides: const [(piece, Cell(0, 1), Cell(0, 2))],
                  slideToken: token,
                  slideDuration: const Duration(milliseconds: 400),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => token++),
                child: const Text('jouer'),
              ),
            ],
          ),
        ),
      ),
    );

    // Au repos, rien ne vole.
    expect(painterOf(tester).progress, 1);

    await tester.tap(find.text('jouer'));
    await tester.pump();
    expect(painterOf(tester).progress, 0, reason: 'le glissement démarre');

    await tester.pump(const Duration(milliseconds: 200));
    final midway = painterOf(tester).progress;
    expect(midway, greaterThan(0));
    expect(midway, lessThan(1), reason: 'la pièce est entre deux cases');

    await tester.pumpAndSettle();
    expect(painterOf(tester).progress, 1, reason: 'elle est arrivée');
  });

  testWidgets('en mode instantané, aucune animation', (tester) async {
    await Settings.instance.setSlideSpeed(0);

    await tester.pumpWidget(const MaterialApp(home: GameScreen(aiCamp: null)));
    await tester.pump();

    final view = tester.widget<GameBoardView>(find.byType(GameBoardView));
    expect(view.slideDuration, Duration.zero);
  });

  testWidgets('le réglage fixe la durée du glissement', (tester) async {
    await Settings.instance.setSlideSpeed(0.25);

    await tester.pumpWidget(const MaterialApp(home: GameScreen(aiCamp: null)));
    await tester.pump();

    final view = tester.widget<GameBoardView>(find.byType(GameBoardView));
    expect(view.slideDuration, const Duration(milliseconds: 250));
  });
}
