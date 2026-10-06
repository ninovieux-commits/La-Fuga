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

  /// Hauteur imposée. Nulle — le cas normal : l'épaisseur d'une touche,
  /// la même partout. `double.infinity` remplit la place disponible, à
  /// réserver aux touches dont le cadre est déjà à la bonne épaisseur.
  final double? height;

  /// Épaisseur d'une touche : celle des grandes touches du menu.
  static double get comfortableHeight => touchHeight();

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
            // Le texte RÉTRÉCIT plutôt que d'être coupé, quoi qu'il arrive.
            // Une touche a une largeur, le texte en a une autre, et Flutter
            // tranche l'excédent SANS lever la moindre erreur : un libellé
            // trop long part en production amputé, et seul l'œil le voit.
            // Les dix langues ne font pas la même longueur — la garantie est
            // donc ici, dans la touche, et non dans un test qui espère.
            //
            // La marge reste en dehors : seules les lettres se réduisent, le
            // texte ne vient jamais lécher le bord.
            child: FittedBox(
              fit: BoxFit.scaleDown,
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
      ),
    );
    return SizedBox(height: height ?? comfortableHeight, child: button);
  }
}
