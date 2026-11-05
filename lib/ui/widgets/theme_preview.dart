/// Aperçu d'un thème — portage de `ThemePreview` (main.py).
///
/// Quatre cases du plateau avec, dessus, l'Héritier blanc, l'Héritier noir, le
/// Garde blanc et le Soldat noir : de quoi juger d'un coup d'œil les couleurs
/// et les pièces d'un thème sans l'appliquer.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../theme/themes.dart';
import 'piece_painter.dart';
import 'theme_image_cache.dart';

/// Les quatre pièces montrées, dans l'ordre de Kivy.
const List<Piece> kPreviewPieces = [
  Piece(PieceType.heritier, Camp.blanc),
  Piece(PieceType.heritier, Camp.noir),
  Piece(PieceType.garde, Camp.blanc),
  Piece(PieceType.soldat, Camp.noir),
];

class ThemePreview extends StatelessWidget {
  const ThemePreview({
    super.key,
    required this.theme,
    this.themeDuPlateau,
    this.themeGeneral,
  });

  /// Le thème des PIÈCES. Seul, il vaut pour les trois axes montrés ici.
  final String theme;

  /// L'axe « Plateau » : le damier, sa grille, son image. Nul = [theme].
  final String? themeDuPlateau;

  /// L'axe « Général » : les couleurs 1 et 2 que portent les pièces.
  /// Nul = [theme].
  final String? themeGeneral;

  @override
  Widget build(BuildContext context) {
    final plateau = themeDuPlateau ?? theme;
    // Deux jeux d'images : celui du plateau pour le fond, celui des pièces
    // pour les pièces. Les confondre faisait porter aux pièces le thème du
    // plateau — le même piège que dans l'aperçu des correspondances.
    return ThemeImagesBuilder(
      theme: plateau,
      builder: (context, imagesPlateau) => ThemeImagesBuilder(
        theme: theme,
        builder: (context, images) => CustomPaint(
          size: Size.infinite,
          painter: _PreviewPainter(
            palette: paletteOf(themeGeneral ?? theme),
            paletteDuPlateau: paletteOf(plateau),
            theme: theme,
            images: images,
            // L'IMAGE DU PLATEAU EST PEINTE AVEC LE RESTE, à la place
            // exacte des quatre cases. Posée derrière en `Image.asset`
            // étalée sur toute la boîte, elle débordait du damier dès que
            // la boîte n'était pas quatre fois plus large que haute.
            imageDuPlateau: imagesPlateau?.board,
          ),
        ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  const _PreviewPainter({
    required this.palette,
    required this.paletteDuPlateau,
    required this.theme,
    required this.images,
    required this.imageDuPlateau,
  });

  /// Les couleurs 1 et 2 — l'axe « Général ».
  final ThemePalette palette;

  /// Le damier et sa grille — l'axe « Plateau ».
  final ThemePalette paletteDuPlateau;
  final String theme;
  final LoadedThemeImages? images;

  /// L'image du damier, quand l'axe « Plateau » en a une.
  final ui.Image? imageDuPlateau;

  @override
  void paint(Canvas canvas, Size size) {
    const n = 4;
    final cs = (size.width / n).clamp(0.0, size.height);
    final ox = (size.width - cs * n) / 2;
    final oy = (size.height - cs) / 2;
    final board = Rect.fromLTWH(ox, oy, cs * n, cs);

    final fond = imageDuPlateau;
    if (fond == null) {
      canvas.drawRect(board, Paint()..color = paletteDuPlateau.board);
    } else {
      canvas.drawImageRect(
        fond,
        Rect.fromLTWH(0, 0, fond.width.toDouble(), fond.height.toDouble()),
        board,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }

    // La grille de Kivy.
    final grid = Paint()
      ..color = paletteDuPlateau.grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i <= n; i++) {
      canvas.drawLine(
        Offset(ox + i * cs, oy),
        Offset(ox + i * cs, oy + cs),
        grid,
      );
    }
    canvas.drawLine(Offset(ox, oy), Offset(ox + cs * n, oy), grid);
    canvas.drawLine(Offset(ox, oy + cs), Offset(ox + cs * n, oy + cs), grid);

    for (var i = 0; i < kPreviewPieces.length; i++) {
      paintPiece(
        canvas,
        Rect.fromLTWH(ox + i * cs, oy, cs, cs),
        kPreviewPieces[i],
        palette,
        boardColor: paletteDuPlateau.board,
        images: images,
        theme: theme,
      );
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.theme != theme ||
      old.images != images ||
      old.palette != palette ||
      old.paletteDuPlateau != paletteDuPlateau ||
      old.imageDuPlateau != imageDuPlateau;
}
