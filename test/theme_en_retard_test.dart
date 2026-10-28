/// On change de thème plus vite que ses images ne se décodent.
///
/// Dans le composeur, choisir un plateau puis un autre lance deux
/// chargements, et le second n'est pas forcément le dernier à revenir : c'est
/// celui qui FINIT en dernier qui s'affichait, pas celui qu'on venait de
/// choisir. Nino : « le composeur de thème foire parfois. Par exemple quand
/// je sélectionne un plateau différent. »
///
/// Le piège se reproduit à coup sûr : on met un thème en cache — le changer
/// pour celui-là est alors instantané — et on part d'un thème qui ne l'est
/// pas, dont le chargement reviendra forcément après.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/board_painter.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:lafuga/ui/widgets/theme_image_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.load();
    setScaleSize(const Size(393, 851));
  });

  Future<void> pose(WidgetTester tester, {String? plateau, String? pieces}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 393,
              height: 561,
              child: GameBoardView(
                board: Board.initial(),
                palette: paletteOf('original'),
                flipped: true,
                onTapCell: (_) {},
                boardTheme: plateau,
                pieceTheme: pieces,
              ),
            ),
          ),
        ),
      );

  T peintre<T>(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((c) => c.painter)
      .whereType<T>()
      .first;

  testWidgets('le PLATEAU reste celui qu on vient de choisir', (tester) async {
    // « fleur » est déjà en cache : le changer est instantané. « dragon » ne
    // l'est pas : son chargement reviendra APRÈS, et ne doit rien écraser.
    await tester.runAsync(() => ThemeImageCache.load('fleur'));

    await pose(tester, plateau: 'dragon');
    await pose(tester, plateau: 'fleur');
    await tester.runAsync(() => ThemeImageCache.load('dragon'));
    await tester.pumpAndSettle();

    expect(
      identical(
        peintre<BoardBackgroundPainter>(tester).images,
        ThemeImageCache.ready('fleur'),
      ),
      isTrue,
      reason: 'le plateau affiché n est pas celui qu on vient de choisir',
    );
  });

  testWidgets('les PIÈCES aussi', (tester) async {
    // Le même piège, sur l'autre axe : les deux chargements sont séparés.
    await tester.runAsync(() => ThemeImageCache.load('fleur'));

    await pose(tester, pieces: 'medieval');
    await pose(tester, pieces: 'fleur');
    await tester.runAsync(() => ThemeImageCache.load('medieval'));
    await tester.pumpAndSettle();

    expect(
      identical(
        peintre<BoardPiecesPainter>(tester).images,
        ThemeImageCache.ready('fleur'),
      ),
      isTrue,
      reason: 'les pièces affichées ne sont pas celles qu on vient de choisir',
    );
  });
}
