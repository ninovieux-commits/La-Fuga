/// Aperçu de l'instrument choisi, dans les réglages.
///
/// Un dessin vaut mieux qu'un nom : on voit ce qu'on choisit avant de
/// l'entendre.
///
/// Les dessins sont des PNG blancs sur fond transparent
/// (`tool/gen_instruments.py`), teintés ici à la couleur du thème. Garder
/// leur fond d'origine, qui est blanc, aurait troué l'écran sombre des
/// réglages d'un carré clair.
library;

import 'package:flutter/material.dart';

/// Où vit le dessin d'un instrument.
String instrumentAsset(String instrument) =>
    'assets/instruments/$instrument.png';

class InstrumentPreview extends StatelessWidget {
  const InstrumentPreview({
    super.key,
    required this.instrument,
    required this.couleur,
  });

  final String instrument;

  /// La teinte du dessin — celle du thème en cours.
  final Color couleur;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: instrument,
    child: Image.asset(
      instrumentAsset(instrument),
      color: couleur,
      fit: BoxFit.contain,
      // Un instrument sans dessin ne doit pas casser l'écran : il ne montre
      // rien, et son nom reste lisible à côté.
      errorBuilder: (context, error, stack) => const SizedBox.shrink(),
    ),
  );
}
