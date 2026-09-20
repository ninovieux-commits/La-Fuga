/// Bouton du menu — portage de `RoundButton` (main.py).
///
/// Rectangle arrondi plein, texte blanc gras centré. La couleur de fond dit
/// la fonction : clair du thème pour l'action principale, foncé pour le jeu
/// en ligne, gris pour le reste.
library;

import 'package:flutter/material.dart';

/// Gris des boutons secondaires — `COL_BTN_GREY` de Kivy.
const Color kFugaGrey = Color.fromRGBO(89, 89, 89, 1);

class FugaButton extends StatelessWidget {
  const FugaButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.color = kFugaGrey,
    this.textColor = Colors.white,
    this.height = 48,
    this.fontSize = 16,
    this.radius = 14,
  });

  final String text;
  final VoidCallback? onPressed;
  final Color color;
  final Color textColor;
  final double height;
  final double fontSize;
  final double radius;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Material(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onPressed,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
