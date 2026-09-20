/// Visite guidée du menu — portage de `MenuTourOverlay` (main.py).
///
/// Un calque par-dessus le VRAI menu : l'élément décrit est entouré d'un
/// anneau rouge, une bulle de texte en bas explique, et deux touches font
/// avancer ou reculer. C'est la dernière étape du tuto.
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../tuto/menu_tour.g.dart';
import 'fuga_button.dart';

/// Une étape de la visite : ce qu'elle entoure, et ce qu'elle dit.
final class MenuTourStop {
  const MenuTourStop(this.targets, this.text);

  /// Noms des éléments du menu à entourer.
  final List<String> targets;

  final String text;
}

/// Les étapes, lues une fois depuis les données extraites de Kivy.
List<MenuTourStop> loadMenuTour([String json = kMenuTourJson]) => [
  for (final s in jsonDecode(json) as List)
    MenuTourStop([
      for (final t in (s as Map)['targets'] as List? ?? const []) '$t',
    ], '${s['text'] ?? ''}'),
];

/// Le calque de la visite.
class MenuTourOverlay extends StatelessWidget {
  const MenuTourOverlay({
    super.key,
    required this.stop,
    required this.index,
    required this.count,
    required this.rings,
    required this.onPrevious,
    required this.onNext,
  });

  final MenuTourStop stop;
  final int index;
  final int count;

  /// Rectangles à entourer, déjà situés à l'écran.
  final List<Rect> rings;

  /// Reculer depuis la première étape renvoie au tuto.
  final VoidCallback onPrevious;

  /// Avancer depuis la dernière termine la visite.
  final VoidCallback onNext;

  bool get _isLast => index == count - 1;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      // Les anneaux ne prennent pas les touchers : le menu défile toujours.
      IgnorePointer(
        child: CustomPaint(size: Size.infinite, painter: _RingsPainter(rings)),
      ),
      Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          color: const Color(0xF2171722),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  T(stop.text),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FugaButton(
                        text: T('< Précédent'),
                        fontSize: 14,
                        onPressed: onPrevious,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FugaButton(
                        text: _isLast ? T('Fermer') : T('Continuer >'),
                        color: const Color(0xFF2E74D9),
                        fontSize: 14,
                        onPressed: onNext,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _RingsPainter extends CustomPainter {
  const _RingsPainter(this.rings);

  final List<Rect> rings;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFFD93A3A);
    for (final r in rings) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(r.inflate(4), const Radius.circular(14)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.rings != rings;
}
