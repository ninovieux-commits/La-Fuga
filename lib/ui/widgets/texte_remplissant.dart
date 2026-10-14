/// Un texte qui OCCUPE la place qu'on lui donne.
///
/// Nino : « le pseudo doit occuper l'espace (plus grand si pseudo court) […]
/// s'il n'y a admettons qu'un mot, il doit occuper la place. »
///
/// `FittedBox` ne sait que rétrécir un texte déjà mis en page, et il le fait
/// sur UNE ligne : un mot court y deviendrait géant et une devise de trois
/// lignes y serait écrasée. Ici on cherche la plus grande taille de police qui
/// tienne dans la boîte en au plus [maxLignes] lignes — ce qui agrandit un
/// nom court ET réduit un nom long, sans jamais rogner.
library;

import 'package:flutter/material.dart';

class TexteRemplissant extends StatelessWidget {
  const TexteRemplissant(
    this.texte, {
    super.key,
    required this.style,
    required this.tailleMin,
    required this.tailleMax,
    this.maxLignes = 1,
    this.align = TextAlign.start,
  });

  final String texte;

  /// Le style SANS taille : c'est elle qu'on cherche.
  final TextStyle style;

  /// Les bornes entre lesquelles chercher. La plus petite est celle en deçà
  /// de laquelle le texte ne se lit plus ; la plus grande, celle au-delà de
  /// laquelle il crierait.
  final double tailleMin;
  final double tailleMax;

  final int maxLignes;
  final TextAlign align;

  /// Précision de la recherche, en points. Sept passes suffisent à descendre
  /// sous le dixième de point entre deux bornes distantes de 40.
  static const int _passes = 7;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, boite) {
      final echelle = MediaQuery.textScalerOf(context);
      final largeur = boite.maxWidth;
      final hauteur = boite.maxHeight;

      bool tient(double taille) {
        final peintre = TextPainter(
          text: TextSpan(
            text: texte,
            style: style.copyWith(fontSize: taille),
          ),
          maxLines: maxLignes,
          textAlign: align,
          textScaler: echelle,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: largeur);
        return !peintre.didExceedMaxLines &&
            peintre.height <= hauteur + 0.5 &&
            peintre.width <= largeur + 0.5;
      }

      // Dichotomie : `basse` tient toujours, `haute` jamais.
      var basse = tailleMin;
      var haute = tailleMax;
      if (tient(haute)) {
        basse = haute;
      } else {
        for (var i = 0; i < _passes; i++) {
          final milieu = (basse + haute) / 2;
          if (tient(milieu)) {
            basse = milieu;
          } else {
            haute = milieu;
          }
        }
      }

      return Text(
        texte,
        maxLines: maxLignes,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: style.copyWith(fontSize: basse),
      );
    },
  );
}
