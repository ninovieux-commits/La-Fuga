/// La pièce choisie s'ENFONCE, et la meneuse porte son chevron.
///
/// Nino : « la couleur de sélection ne me convient pas, c'est pas clair. Et
/// pourquoi on mettrait pas plutôt la pièce en "enfoncée" ? Je veux dire,
/// comme les boutons quand ils ne peuvent pas être utilisés. Quand on en
/// sélectionne plusieurs, ce symbole apparaît sur la meneuse. »
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/board_geometry.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:lafuga/ui/widgets/picto_touche.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.load();
    setScaleSize(const Size(393, 851));
  });
  tearDown(resetScale);

  Future<void> pose(
    WidgetTester tester, {
    Cell? choisie,
    Set<Cell> groupe = const {},
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 393,
            height: 561,
            child: GameBoardView(
              board: Board.initial(),
              palette: paletteOf(kDefaultTheme),
              flipped: true,
              onTapCell: (_) {},
              selected: choisie,
              groupSelection: groupe,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final chevron = find.byWidgetPredicate(
    (w) => w is PictoTouche && w.asset.endsWith('meneuse.webp'),
  );

  testWidgets('une pièce seule ne mène personne', (tester) async {
    await pose(tester, choisie: const Cell(2, 1));
    expect(chevron, findsNothing);
  });

  testWidgets('rien de choisi, rien de marqué', (tester) async {
    await pose(tester);
    expect(chevron, findsNothing);
  });

  testWidgets('en manœuvre, la meneuse porte le chevron', (tester) async {
    await pose(
      tester,
      choisie: const Cell(2, 1),
      groupe: {const Cell(3, 1), const Cell(4, 1)},
    );
    expect(chevron, findsOneWidget);

    // Sur la MENEUSE, et pas sur une suiveuse : il occupe exactement la
    // case choisie.
    final g = BoardGeometry(
      size: const Size(393, 561),
      flipped: true,
      rall: Board.initial().rall,
    );
    final attendue = g.cellRect(2, 1);
    final posee = tester.getRect(chevron);
    expect(posee.center.dx, moreOrLessEquals(attendue.center.dx, epsilon: 1));
    expect(posee.center.dy, moreOrLessEquals(attendue.center.dy, epsilon: 1));
  });
}
