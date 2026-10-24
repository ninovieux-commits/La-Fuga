/// Le dessin d'une touche à pictogramme, posé comme une lettre.
///
/// ## Pourquoi il ne remplit pas la touche
///
/// Un pictogramme est cadré sur son sujet : il touche les quatre bords de son
/// fichier. Posé avec la marge d'un texte, il occupait 85 % de la touche et en
/// avalait la forme — la boule, qui est ronde, faisait lire un DISQUE là où
/// ses voisines sont des carrés. Nino : « la touche doit avoir la même forme
/// carrée que les autres ! Ainsi que la touche drapeau de tout à l'heure
/// d'ailleurs. »
///
/// Un glyphe de texte, lui, occupe un peu plus de la moitié de sa touche, et
/// c'est précisément ce qui laisse voir le carré autour. Le dessin prend donc
/// la même part.
///
/// ## Et il la prend en FRACTION de la touche
///
/// Une marge en pixels de référence suit la LARGEUR de l'écran (`S`), alors
/// que ces touches sont carrées sur la HAUTEUR de leur bandeau : la part du
/// dessin changerait d'un téléphone à l'autre, et la forme avec elle.
library;

import 'package:flutter/material.dart';

/// Part de la touche qu'occupe le dessin — le reste est le carré qu'on voit.
const double kPartPicto = 0.58;

class PictoTouche extends StatelessWidget {
  const PictoTouche({
    super.key,
    required this.asset,
    required this.couleur,
    this.secours = '?',
  });

  /// Le fichier : blanc sur fond transparent, teinté ici par le thème, comme
  /// les instruments des réglages.
  final String asset;

  final Color couleur;

  /// Ce qui s'affiche si le dessin manque : une touche sans rien dessus n'est
  /// plus une touche.
  final String secours;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    widthFactor: kPartPicto,
    heightFactor: kPartPicto,
    child: Image.asset(
      asset,
      color: couleur,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) => FittedBox(
        child: Text(
          secours,
          style: TextStyle(color: couleur, fontWeight: FontWeight.bold),
        ),
      ),
    ),
  );
}
