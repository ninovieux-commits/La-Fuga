/// Annotations du tuto dessinées par-dessus le plateau — portage du bloc
/// `tuto_annotations` de `BoardWidget._redraw` (main.py).
///
/// Encadrés de couleur, flèches, liens entre pièces, Héritiers ayant fugué, et
/// faux éléments d'interface des étapes qui illustrent une fin de partie.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../engine/board.dart';
import '../../engine/piece.dart';
import '../../game/tuto.dart';
import '../../theme/themes.dart';
import 'board_geometry.dart';
import 'piece_painter.dart';

/// Les couleurs des encadrés, reprises de Kivy.
const Color kTutoFramed = Color(0xFFD93A3A);
const Color kTutoFramedOk = Color(0xFF2EB84D);
const Color kTutoFramedBlue = Color(0xFF2E74D9);
const Color kTutoFramedSelected = Color(0xFFF2B01E);

class TutoOverlayPainter extends CustomPainter {
  const TutoOverlayPainter({
    required this.annotations,
    required this.fugued,
    required this.mockUi,
    required this.palette,
    this.flipped = true,
  });

  final TutoAnnotations annotations;
  final List<({Cell cell, Camp camp})> fugued;
  final List<TutoMockElement> mockUi;
  final ThemePalette palette;
  final bool flipped;

  @override
  void paint(Canvas canvas, Size size) {
    final g = BoardGeometry(size: size, flipped: flipped);

    for (final h in fugued) {
      paintPiece(
        canvas,
        g.cellRect(h.cell.col, h.cell.row),
        Piece(PieceType.heritier, h.camp),
        palette,
      );
    }

    for (final link in annotations.links) {
      _links(canvas, g, link);
    }
    _frames(canvas, g, annotations.framed, kTutoFramed);
    _frames(canvas, g, annotations.framedOk, kTutoFramedOk);
    _frames(canvas, g, annotations.framedBlue, kTutoFramedBlue);
    _frames(canvas, g, annotations.framedSelected, kTutoFramedSelected);

    for (final (from, to) in annotations.arrows) {
      _arrow(canvas, g, from, to);
    }

    for (final el in mockUi) {
      _mock(canvas, size, el);
    }
  }

  void _frames(Canvas canvas, BoardGeometry g, List<Cell> cells, Color color) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, g.cellSize * 0.06)
      ..color = color;
    for (final c in cells) {
      canvas.drawRect(
        g.cellRect(c.col, c.row).deflate(paint.strokeWidth),
        paint,
      );
    }
  }

  /// Trait reliant deux pièces : montre qu'elles se touchent.
  void _links(Canvas canvas, BoardGeometry g, TutoLink link) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, g.cellSize * 0.05)
      ..strokeCap = StrokeCap.round
      ..color = _color(link.color);
    for (final (a, b) in link.pairs) {
      canvas.drawLine(
        g.cellCenter(a.col, a.row),
        g.cellCenter(b.col, b.row),
        paint,
      );
    }
  }

  /// Flèche d'un centre de case à l'autre, pointe comprise.
  void _arrow(Canvas canvas, BoardGeometry g, Cell from, Cell to) {
    final start = g.cellCenter(from.col, from.row);
    final end = g.cellCenter(to.col, to.row);
    final width = math.max(2.5, g.cellSize * 0.07);
    final paint = Paint()
      ..color = kTutoFramedSelected
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    final head = g.cellSize * 0.24;
    // On arrête le trait avant la pointe, sinon il dépasse.
    final tipBase = Offset(
      end.dx - head * 0.8 * math.cos(angle),
      end.dy - head * 0.8 * math.sin(angle),
    );
    canvas.drawLine(start, tipBase, paint);

    const spread = 0.42;
    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - head * math.cos(angle - spread),
        end.dy - head * math.sin(angle - spread),
      )
      ..lineTo(
        end.dx - head * math.cos(angle + spread),
        end.dy - head * math.sin(angle + spread),
      )
      ..close();
    canvas.drawPath(path, Paint()..color = kTutoFramedSelected);
  }

  /// Faux bouton ou chrono, posé en fraction de la zone du plateau.
  void _mock(Canvas canvas, Size size, TutoMockElement el) {
    final w = el.fw * size.width;
    final h = el.fh * size.height;
    // Les fractions de Kivy partent du BAS de l'écran.
    final rect = Rect.fromCenter(
      center: Offset(el.fx * size.width, (1 - el.fy) * size.height),
      width: w,
      height: h,
    );
    final radius = Radius.circular(h * 0.35);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..color = _color(el.color),
    );
    if (el.circled) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(h * 0.18), radius),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, h * 0.12)
          ..color = kTutoFramed,
      );
    }

    final painter = TextPainter(
      text: TextSpan(
        text: el.text,
        style: TextStyle(
          color: Colors.white,
          fontSize: h * 0.52,
          fontWeight: FontWeight.bold,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: w);
    painter.paint(
      canvas,
      Offset(
        rect.center.dx - painter.width / 2,
        rect.center.dy - painter.height / 2,
      ),
    );
  }

  Color _color((double, double, double) c) => Color.fromRGBO(
    (c.$1 * 255).round(),
    (c.$2 * 255).round(),
    (c.$3 * 255).round(),
    1,
  );

  @override
  bool shouldRepaint(TutoOverlayPainter old) =>
      old.annotations != annotations ||
      old.fugued != fugued ||
      old.mockUi != mockUi ||
      old.palette != palette ||
      old.flipped != flipped;
}
