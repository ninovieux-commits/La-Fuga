/// Rosace du logo La Fuga — portage de `draw_logo` (main.py).
///
/// Huit segments rectangulaires en couronne, alternant les deux accents du
/// thème, avec des triangles noir et blanc dans les intervalles.
///
/// Deux tracés : la version **colorée** pour le logo, et la version
/// **contours seuls** dessinée au centre du plateau, sous les pièces.
library;

import 'dart:math' as math;
import 'dart:ui';

/// Dessine la rosace colorée, centrée sur ([cx], [cy]).
void paintLogo(
  Canvas canvas,
  double cx,
  double cy,
  double radius, {
  required Color clair,
  required Color fonce,
  double lineWidth = 2.5,
}) {
  final innerR = radius * 0.42;
  final outerR = radius;
  const segHalf = math.pi / 8; // 22,5° de demi-largeur

  // Huit segments : accent clair aux cardinales, foncé aux diagonales.
  for (var i = 0; i < 8; i++) {
    final ang = -math.pi / 2 + i * (math.pi / 4); // part du haut, sens horaire
    final a1 = ang - segHalf;
    final a2 = ang + segHalf;
    final path = Path()
      ..moveTo(cx + innerR * math.cos(a1), cy + innerR * math.sin(a1))
      ..lineTo(cx + outerR * math.cos(a1), cy + outerR * math.sin(a1))
      ..lineTo(cx + outerR * math.cos(a2), cy + outerR * math.sin(a2))
      ..lineTo(cx + innerR * math.cos(a2), cy + innerR * math.sin(a2))
      ..close();
    canvas.drawPath(path, Paint()..color = i.isEven ? clair : fonce);
  }

  // Petits triangles dans les intervalles, noir et blanc en alternance.
  for (var i = 0; i < 8; i++) {
    final gap = -math.pi / 2 + i * (math.pi / 4) + math.pi / 8;
    final a1 = gap - math.pi / 24;
    final a2 = gap + math.pi / 24;
    final tip = innerR + (outerR - innerR) * 0.55;
    final path = Path()
      ..moveTo(cx + outerR * math.cos(a1), cy + outerR * math.sin(a1))
      ..lineTo(cx + outerR * math.cos(a2), cy + outerR * math.sin(a2))
      ..lineTo(cx + tip * math.cos(gap), cy + tip * math.sin(gap))
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = i.isEven ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
    );
  }

  final stroke = Paint()
    ..color = const Color(0xFF000000)
    ..style = PaintingStyle.stroke
    ..strokeWidth = lineWidth;
  canvas.drawCircle(Offset(cx, cy), outerR, stroke);
  canvas.drawCircle(Offset(cx, cy), innerR, stroke);
  for (var i = 0; i < 8; i++) {
    for (final sign in [-1, 1]) {
      final ang = -math.pi / 2 + i * (math.pi / 4) + sign * segHalf;
      canvas.drawLine(
        Offset(cx + innerR * math.cos(ang), cy + innerR * math.sin(ang)),
        Offset(cx + outerR * math.cos(ang), cy + outerR * math.sin(ang)),
        stroke,
      );
    }
  }
}

/// Dessine la rosace en contours seuls, pour le centre du plateau.
///
/// Les segments sont assez larges pour que les côtés de deux voisins se
/// croisent : on garde la partie externe de chaque croisement — le triangle
/// qui pointe vers le centre — et on relie la croisée au centre par un seul
/// trait, au lieu du V intérieur.
void paintLogoOutline(
  Canvas canvas,
  double cx,
  double cy,
  double radius, {
  required Color color,
  double strokeWidth = 1.6,
}) {
  final outerR = radius;
  final innerR = radius * 0.49;
  final half = outerR * 0.50 / 2;

  final stroke = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth;

  canvas.drawCircle(Offset(cx, cy), outerR, stroke);
  canvas.drawCircle(Offset(cx, cy), innerR, stroke);

  /// Les deux extrémités d'un côté de segment, décalé de [offset] de l'axe.
  (Offset, Offset) side(double theta, double offset) {
    final ct = math.cos(theta), st = math.sin(theta);
    final ti = math.sqrt(math.max(0, innerR * innerR - offset * offset));
    final to = math.sqrt(math.max(0, outerR * outerR - offset * offset));
    return (
      Offset(cx + ti * ct - offset * st, cy + ti * st + offset * ct),
      Offset(cx + to * ct - offset * st, cy + to * st + offset * ct),
    );
  }

  for (var g = 0; g < 8; g++) {
    final thi = -math.pi / 2 + g * (math.pi / 4);
    final thj = -math.pi / 2 + (g + 1) * (math.pi / 4);
    final (ai, ao) = side(thi, half);
    final (bi, bo) = side(thj, -half);

    final crossing = _intersection(ai, ao, bi, bo);
    if (crossing == null) continue;

    canvas.drawLine(ao, crossing, stroke);
    canvas.drawLine(bo, crossing, stroke);

    final gap = thi + math.pi / 8;
    canvas.drawLine(
      crossing,
      Offset(cx + innerR * math.cos(gap), cy + innerR * math.sin(gap)),
      stroke,
    );
  }
}

/// Intersection de deux droites, ou `null` si elles sont parallèles.
Offset? _intersection(Offset p1, Offset p2, Offset p3, Offset p4) {
  final den =
      (p1.dx - p2.dx) * (p3.dy - p4.dy) - (p1.dy - p2.dy) * (p3.dx - p4.dx);
  if (den.abs() < 1e-9) return null;
  final t =
      ((p1.dx - p3.dx) * (p3.dy - p4.dy) - (p1.dy - p3.dy) * (p3.dx - p4.dx)) /
      den;
  return Offset(p1.dx + t * (p2.dx - p1.dx), p1.dy + t * (p2.dy - p1.dy));
}
