/// Rendu du plateau — portage de `BoardWidget._redraw` (main.py).
///
/// Le dessin est séparé en deux peintres pour que l'animation d'une pièce ne
/// force pas la reconstruction du décor : [BoardBackgroundPainter] ne change
/// qu'au changement de thème ou de taille, [BoardPiecesPainter] à chaque coup.
library;

import 'package:flutter/rendering.dart';

import '../../engine/board.dart';
import '../../theme/themes.dart';
import 'board_geometry.dart';
import 'piece_painter.dart';
import 'theme_image_cache.dart';

/// Décor : zones de ralliement, fond du plateau, grille. Statique.
final class BoardBackgroundPainter extends CustomPainter {
  const BoardBackgroundPainter({
    required this.geometry,
    required this.palette,
    this.images,
  });

  final BoardGeometry geometry;
  final ThemePalette palette;

  /// Images du thème, quand il en a.
  final LoadedThemeImages? images;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    final radius = Radius.circular(g.cellSize * 0.22);

    // Zones de ralliement : chaque camp a la sienne, à sa couleur d'accent.
    // Arrondies vers l'extérieur, droites du côté du plateau.
    for (final row in [8, -1]) {
      final rect = g.rallyRect(row);
      final isTop = g.rowToIndex(row) == 0;
      final rrect = RRect.fromRectAndCorners(
        rect,
        topLeft: isTop ? radius : Radius.zero,
        topRight: isTop ? radius : Radius.zero,
        bottomLeft: isTop ? Radius.zero : radius,
        bottomRight: isTop ? Radius.zero : radius,
      );
      canvas.drawRRect(
        rrect,
        Paint()..color = row == 8 ? palette.clair : palette.fonce,
      );
      // Contour foncé : le débordement dans les cadres info doit paraître net.
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = const Color(0xFF1A1A1A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Plateau.
    final boardRect = Rect.fromLTWH(
      g.colToX(0) < g.colToX(6) ? g.colToX(0) : g.colToX(6),
      g.rowToY(g.indexToRow(1)),
      g.cellSize * kCols,
      g.cellSize * kRows,
    );
    final boardImage = images?.board;
    if (boardImage != null) {
      canvas.drawImageRect(
        boardImage,
        Rect.fromLTWH(
          0,
          0,
          boardImage.width.toDouble(),
          boardImage.height.toDouble(),
        ),
        boardRect,
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else {
      canvas.drawRect(boardRect, Paint()..color = palette.board);
    }

    final gridPaint = Paint()
      ..color = palette.grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var c = 0; c < kCols; c++) {
      for (var r = 0; r < kRows; r++) {
        canvas.drawRect(g.cellRect(c, r), gridPaint);
      }
    }
  }

  @override
  bool shouldRepaint(BoardBackgroundPainter old) =>
      old.palette != palette ||
      old.images != images ||
      old.geometry.cellSize != geometry.cellSize ||
      old.geometry.flipped != geometry.flipped;
}

/// Pièces, sélection et mise en évidence du dernier coup.
final class BoardPiecesPainter extends CustomPainter {
  const BoardPiecesPainter({
    required this.geometry,
    required this.palette,
    required this.board,
    this.selected,
    this.groupSelection = const {},
    this.destinations = const {},
    this.lastMoveCells = const {},
    this.images,
  });

  final BoardGeometry geometry;
  final ThemePalette palette;
  final Board board;

  /// Pièce actuellement sélectionnée.
  final Cell? selected;

  /// Autres pièces du groupe sélectionné (manœuvre).
  final Set<Cell> groupSelection;

  /// Cases d'arrivée légales, à pointer.
  final Set<Cell> destinations;

  /// Cases touchées par le dernier coup joué.
  final Set<Cell> lastMoveCells;

  /// Images du thème, quand il en a.
  final LoadedThemeImages? images;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;

    // Cadres du dernier coup, sous les pièces.
    if (lastMoveCells.isNotEmpty) {
      final paint = Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4;
      for (final cell in lastMoveCells) {
        if (!cell.onBoard) continue;
        canvas.drawRect(g.cellRect(cell.col, cell.row).inflate(1), paint);
      }
    }

    // Pastilles des destinations légales.
    if (destinations.isNotEmpty) {
      final paint = Paint()..color = const Color(0x99FFFF00);
      for (final cell in destinations) {
        canvas.drawCircle(
          g.cellCenter(cell.col, cell.row),
          g.cellSize * 0.16,
          paint,
        );
      }
    }

    // Pièces.
    for (var c = 0; c < kCols; c++) {
      for (var r = 0; r < kRows; r++) {
        final p = board.at(c, r);
        if (p == null) continue;
        final cell = Cell(c, r);

        Color? outline;
        var width = 2.0;
        if (cell == selected) {
          outline = FugaColors.selection;
          width = 4;
        } else if (groupSelection.contains(cell)) {
          outline = FugaColors.groupSelection;
          width = 4;
        } else if (board.isImmobilised(c, r)) {
          // Même condition que la règle : une pièce au contour rouge ne peut
          // pas bouger.
          outline = FugaColors.immobile;
          width = 3;
        }

        paintPiece(
          canvas,
          g.cellRect(c, r),
          p,
          palette,
          outline: outline,
          outlineWidth: width,
          flipped: g.flipped,
          boardColor: palette.board,
          images: images,
        );
      }
    }
  }

  @override
  bool shouldRepaint(BoardPiecesPainter old) =>
      old.board.key != board.key ||
      old.images != images ||
      old.selected != selected ||
      old.palette != palette ||
      old.geometry.flipped != geometry.flipped ||
      old.destinations.length != destinations.length ||
      old.lastMoveCells.length != lastMoveCells.length;
}
