/// Bandeau de titre des écrans secondaires — portage du `header` que tous les
/// écrans de Kivy construisent à l'identique (`BoxLayout(size_hint=(1, 0.08))`
/// avec un bouton de retour large de 110, le titre en italique noir au centre,
/// et un vide de même largeur à droite pour que le titre reste centré).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'fuga_button.dart';
import '../scale.dart';

class FugaHeader extends StatelessWidget implements PreferredSizeWidget {
  const FugaHeader({
    super.key,
    required this.back,
    required this.title,
    required this.onBack,
    this.titleSize = 28,
    this.titleColor = Colors.black,
    this.bold = false,
  });

  /// Intitulé du bouton de retour, barre chevron comprise : `< Menu`.
  final String back;

  final String title;
  final VoidCallback onBack;

  /// Kivy varie la taille du titre d'un écran à l'autre : 32 pour
  /// l'historique, 28 pour ses deux listes, 26 pour le lecteur.
  final double titleSize;

  /// Noir partout, sauf sur le composeur de thèmes où Kivy l'écrit en blanc.
  final Color titleColor;

  /// Les titres en gras (messagerie, composeur) ne sont pas en italique.
  final bool bold;

  static const double _sideWidth = 110;

  /// Hauteur du bandeau : la plus grande de sa touche et de son titre, plus
  /// les marges.
  ///
  /// Le titre était écrit à sa taille de référence BRUTE, sans passer par
  /// `SF` — un `32` fixe dans un bandeau qui n'en faisait que 24 de haut, et
  /// le mot était coupé par le milieu. Il suit maintenant l'échelle de
  /// l'écran, et le bandeau s'ouvre pour le laisser tenir en entier.
  @override
  Size get preferredSize => Size.fromHeight(
    math.max(touchHeight(), SF(titleSize) * _lineHeight) + 2 * S(6),
  );

  /// Hauteur d'une ligne rapportée à la taille de police. Mesurée sur la
  /// police de l'appli : 1,43. Arrondie au-dessus, pour les accents.
  static const double _lineHeight = 1.45;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: preferredSize.height,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: S(8), vertical: S(6)),
      child: Row(
        children: [
          SizedBox(
            width: _sideWidth,
            child: FugaButton(text: back, fontSize: SF(16), onPressed: onBack),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: SF(titleSize),
                fontStyle: bold ? FontStyle.normal : FontStyle.italic,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                color: titleColor,
              ),
            ),
          ),
          const SizedBox(width: _sideWidth),
        ],
      ),
    ),
  );
}
