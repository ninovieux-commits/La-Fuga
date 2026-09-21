/// Bouton du menu — portage de `RoundButton` (main.py).
///
/// Rectangle arrondi plein, texte blanc gras centré. La couleur de fond dit
/// la fonction : clair du thème pour l'action principale, foncé pour le jeu
/// en ligne, gris pour le reste.
library;

import 'package:flutter/material.dart';

import '../scale.dart';

/// Gris des boutons secondaires — `COL_BTN_GREY` de Kivy.
const Color kFugaGrey = Color.fromRGBO(89, 89, 89, 1);

class FugaButton extends StatelessWidget {
  const FugaButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.color = kFugaGrey,
    this.textColor = Colors.white,
    this.height,
    this.fontSize,
    this.radius,
  });

  final String text;
  final VoidCallback? onPressed;
  final Color color;
  final Color textColor;

  /// Hauteur imposée. Nulle : la hauteur de confort, assez grande pour qu'on
  /// vise sans réfléchir. `double.infinity` remplit la place disponible.
  final double? height;

  /// Hauteur d'une touche à laquelle on n'en impose pas : les popups de Kivy
  /// tournent autour de S(48)–S(50).
  static double get comfortableHeight => S(52);

  final double? fontSize;

  /// Rayon des coins — `S(18)` par défaut, comme `RoundButton`.
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final r = radius ?? S(18);
    final button = Material(
      color: color,
      borderRadius: BorderRadius.circular(r),
      child: InkWell(
        borderRadius: BorderRadius.circular(r),
        onTap: onPressed,
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: S(10)),
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: TextStyle(
                color: textColor,
                fontSize: fontSize ?? SF(16),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
    return SizedBox(height: height ?? comfortableHeight, child: button);
  }
}
