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

  /// Le plancher ABSOLU, sous [tailleMin], et pour la HAUTEUR seulement.
  ///
  /// [tailleMin] dit « en deçà, ça ne se lit plus », et c'est la bonne règle
  /// tant que le texte ne risque que d'être trop long : `TextOverflow`
  /// l'abrège d'un « … », ce qui se lit encore.
  ///
  /// Trop HAUT, en revanche, il n'est pas abrégé : il est tranché en plein
  /// milieu, et là plus rien ne se lit. Entre un texte un peu trop petit et
  /// un texte coupé en deux, on prend le petit, et on descend jusqu'ici.
  ///
  /// Ce n'est pas un cas d'école : les boîtes se mesurent en `S` et les
  /// polices en `SF`, qui vaut 1,70 fois plus. La ligne des mélos du profil
  /// demandait `SF(9)` — soit 15,3 — dans une boîte de `S(16)`, et sortait
  /// coupée en deux sur tous les téléphones.
  static const double _plancher = 6;

  /// Interligne imposé, quand le style n'en donne pas.
  ///
  /// Sans lui, la hauteur d'une ligne est celle que la POLICE décide : 1,0
  /// pour celle des tests, 1,17 pour Roboto, autre chose ailleurs. Une boîte
  /// juste assez haute en test sortait donc coupée sur un téléphone, et le
  /// test ne pouvait pas le voir. En le fixant, la mise en page est la même
  /// partout — et un défaut de hauteur se reproduit en test.
  static const double _interligne = 1.2;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, boite) {
      final echelle = MediaQuery.textScalerOf(context);
      final largeur = boite.maxWidth;
      final hauteur = boite.maxHeight;

      final base = style.height == null
          ? style.copyWith(height: _interligne)
          : style;

      TextPainter mesure(double taille) => TextPainter(
        text: TextSpan(
          text: texte,
          style: base.copyWith(fontSize: taille),
        ),
        maxLines: maxLignes,
        textAlign: align,
        textScaler: echelle,
        textDirection: Directionality.of(context),
      )..layout(maxWidth: largeur);

      bool tient(double taille) {
        final peintre = mesure(taille);
        return !peintre.didExceedMaxLines &&
            peintre.height <= hauteur + 0.5 &&
            peintre.width <= largeur + 0.5;
      }

      bool tientEnHauteur(double taille) =>
          mesure(taille).height <= hauteur + 0.5;

      /// La plus grande taille qui satisfasse [critere], entre deux bornes.
      double cherche(
        double basse,
        double haute,
        bool Function(double) critere,
      ) {
        for (var i = 0; i < _passes; i++) {
          final milieu = (basse + haute) / 2;
          if (critere(milieu)) {
            basse = milieu;
          } else {
            haute = milieu;
          }
        }
        return basse;
      }

      // Dichotomie : `basse` tient toujours, `haute` jamais.
      var basse = tailleMin;
      if (tient(tailleMax)) {
        basse = tailleMax;
      } else {
        basse = cherche(tailleMin, tailleMax, tient);
        // Même à [tailleMin], le texte peut encore être trop HAUT pour sa
        // boîte — et là il serait tranché, pas abrégé. On redescend donc
        // sur le seul critère de la hauteur.
        if (!tientEnHauteur(basse)) {
          basse = cherche(_plancher, basse, tientEnHauteur);
        }
      }

      return Text(
        texte,
        maxLines: maxLignes,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: base.copyWith(fontSize: basse),
      );
    },
  );
}
