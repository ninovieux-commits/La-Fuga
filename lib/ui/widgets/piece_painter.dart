/// Dessin des pièces — portage de `draw_piece` (main.py), rendu géométrique.
///
/// Le rendu à base d'images de thème (médiéval, fleurs, dragon, insectes,
/// deepgrey) viendra s'ajouter par-dessus ; ce fichier couvre le rendu
/// classique, qui sert de repli universel.
library;

import 'dart:math' as math;
import 'dart:ui';

import '../../engine/piece.dart';
import '../../theme/themes.dart';
import 'theme_image_cache.dart';

/// Dessine une pièce dans le carré [rect].
///
/// [outline] force la couleur du contour (sélection, groupe, immobilisation) ;
/// sinon on prend le contour par défaut du camp.
/// [pushHighlightDirs] grossit les points correspondant aux directions de
/// poussée disponibles, en couleur inversée, comme en Kivy.
void paintPiece(
  Canvas canvas,
  Rect rect,
  Piece piece,
  ThemePalette palette, {
  Color? outline,
  double outlineWidth = 2,
  Set<(int, int)> pushHighlightDirs = const {},
  bool flipped = true,
  Color boardColor = const Color(0xFF8C8C8C),
  LoadedThemeImages? images,
}) {
  // Thème à images : on dessine l'image de la pièce. Si elle manque, on
  // retombe sur le rendu géométrique plutôt que de laisser un trou.
  final themed = images?.pieceFor(piece);
  if (themed != null) {
    _paintPieceImage(
      canvas,
      rect,
      themed,
      cornerRadius: images!.cornerRadius,
      outline: outline,
      outlineWidth: outlineWidth,
    );
    return;
  }

  final sz = rect.width;
  final pad = sz * 0.04;
  final inner = sz - 2 * pad;
  final box = Rect.fromLTWH(rect.left + pad, rect.top + pad, inner, inner);
  final centre = rect.center;

  final bg = piece.camp == Camp.blanc
      ? FugaColors.whitePiece
      : FugaColors.blackPiece;
  final accent = piece.camp == Camp.blanc ? palette.clair : palette.fonce;
  final stroke =
      outline ??
      (piece.camp == Camp.blanc
          ? FugaColors.whiteOutline
          : FugaColors.blackOutline);

  final fill = Paint()..color = bg;
  final line = Paint()
    ..color = stroke
    ..style = PaintingStyle.stroke
    ..strokeWidth = outlineWidth;
  final acc = Paint()
    ..color = accent
    ..strokeCap = StrokeCap.round;

  // Le joueur Noir voit le plateau tourné à 180° : les deux axes s'inversent.
  final axis = flipped ? 1 : -1;
  final bigDirs = {
    for (final (dc, dr) in pushHighlightDirs) (dc * axis, dr * axis),
  };
  final bigColor = piece.camp == Camp.blanc
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);

  switch (piece.type) {
    case PieceType.soldat:
    case PieceType.garde:
      canvas.drawRect(box, fill);
      canvas.drawRect(box, line);
      final inset = inner * 0.18;
      final sw = math.max(2.0, inner * 0.10);
      acc.strokeWidth = sw;
      if (piece.type == PieceType.soldat) {
        // Croix « + » : le Soldat s'active en orthogonal…
        canvas.drawLine(
          Offset(box.left + inset, centre.dy),
          Offset(box.right - inset, centre.dy),
          acc,
        );
        canvas.drawLine(
          Offset(centre.dx, box.top + inset),
          Offset(centre.dx, box.bottom - inset),
          acc,
        );
        // …et pousse en diagonale : les points marquent les 4 diagonales.
        _paintDots(canvas, centre, inner, accent, bigColor, bigDirs, const [
          (-1, -1),
          (1, -1),
          (-1, 1),
          (1, 1),
        ], axis);
      } else {
        // Croix « × » : le Garde s'active en diagonal…
        canvas.drawLine(
          Offset(box.left + inset, box.top + inset),
          Offset(box.right - inset, box.bottom - inset),
          acc,
        );
        canvas.drawLine(
          Offset(box.left + inset, box.bottom - inset),
          Offset(box.right - inset, box.top + inset),
          acc,
        );
        // …et pousse en orthogonal.
        _paintDots(canvas, centre, inner, accent, bigColor, bigDirs, const [
          (0, -1),
          (0, 1),
          (-1, 0),
          (1, 0),
        ], axis);
      }

    case PieceType.nurse:
      canvas.drawCircle(centre, inner / 2, fill);
      canvas.drawCircle(centre, inner / 2, line);

    case PieceType.heritier:
      canvas.drawCircle(centre, inner / 2, fill);
      canvas.drawCircle(centre, inner / 2, line);
      // Anneau d'accent, puis un « trou » peint à la couleur du plateau :
      // l'illusion de transparence du rendu Kivy.
      final d = inner * 0.20;
      canvas.drawCircle(centre, (inner - 2 * d) / 2, Paint()..color = accent);
      canvas.drawCircle(centre, inner * 0.14, Paint()..color = boardColor);

    case PieceType.chevalier:
      final hOff = inner * 0.20;
      final path = Path()
        ..moveTo(centre.dx, box.top)
        ..lineTo(box.right, centre.dy - hOff)
        ..lineTo(box.right, centre.dy + hOff)
        ..lineTo(centre.dx, box.bottom)
        ..lineTo(box.left, centre.dy + hOff)
        ..lineTo(box.left, centre.dy - hOff)
        ..close();
      canvas.drawPath(path, Paint()..color = accent);
      canvas.drawPath(path, line);
  }
}

/// Points marquant les directions de poussée, grossis et inversés quand la
/// direction est effectivement poussable.
void _paintDots(
  Canvas canvas,
  Offset centre,
  double inner,
  Color accent,
  Color bigColor,
  Set<(int, int)> bigDirs,
  List<(int, int)> dirs,
  int axis,
) {
  final r = inner * 0.06;
  final off = inner * 0.30;
  for (final (dc, dr) in dirs) {
    final isBig = bigDirs.contains((dc, dr));
    final radius = isBig ? r * 2 : r;
    canvas.drawCircle(
      // dr positif = vers l'avant en coordonnées de jeu, donc vers le HAUT à
      // l'écran quand les Blancs sont en bas : d'où le signe inversé sur dy.
      Offset(centre.dx + dc * off * axis, centre.dy - dr * off * axis),
      radius,
      Paint()..color = isBig ? bigColor : accent,
    );
  }
}

/// Dessine l'image d'une pièce dans sa case.
///
/// [cornerRadius] arrondit les coins : certaines images portent un filigrane
/// dans un angle, et l'arrondi le fait disparaître sans que cela se voie.
void _paintPieceImage(
  Canvas canvas,
  Rect rect,
  Image image, {
  required double cornerRadius,
  Color? outline,
  double outlineWidth = 2,
}) {
  final pad = rect.width * 0.04;
  final box = rect.deflate(pad);

  canvas.save();
  if (cornerRadius > 0) {
    final radius = Radius.circular(box.width * cornerRadius);
    canvas.clipRRect(RRect.fromRectAndRadius(box, radius));
  }
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    box,
    Paint()..filterQuality = FilterQuality.medium,
  );
  canvas.restore();

  if (outline != null) {
    final paint = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = outlineWidth;
    if (cornerRadius > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, Radius.circular(box.width * cornerRadius)),
        paint,
      );
    } else {
      canvas.drawRect(box, paint);
    }
  }
}
