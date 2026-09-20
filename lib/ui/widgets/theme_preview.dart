/// Aperçu d'un thème — portage de `ThemePreview` (main.py).
///
/// Quatre cases du plateau avec, dessus, l'Héritier blanc, l'Héritier noir, le
/// Garde blanc et le Soldat noir : de quoi juger d'un coup d'œil les couleurs
/// et les pièces d'un thème sans l'appliquer.
library;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../theme/theme_assets.dart';
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
  const ThemePreview({super.key, required this.theme});

  final String theme;

  @override
  Widget build(BuildContext context) => ThemeImagesBuilder(
    theme: theme,
    builder: (context, images) {
      final board = imagesFor(theme)?.board;
      return Stack(
        fit: StackFit.expand,
        children: [
          if (board != null) Image.asset(board, fit: BoxFit.cover),
          CustomPaint(
            painter: _PreviewPainter(
              palette: paletteOf(theme),
              theme: theme,
              images: images,
              drawBoard: board == null,
            ),
          ),
        ],
      );
    },
  );
}

class _PreviewPainter extends CustomPainter {
  const _PreviewPainter({
    required this.palette,
    required this.theme,
    required this.images,
    required this.drawBoard,
  });

  final ThemePalette palette;
  final String theme;
  final LoadedThemeImages? images;
  final bool drawBoard;

  @override
  void paint(Canvas canvas, Size size) {
    const n = 4;
    final cs = (size.width / n).clamp(0.0, size.height);
    final ox = (size.width - cs * n) / 2;
    final oy = (size.height - cs) / 2;
    final board = Rect.fromLTWH(ox, oy, cs * n, cs);

    if (drawBoard) {
      canvas.drawRect(board, Paint()..color = palette.board);
    }

    // La grille de Kivy.
    final grid = Paint()
      ..color = palette.grid
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
        boardColor: palette.board,
        images: images,
        theme: theme,
      );
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.theme != theme || old.images != images;
}
