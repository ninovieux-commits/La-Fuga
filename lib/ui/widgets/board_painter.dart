/// Rendu du plateau — portage de `BoardWidget._redraw` (main.py).
///
/// Le dessin est séparé en deux peintres pour que l'animation d'une pièce ne
/// force pas la reconstruction du décor : [BoardBackgroundPainter] ne change
/// qu'au changement de thème ou de taille, [BoardPiecesPainter] à chaque coup.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../../engine/board.dart';
import '../../engine/piece.dart';
import '../../game/last_move.dart';
import '../../theme/themes.dart';
import 'board_geometry.dart';
import 'logo_painter.dart';
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
          ..strokeWidth = kivyLine(2),
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
      ..strokeWidth = kivyLine(1);
    for (var c = 0; c < kCols; c++) {
      for (var r = 0; r < kRows; r++) {
        canvas.drawRect(g.cellRect(c, r), gridPaint);
      }
    }

    // Rosace au centre du plateau, en contours seuls : elle passe sous les
    // pièces sans gêner la lecture de la position.
    paintLogoOutline(
      canvas,
      boardRect.center.dx,
      boardRect.center.dy,
      g.cellSize * 0.42,
      color: palette.grid,
      strokeWidth: kivyLine(1.6),
    );

    _paintAnnotations(canvas, g);
  }

  /// Chiffres 1 à 8 dans la colonne la plus à gauche, et notes do…si sous le
  /// plateau — portage de `_draw_annotations`.
  void _paintAnnotations(Canvas canvas, BoardGeometry g) {
    final cs = g.cellSize;
    // La colonne qui se trouve visuellement à gauche change avec
    // l'orientation : côté Noir, le plateau est tourné à 180°.
    final leftCol = g.flipped ? 0 : kCols - 1;

    for (var r = 0; r < kRows; r++) {
      final cell = g.cellRect(leftCol, r);
      _text(
        canvas,
        '${r + 1}',
        Offset(cell.left + cs * 0.08, cell.bottom - cs * 0.04),
        fontSize: math.max(10, cs * 0.20),
        color: const Color(0xFF000000),
        anchor: _Anchor.bottomLeft,
      );
    }

    // Les notes sont sous le plateau, chacune sous SA colonne.
    final noteY = g.rowToY(g.flipped ? -1 : 8) + cs * 0.20;
    for (var c = 0; c < kCols; c++) {
      _text(
        canvas,
        kBoardNotes[c],
        Offset(g.cellRect(c, 0).center.dx, noteY),
        fontSize: math.max(11, cs * 0.26),
        color: const Color(0xFFFFFFFF),
        anchor: _Anchor.center,
      );
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    required double fontSize,
    required Color color,
    required _Anchor anchor,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final offset = switch (anchor) {
      _Anchor.bottomLeft => Offset(at.dx, at.dy - painter.height),
      _Anchor.center => Offset(
        at.dx - painter.width / 2,
        at.dy - painter.height / 2,
      ),
    };
    painter.paint(canvas, offset);
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
    this.lastMove,
    this.images,
    this.theme,
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

  /// Dernier coup joué, à mettre en évidence.
  final LastMove? lastMove;

  /// Thème des pièces : deepgrey et arc-en-ciel ont leur propre rendu.
  final String? theme;

  /// Images du thème, quand il en a.
  final LoadedThemeImages? images;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;

    // Dernier coup, sous les pièces : cadres vers l'extérieur, et petits
    // carrés sur les rebonds d'un multisaut. La couleur est l'inverse du camp
    // qui a joué, pour rester lisible sur toutes les pièces.
    final last = lastMove;
    if (last != null && !last.isEmpty) {
      final color = last.camp == Camp.blanc
          ? const Color(0xFF000000)
          : const Color(0xFFFFFFFF);
      final frame = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = kivyLine(2.4);
      for (final cell in last.framedCells) {
        if (!cell.onBoard) continue;
        canvas.drawRect(g.cellRect(cell.col, cell.row).inflate(1), frame);
      }
      final dot = Paint()..color = color;
      for (final cell in last.jumpPath) {
        if (!cell.onBoard) continue;
        final d = g.cellSize * 0.16;
        canvas.drawRect(
          Rect.fromCenter(
            center: g.cellCenter(cell.col, cell.row),
            width: d,
            height: d,
          ),
          dot,
        );
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
          // Les points de poussée grossis, sur la pièce qui vient de pousser.
          pushHighlightDirs: {...?lastMove?.pushDirs[cell]},
          flipped: g.flipped,
          boardColor: palette.board,
          images: images,
          theme: theme,
          rainbowFraction: rainbowFractionOf(c, r),
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
      old.theme != theme ||
      old.lastMove != lastMove;
}

/// Notes telles qu'elles s'écrivent SOUS le plateau : en minuscules. La
/// notation `.nmc`, elle, les capitalise.
const List<String> kBoardNotes = ['do', 'ré', 'mi', 'fa', 'sol', 'la', 'si'];

/// Où ancrer un texte dessiné sur le plateau.
enum _Anchor { bottomLeft, center }
