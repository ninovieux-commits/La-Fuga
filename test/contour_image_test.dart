/// Les pièces des thèmes à IMAGES ont, elles aussi, leur contour net.
///
/// Nino : « un trait noir qui fait parfaitement le tour des images comme on a
/// fait avec les symboles des touches ingame. » Ces images sont des
/// silhouettes sur fond transparent — le décor du plateau transparaît autour
/// —, et c'est cette silhouette qu'on trace, pas la case.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/board_geometry.dart';
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
  tearDown(resetScale);

  testWidgets('une pièce choisie se cerne de noir', (tester) async {
    const theme = 'fleur';
    tester.view.physicalSize = const Size(393, 561);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Les images se décodent en tâche de fond : on les attend, sinon le
    // plateau montre son rendu géométrique de secours et le test ne mesure
    // pas ce qu'il croit.
    await tester.runAsync(() => ThemeImageCache.load(theme));

    final cle = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: cle,
            child: SizedBox(
              width: 393,
              height: 561,
              child: GameBoardView(
                board: Board.initial(),
                palette: paletteOf(theme),
                flipped: true,
                onTapCell: (_) {},
                selected: const Cell(2, 0),
                pieceTheme: theme,
                boardTheme: theme,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    late ByteData pixels;
    late ui.Image rendu;
    await tester.runAsync(() async {
      final boundary =
          cle.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      rendu = await boundary.toImage();
      pixels = (await rendu.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    });

    final g = BoardGeometry(
      size: const Size(393, 561),
      flipped: true,
      rall: Board.initial().rall,
    );

    /// Combien de pixels franchement NOIRS dans cette case.
    int noirs(Cell cell) {
      final r = g.cellRect(cell.col, cell.row);
      var compte = 0;
      for (var y = r.top.round() + 1; y < r.bottom.round() - 1; y++) {
        for (var x = r.left.round() + 1; x < r.right.round() - 1; x++) {
          final i = (y * rendu.width + x) * 4;
          if (i + 3 >= pixels.lengthInBytes) continue;
          if (pixels.getUint8(i) < 40 &&
              pixels.getUint8(i + 1) < 40 &&
              pixels.getUint8(i + 2) < 40 &&
              pixels.getUint8(i + 3) > 200) {
            compte++;
          }
        }
      }
      return compte;
    }

    final choisie = noirs(const Cell(2, 0));
    final voisine = noirs(const Cell(3, 0));
    expect(
      choisie,
      greaterThan(voisine * 3),
      reason:
          'la pièce choisie n est pas cernée : $choisie pixels noirs contre '
          '$voisine chez sa voisine intacte',
    );
  });
}
