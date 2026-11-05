/// L'axe « Plateau » du composeur change VRAIMENT le plateau.
///
/// Nino : « le composeur de thème a des défauts. Par exemple, le plateau ne
/// se met pas bien à jour. »
///
/// L'axe ne choisissait que l'IMAGE de fond. Cinq thèmes sur dix-sept en ont
/// une ; pour les douze autres, le prendre comme plateau ne changeait rien
/// du tout, puisque la couleur du damier et celle de la grille venaient de
/// l'axe « Général ». Le composeur montrait pourtant la couleur du thème
/// dans sa vignette, et promettait un changement qui n'arrivait jamais.
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
import 'package:shared_preferences/shared_preferences.dart';

const Key _cadre = Key('cadre');
const Size _ecran = Size(393, 561);

/// La couleur peinte au centre d'une case VIDE du damier.
Future<Color> _couleurDuDamier(
  WidgetTester tester, {
  required String general,
  required String plateau,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(
          key: _cadre,
          child: SizedBox(
            width: _ecran.width,
            height: _ecran.height,
            child: GameBoardView(
              board: Board.initial(),
              palette: paletteOf(general),
              flipped: true,
              onTapCell: (_) {},
              pieceTheme: 'original',
              boardTheme: plateau,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  late ByteData pixels;
  late int largeur;
  await tester.runAsync(() async {
    final limite =
        tester.renderObject(find.byKey(_cadre)) as RenderRepaintBoundary;
    final rendu = await limite.toImage();
    largeur = rendu.width;
    pixels = (await rendu.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });

  // Une case du milieu : vide à la position de départ, et loin de la grille.
  final g = BoardGeometry(
    size: _ecran,
    flipped: true,
    rall: Board.initial().rall,
  );
  final centre = g.cellRect(1, 4).center;
  final i = (centre.dy.round() * largeur + centre.dx.round()) * 4;
  return Color.fromARGB(
    255,
    pixels.getUint8(i),
    pixels.getUint8(i + 1),
    pixels.getUint8(i + 2),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.load();
    setScaleSize(const Size(393, 851));
  });
  tearDown(resetScale);

  testWidgets('le damier prend la couleur de l axe Plateau', (tester) async {
    tester.view.physicalSize = _ecran;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Forêt n'a AUCUNE image de plateau : c'est le cas qui ne changeait
    // rien. Sa couleur de damier diffère pourtant de celle d'Original.
    expect(paletteOf('foret').board, isNot(paletteOf('original').board));

    final original = await _couleurDuDamier(
      tester,
      general: 'original',
      plateau: 'original',
    );
    final foret = await _couleurDuDamier(
      tester,
      general: 'original',
      plateau: 'foret',
    );

    expect(original, paletteOf('original').board);
    expect(
      foret,
      paletteOf('foret').board,
      reason: 'changer d axe Plateau doit repeindre le damier',
    );
  });

  testWidgets('les zones de ralliement restent à l axe Général', (
    tester,
  ) async {
    // Elles disent les CAMPS, pas le décor : elles gardent les couleurs 1
    // et 2 du joueur quel que soit le plateau choisi.
    tester.view.physicalSize = _ecran;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: _cadre,
            child: SizedBox(
              width: _ecran.width,
              height: _ecran.height,
              child: GameBoardView(
                board: Board.initial(),
                palette: paletteOf('original'),
                flipped: true,
                onTapCell: (_) {},
                pieceTheme: 'original',
                boardTheme: 'foret',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    late ByteData pixels;
    late int largeur;
    await tester.runAsync(() async {
      final limite =
          tester.renderObject(find.byKey(_cadre)) as RenderRepaintBoundary;
      final rendu = await limite.toImage();
      largeur = rendu.width;
      pixels = (await rendu.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    });

    final g = BoardGeometry(
      size: _ecran,
      flipped: true,
      rall: Board.initial().rall,
    );
    final zones = g.rallyRects(8);
    expect(zones, isNotEmpty);
    final p = zones.first.center;
    final i = (p.dy.round() * largeur + p.dx.round()) * 4;
    final vu = Color.fromARGB(
      255,
      pixels.getUint8(i),
      pixels.getUint8(i + 1),
      pixels.getUint8(i + 2),
    );
    expect(vu, paletteOf('original').clair);
  });
}
