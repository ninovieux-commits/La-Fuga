/// Bandeau de titre des écrans secondaires — portage du `header` que tous les
/// écrans de Kivy construisent à l'identique (`BoxLayout(size_hint=(1, 0.08))`
/// avec un bouton de retour large de 110, le titre en italique noir au centre,
/// et un vide de même largeur à droite pour que le titre reste centré).
library;

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

  /// Le bandeau fait la hauteur de sa touche, plus ses marges : c'est la
  /// touche de retour qui commande, et elle a l'épaisseur des autres.
  @override
  Size get preferredSize => Size.fromHeight(touchHeight() + 2 * S(6));

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
                fontSize: titleSize,
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
