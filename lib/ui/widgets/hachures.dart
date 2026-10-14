/// Les hachures d'une touche HORS SERVICE — partout dans l'application.
///
/// Nino : « j'aimerai aussi que les boutons "½" et ">" et "<" soient plutôt
/// hachurés quand inutilisables. En fait si tu pouvais appliquer ce réglage
/// partout dans l'app ça serait l'idéal. »
///
/// Jusqu'ici chaque touche éteinte se débrouillait à sa façon : l'une pâlissait
/// (`Opacity(0.35)`), l'autre se fondait à moitié dans son panneau, la
/// troisième gardait sa couleur. Pâle, une touche ressemble surtout à une
/// touche mal imprimée ; hachurée, on voit qu'elle existe, qu'elle est la même
/// qu'ailleurs, et qu'ici elle ne sert pas.
///
/// [HorsService] enveloppe n'importe quelle touche : à elle de dire si elle
/// répond, les hachures suivent.
library;

import 'package:flutter/material.dart';

import '../scale.dart';

/// Marque les hachures dans l'arbre : un bouton contient d'autres
/// `CustomPaint` que les siennes — l'encre de Material en pose une — et un
/// test doit pouvoir montrer CELLES-CI.
const Key kHachuresKey = ValueKey('hachures');

/// Une touche, hachurée quand elle ne répond pas.
class HorsService extends StatelessWidget {
  const HorsService({
    super.key,
    required this.child,
    required this.actif,
    required this.rayon,
  });

  final Widget child;

  /// Faux : la touche est là, visible, et hors service.
  final bool actif;

  /// Le rayon des coins de la touche : les hachures s'y arrêtent.
  final double rayon;

  @override
  Widget build(BuildContext context) {
    if (actif) return child;
    return Stack(
      children: [
        child,
        // Les hachures ne sont PAS touchables : sans ce filtre, elles
        // avaleraient le toucher au lieu de le laisser passer à la touche
        // éteinte — qui, elle, ne répond déjà plus.
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(rayon),
              child: CustomPaint(
                key: kHachuresKey,
                painter: Hachures(pas: S(12)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Les traits noirs en diagonale.
class Hachures extends CustomPainter {
  const Hachures({required this.pas});

  /// Écart entre deux traits.
  final double pas;

  @override
  void paint(Canvas canvas, Size size) {
    final trait = Paint()
      ..color = Colors.black
      ..strokeWidth = pas / 3
      ..strokeCap = StrokeCap.square;
    // Des diagonales à 45°, du coin bas-gauche vers le haut-droit. On part
    // AVANT la touche pour que les premières la traversent aussi.
    for (var x = -size.height; x < size.width; x += pas) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        trait,
      );
    }
  }

  @override
  bool shouldRepaint(Hachures old) => old.pas != pas;
}
