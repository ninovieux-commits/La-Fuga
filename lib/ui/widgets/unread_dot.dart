/// Pastille rouge d'un message non lu.
///
/// Un compteur entre parenthèses — « Messages (1) » — allonge l'intitulé et le
/// fait déborder dès qu'il y a deux chiffres. La pastille dit la même chose
/// sans toucher au texte, et se pose de la même façon sur une touche du menu
/// et sur celle d'un bandeau de partie.
library;

import 'package:flutter/material.dart';

import '../scale.dart';

/// Rouge de la pastille — celui du compteur de la messagerie.
const Color kUnreadRed = Color(0xFFD93333);

class UnreadDot extends StatelessWidget {
  const UnreadDot({super.key, required this.child, required this.show});

  final Widget child;

  /// Vrai quand il y a quelque chose à signaler.
  final bool show;

  @override
  Widget build(BuildContext context) {
    if (!show) return child;
    final size = S(14);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -size / 4,
          right: -size / 4,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: kUnreadRed,
              shape: BoxShape.circle,
              // Un liseré clair : la pastille reste visible sur un fond rouge
              // comme sur un fond sombre.
              border: Border.all(color: Colors.white, width: S(1.6)),
            ),
          ),
        ),
      ],
    );
  }
}
