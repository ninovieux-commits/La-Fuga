/// L'aperçu d'un thème tient dans ses quatre cases.
///
/// Il montre quatre cases du damier avec une pièce sur chacune. L'image du
/// plateau était posée DERRIÈRE, étalée sur toute la boîte : dès que la
/// boîte n'était pas quatre fois plus large que haute — le composeur lui
/// donne toute la largeur de l'écran —, le décor débordait des cases et
/// l'aperçu ne ressemblait plus à un plateau.
///
/// Il sert aussi aux trois axes du composeur : les pièces, le plateau et les
/// couleurs peuvent venir de trois thèmes différents.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/theme_image_cache.dart';
import 'package:lafuga/ui/widgets/theme_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Key _cadre = Key('cadre');

/// Le fond derrière l'aperçu : une couleur qu'aucun thème n'emploie.
const Color _fond = Color(0xFFFF00FF);

Future<({ByteData pixels, int largeur, int hauteur})> _rend(
  WidgetTester tester,
  Widget apercu, {
  required Size boite,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: _cadre,
            child: ColoredBox(
              color: _fond,
              child: SizedBox(
                width: boite.width,
                height: boite.height,
                child: apercu,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  late ByteData pixels;
  late int largeur;
  late int hauteur;
  await tester.runAsync(() async {
    final limite =
        tester.renderObject(find.byKey(_cadre)) as RenderRepaintBoundary;
    final rendu = await limite.toImage();
    largeur = rendu.width;
    hauteur = rendu.height;
    pixels = (await rendu.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });
  return (pixels: pixels, largeur: largeur, hauteur: hauteur);
}

Color _au(({ByteData pixels, int largeur, int hauteur}) r, int x, int y) {
  final i = (y * r.largeur + x) * 4;
  return Color.fromARGB(
    255,
    r.pixels.getUint8(i),
    r.pixels.getUint8(i + 1),
    r.pixels.getUint8(i + 2),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.load();
    setScaleSize(const Size(393, 851));
  });
  tearDown(() {
    resetScale();
    ThemeImageCache.clear();
  });

  testWidgets('le décor du plateau ne déborde pas des quatre cases', (
    tester,
  ) async {
    // Fleur a une image de plateau : c'est elle qui débordait.
    await tester.runAsync(() => ThemeImageCache.load('fleur'));

    // Deux fois plus large que haute : les cases font un quart de la
    // largeur, donc la moitié de la hauteur. Il doit rester du fond
    // au-dessus et au-dessous.
    final r = await _rend(
      tester,
      const ThemePreview(theme: 'fleur'),
      boite: const Size(200, 100),
    );

    expect(_au(r, 100, 3), _fond, reason: 'au-dessus des cases');
    expect(_au(r, 100, 96), _fond, reason: 'au-dessous des cases');
    expect(
      _au(r, 4, 50),
      isNot(_fond),
      reason: 'la bande des cases, elle, est peinte',
    );
  });

  testWidgets('les trois axes se composent', (tester) async {
    // Le damier vient de l'axe « Plateau », pas de celui des pièces.
    await tester.runAsync(() async {
      await ThemeImageCache.load('original');
      await ThemeImageCache.load('foret');
    });

    final r = await _rend(
      tester,
      const ThemePreview(
        theme: 'original',
        themeDuPlateau: 'foret',
        themeGeneral: 'original',
      ),
      boite: const Size(200, 50),
    );

    // Un coin de case, loin d'une pièce et de la grille : le damier nu.
    expect(_au(r, 3, 46), paletteOf('foret').board);
  });
}
