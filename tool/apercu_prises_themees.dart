/// Aperçu : les pièces MANGÉES portent le dessin du plateau, tous thèmes.
///
/// Ce fichier ne sert qu'à dessiner : il ne fait pas partie de l'application.
/// `flutter test tool/apercu_prises_themees.dart` écrit un PNG dans
/// `tool/apercus/`.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/bandeau_prises.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:lafuga/ui/widgets/theme_image_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Key _cadre = Key('cadre');

/// Les quatre thèmes qui se dessinent le plus différemment.
const List<String> _themes = ['medieval', 'fleur', 'arcenciel', 'deepgrey'];

/// Ce qui a été pris de chaque côté.
const List<Piece> _prisesHaut = [
  Piece.noirSoldat,
  Piece.noirGarde,
  Piece.noirChevalier,
  Piece.noirNurse,
];
const List<Piece> _prisesBas = [
  Piece.blancSoldat,
  Piece.blancChevalier,
  Piece.blancGarde,
];

Widget _colonne(String theme) => SizedBox(
  width: 340,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          kThemeLabels[theme] ?? theme,
          style: const TextStyle(
            fontFamily: 'NotoSansCJK',
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      // LES PRISES, puis le plateau juste dessous : d'un coup d'œil, la
      // même pièce doit avoir le même dessin aux deux endroits.
      BandeauPrises(
        prisesHaut: _prisesHaut,
        prisesBas: _prisesBas,
        palette: paletteOf(theme),
        hautEstBlanc: false,
        theme: theme,
      ),
      SizedBox(
        width: 340,
        height: 340 * kExtRows / kCols,
        child: GameBoardView(
          board: Board.initial(),
          palette: paletteOf(theme),
          flipped: true,
          onTapCell: (_) {},
          pieceTheme: theme,
          boardTheme: theme,
        ),
      ),
    ],
  ),
);

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('aperçu des prises thémées', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await Settings.load();
    await Translations.load('fr');
    resetScale();
    setScaleSize(const Size(393, 851));
    tester.view.physicalSize = const Size(720, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      for (final (famille, chemin) in [
        ('NotoSansCJK', 'assets/fonts/NotoSansCJKsc-Regular.otf'),
        (
          'Roboto',
          '/opt/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
        ),
      ]) {
        final police = FontLoader(famille)
          ..addFont(
            File(chemin).readAsBytes().then((o) => ByteData.view(o.buffer)),
          );
        await police.load();
      }
      // Les images des thèmes se décodent hors frame : sans cette attente,
      // les plateaux ET les prises sortent en rendu géométrique.
      for (final t in _themes) {
        await ThemeImageCache.load(t);
      }
    });

    await tester.pumpWidget(
      RepaintBoundary(
        key: _cadre,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'NotoSansCJK'),
          home: ColoredBox(
            color: const Color(0xFF1A1A1A),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [_colonne(_themes[0]), _colonne(_themes[1])],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [_colonne(_themes[2]), _colonne(_themes[3])],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Directory('tool/apercus').createSync(recursive: true);
    final limite =
        tester.renderObject(find.byKey(_cadre)) as RenderRepaintBoundary;
    final octets = await tester.runAsync(() async {
      final image = await limite.toImage(pixelRatio: 2);
      return image.toByteData(format: ui.ImageByteFormat.png);
    });
    File(
      'tool/apercus/prises_themees.png',
    ).writeAsBytesSync(Uint8List.view(octets!.buffer));
  });
}
