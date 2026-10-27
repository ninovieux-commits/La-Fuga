/// La place qu'occupe un émoji — la « taille smiley ».
///
/// Nino, des pièces posées dans un message : « taille smiley ». Une pièce
/// envoyée comme un émoji doit en faire la taille, sans quoi elle dépasse de
/// la ligne ou s'y perd.
///
/// ON LA MESURE, on ne la devine pas. Un émoji n'occupe pas la taille de
/// police qu'on lui donne : il la déborde d'un sixième environ, et de combien
/// exactement dépend de la police qui le dessine — celle du système, qui
/// n'est pas la nôtre. Un facteur écrit à la main serait juste sur un
/// téléphone et faux sur le suivant.
library;

import 'package:flutter/widgets.dart';

/// L'émoji témoin : rond, plein, sans accent ni queue — il occupe la boîte
/// que les autres occupent.
const String _temoin = '\u{1F600}';

final Map<double, double> _mesures = {};

/// Côté du carré qu'occupe un émoji de cette taille de police.
///
/// Mémorisé : la mesure demande une mise en page de texte, et une bulle la
/// redemande à chaque image.
double tailleDUnEmoji(double fontSize) =>
    _mesures[fontSize] ??= _mesure(fontSize);

double _mesure(double fontSize) {
  final peintre = TextPainter(
    text: TextSpan(
      text: _temoin,
      style: TextStyle(fontSize: fontSize),
    ),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  // La hauteur de la ligne, pas la largeur : un émoji est carré, et sa
  // largeur dépend de la chasse que la police lui donne.
  final cote = peintre.height;
  return cote > 0 ? cote : fontSize;
}
