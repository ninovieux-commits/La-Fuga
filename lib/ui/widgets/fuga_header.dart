/// Bandeau de titre des écrans secondaires — portage du `header` que tous les
/// écrans de Kivy construisent à l'identique (`BoxLayout(size_hint=(1, 0.08))`
/// avec un bouton de retour large de 110, le titre en italique noir au centre,
/// et un vide de même largeur à droite pour que le titre reste centré).
library;

import 'package:flutter/material.dart';

import 'fuga_button.dart';

class FugaHeader extends StatelessWidget implements PreferredSizeWidget {
  const FugaHeader({
    super.key,
    required this.back,
    required this.title,
    required this.onBack,
    this.titleSize = 28,
  });

  /// Intitulé du bouton de retour, barre chevron comprise : `< Menu`.
  final String back;

  final String title;
  final VoidCallback onBack;

  /// Kivy varie la taille du titre d'un écran à l'autre : 32 pour
  /// l'historique, 28 pour ses deux listes, 26 pour le lecteur.
  final double titleSize;

  static const double _sideWidth = 110;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: _sideWidth,
            child: FugaButton(
              text: back,
              fontSize: 14,
              height: double.infinity,
              onPressed: onBack,
            ),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: titleSize,
                fontStyle: FontStyle.italic,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(width: _sideWidth),
        ],
      ),
    ),
  );
}
