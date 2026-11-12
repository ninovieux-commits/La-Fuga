/// La couleur d'une pièce vient de l'axe « Pièces ».
///
/// Nino : « les pièces affichées dans l'aperçu sont en fonction de la
/// couleur générale au lieu de pièces ». Les écrans ne connaissent qu'une
/// palette — la générale — et la passaient à [paintPiece] pour tout le
/// monde : sur un thème sans images, choisir un thème de pièces ne changeait
/// alors rien du tout. C'est [paintPiece] qui tranche désormais, là où le
/// nom du thème des pièces lui est déjà donné.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/widgets/piece_painter.dart';

const Key _cadre = Key('cadre');

class _UnePiece extends CustomPainter {
  const _UnePiece(this.piece, this.palette, this.theme);

  final Piece piece;
  final ThemePalette palette;
  final String? theme;

  @override
  void paint(Canvas canvas, Size size) =>
      paintPiece(canvas, Offset.zero & size, piece, palette, theme: theme);

  @override
  bool shouldRepaint(_UnePiece old) => true;
}

/// Toutes les couleurs d'une pièce peinte, avec le nombre de pixels de
/// chacune.
Future<Map<Color, int>> _couleurs(
  WidgetTester tester,
  Piece piece, {
  required ThemePalette palette,
  String? theme,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: _cadre,
          child: SizedBox(
            width: 60,
            height: 60,
            child: CustomPaint(painter: _UnePiece(piece, palette, theme)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final compte = <Color, int>{};
  await tester.runAsync(() async {
    final limite =
        tester.renderObject(find.byKey(_cadre)) as RenderRepaintBoundary;
    final rendu = await limite.toImage();
    final pixels = (await rendu.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    for (var i = 0; i < pixels.lengthInBytes; i += 4) {
      final c = Color.fromARGB(
        255,
        pixels.getUint8(i),
        pixels.getUint8(i + 1),
        pixels.getUint8(i + 2),
      );
      compte[c] = (compte[c] ?? 0) + 1;
    }
  });
  return compte;
}

void main() {
  const blanche = Piece(PieceType.heritier, Camp.blanc);
  const noire = Piece(PieceType.heritier, Camp.noir);

  testWidgets('le thème des pièces l emporte sur la palette reçue', (
    tester,
  ) async {
    // Ce que les écrans font : la palette générale, et le thème des pièces.
    final vu = await _couleurs(
      tester,
      blanche,
      palette: paletteOf('foret'),
      theme: 'hemo',
    );

    expect(
      vu[paletteOf('hemo').clair] ?? 0,
      greaterThan(0),
      reason: 'le signe doit être au clair de hémo',
    );
    expect(
      vu[paletteOf('foret').clair] ?? 0,
      0,
      reason: 'rien ne doit rester du thème général',
    );
  });

  testWidgets('sans thème, la palette reçue fait foi', (tester) async {
    final vu = await _couleurs(tester, blanche, palette: paletteOf('foret'));
    expect(vu[paletteOf('foret').clair] ?? 0, greaterThan(0));
  });

  // Nino : « les puces [pièces] noires du thème étoiles doivent être bleues
  // foncé. »
  testWidgets('les pièces noires du thème étoile ont un corps bleu nuit', (
    tester,
  ) async {
    final vu = await _couleurs(
      tester,
      noire,
      palette: paletteOf('etoile'),
      theme: 'etoile',
    );

    expect(
      vu[kBleuDEtoile] ?? 0,
      greaterThan(0),
      reason: 'le corps est bleu nuit',
    );
    expect(
      vu[FugaColors.blackPiece] ?? 0,
      0,
      reason: 'et plus noir : il se fondait dans son plateau',
    );
    // Le jaune vif, lui, est passé du côté des noires.
    expect(vu[const Color.fromRGBO(255, 217, 51, 1)] ?? 0, greaterThan(0));
  });

  testWidgets('et les blanches du thème étoile gardent le jaune sourd', (
    tester,
  ) async {
    final vu = await _couleurs(
      tester,
      blanche,
      palette: paletteOf('etoile'),
      theme: 'etoile',
    );
    expect(vu[FugaColors.whitePiece] ?? 0, greaterThan(0));
    expect(vu[const Color.fromRGBO(191, 153, 20, 1)] ?? 0, greaterThan(0));
  });
}
