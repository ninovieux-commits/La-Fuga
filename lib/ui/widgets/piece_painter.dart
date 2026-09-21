/// Dessin des pièces — portage de `draw_piece` (main.py), rendu géométrique.
///
/// Les thèmes à images (médiéval, fleurs, dragon, insectes) passent par
/// [LoadedThemeImages] ; le rendu géométrique sert pour tous les autres et
/// de repli universel.
///
/// **Épaisseurs de trait.** Kivy trace un `Line(width: w)` en décalant les
/// bords de ±w de part et d'autre de l'axe : le trait fait donc **2w** à
/// l'écran. Flutter, lui, prend l'épaisseur totale. Les valeurs de Kivy sont
/// donc doublées ici, sinon tous les signes des pièces paraissent deux fois
/// trop fins.
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
  String? theme,
  double? rainbowFraction,
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

  // Thème deepgrey : corps gris pour tout le monde, détails en blanc (pièces
  // blanches) ou noir (pièces noires) — les camps restent lisibles.
  final isDeepGrey = theme == 'deepgrey';
  final detail = piece.camp == Camp.blanc
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF000000);

  final bg = isDeepGrey
      ? kDeepGreyBody
      : (piece.camp == Camp.blanc
            ? FugaColors.whitePiece
            : FugaColors.blackPiece);
  final accent = isDeepGrey
      ? detail
      : (theme == 'arcenciel' && rainbowFraction != null
            ? rainbowColor(rainbowFraction)
            : (piece.camp == Camp.blanc ? palette.clair : palette.fonce));
  final stroke =
      outline ??
      (isDeepGrey
          ? detail
          : (piece.camp == Camp.blanc
                ? FugaColors.whiteOutline
                : FugaColors.blackOutline));

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
      acc.strokeWidth = kivyLine(math.max(2.0, inner * 0.10));
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
        _paintDots(
          canvas,
          centre,
          inner,
          accent,
          bigColor,
          bigDirs,
          const [(-1, -1), (1, -1), (-1, 1), (1, 1)],
          // Le Soldat porte ses points en X, un peu resserrés.
          offset: 0.30,
        );
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
        _paintDots(
          canvas,
          centre,
          inner,
          accent,
          bigColor,
          bigDirs,
          const [(0, -1), (0, 1), (-1, 0), (1, 0)],
          // Le Garde porte les siens en croix, plus écartés.
          offset: 0.36,
        );
      }

    case PieceType.nurse:
      canvas.drawCircle(centre, inner / 2, fill);
      canvas.drawCircle(centre, inner / 2, line);
      if (isDeepGrey) {
        // Nurse deepgrey : un point plein au centre, à la couleur du camp.
        canvas.drawCircle(centre, inner * 0.24, Paint()..color = accent);
      }

    case PieceType.heritier:
      // Attention : le corps n'est PAS peint ici. L'Héritier ordinaire a un
      // trou au centre, et un disque plein posé d'avance le boucherait.
      if (isDeepGrey) {
        canvas.drawCircle(centre, inner / 2, fill);
        canvas.drawCircle(centre, inner / 2, line);
        // Héritier deepgrey : un gros cœur plein qui se fond vers le gris sur
        // le bord — douze cercles concentriques, comme en Kivy.
        const steps = 12;
        for (var i = 0; i < steps; i++) {
          final frac = i / (steps - 1);
          final r = (inner / 2) * (1 - frac * 0.90);
          final t = math.min(1.0, frac / 0.55);
          canvas.drawCircle(
            centre,
            r,
            Paint()..color = Color.lerp(kDeepGreyBody, detail, t)!,
          );
        }
        canvas.drawCircle(centre, inner / 2, line);
      } else {
        // Anneau d'accent, et un VRAI trou au centre : le plateau se voit au
        // travers. Kivy peignait ce disque à la couleur du plateau — une
        // illusion qui ne tient ni sur un plateau à image, ni sur une zone de
        // ralliement. Ici, le trou n'est tout simplement PAS peint : le corps
        // et l'anneau sont des tracés à trou (règle pair-impair), sans calque
        // ni effacement, ce qui marche sur tous les moteurs de rendu.
        final d = inner * 0.20;
        final holeRadius = inner * 0.14;
        final hole = Rect.fromCircle(center: centre, radius: holeRadius);

        Path ringAround(double radius) => Path()
          ..addOval(Rect.fromCircle(center: centre, radius: radius))
          ..addOval(hole)
          ..fillType = PathFillType.evenOdd;

        canvas.drawPath(ringAround(inner / 2), fill);
        canvas.drawPath(
          ringAround((inner - 2 * d) / 2),
          Paint()..color = accent,
        );
        canvas.drawCircle(centre, inner / 2, line);
      }

    case PieceType.chevalier:
      final hOff = inner * 0.20;
      final path = Path();
      for (var i = 0; i < 6; i++) {
        final p = _knightPoint(i, box, centre, hOff);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = isDeepGrey ? bg : accent);
      canvas.drawPath(path, line);
      if (isDeepGrey) {
        // Centre hexagonal réduit, à la couleur du camp.
        final small = Path();
        for (var i = 0; i < 6; i++) {
          final p = _knightPoint(i, box, centre, hOff);
          final scaled = Offset(
            centre.dx + (p.dx - centre.dx) * 0.45,
            centre.dy + (p.dy - centre.dy) * 0.45,
          );
          i == 0
              ? small.moveTo(scaled.dx, scaled.dy)
              : small.lineTo(scaled.dx, scaled.dy);
        }
        small.close();
        canvas.drawPath(small, Paint()..color = accent);
      }
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
  List<(int, int)> dirs, {
  required double offset,
}) {
  final r = inner * 0.06;
  final off = inner * offset;
  for (final (dc, dr) in dirs) {
    // Les points sont à une place FIXE sur la pièce ; seule la direction
    // mise en évidence dépend de l'orientation du plateau, et l'appelant l'a
    // déjà transformée. C'est ce que fait Kivy.
    final isBig = bigDirs.contains((dc, dr));
    final radius = isBig ? r * 2 : r;
    canvas.drawCircle(
      // dr positif = vers l'avant en coordonnées de jeu, donc vers le HAUT à
      // l'écran : d'où le signe inversé sur dy.
      Offset(centre.dx + dc * off, centre.dy - dr * off),
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

/// Corps gris des pièces du thème deepgrey.
const Color kDeepGreyBody = Color(0xFF808080);

/// Les huit couleurs du thème « arc-en-ciel » — portage de `RAINBOW_PALETTE`.
const List<Color> kRainbowPalette = [
  Color.fromRGBO(242, 66, 54, 1), // rouge
  Color.fromRGBO(242, 140, 38, 1), // orange
  Color.fromRGBO(250, 217, 51, 1), // jaune
  Color.fromRGBO(102, 204, 77, 1), // vert
  Color.fromRGBO(51, 179, 179, 1), // turquoise
  Color.fromRGBO(64, 140, 242, 1), // bleu
  Color.fromRGBO(140, 102, 230, 1), // violet
  Color.fromRGBO(242, 115, 191, 1), // rose
];

/// Couleur d'accent du thème arc-en-ciel pour une fraction 0→1.
///
/// Le fond et les contours ne changent pas : les camps restent distinguables.
Color rainbowColor(double fraction) {
  final index = (fraction * (kRainbowPalette.length - 1)).round();
  return kRainbowPalette[index.clamp(0, kRainbowPalette.length - 1)];
}

/// Fraction arc-en-ciel d'une case, fixe selon sa position.
double rainbowFractionOf(int col, int row) =>
    ((col * 3 + row * 5) % kRainbowPalette.length) /
    (kRainbowPalette.length - 1);

/// Un sommet de l'hexagone du Chevalier.
Offset _knightPoint(int i, Rect box, Offset centre, double hOff) => switch (i) {
  0 => Offset(centre.dx, box.top),
  1 => Offset(box.right, centre.dy - hOff),
  2 => Offset(box.right, centre.dy + hOff),
  3 => Offset(centre.dx, box.bottom),
  4 => Offset(box.left, centre.dy + hOff),
  _ => Offset(box.left, centre.dy - hOff),
};
