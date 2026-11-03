/// Le TAMPON : la date et les deux joueurs, posés sur l'image.
///
/// Nino : « en modifier, il faut ajouter un bouton [tampon] qui crée un texte
/// automatique comprenant la date et les noms des deux joueurs. […] Il doit y
/// avoir un rond blanc à côté d'un des noms et un rond noir à côté de
/// l'autre, avec un petit bouton pour inverser ces deux ronds. »
///
/// Les deux ronds disent qui tenait les Blancs et qui tenait les Noirs. Ce
/// sont de vrais ronds peints, et non des émojis : à cette taille un émoji
/// change de dessin d'un téléphone à l'autre, et le blanc y est rarement
/// blanc.
library;

import 'package:flutter/material.dart';

/// Ce que le tampon raconte : une date, deux noms, et qui avait les Blancs.
final class Tampon {
  const Tampon({
    required this.date,
    required this.gauche,
    required this.droite,
    this.blancAGauche = true,
  });

  /// Le jour, tel qu'il s'écrira. On le fige à la pose : une image qu'on
  /// modifie le lendemain garde la date de la partie, pas celle du jour.
  final DateTime date;

  final String gauche;
  final String droite;

  /// Le rond BLANC est-il du côté du nom de gauche ? Le petit bouton
  /// l'échange.
  final bool blancAGauche;

  Tampon echange() => Tampon(
    date: date,
    gauche: gauche,
    droite: droite,
    blancAGauche: !blancAGauche,
  );

  /// La date au format court, sans nom de mois : il changerait de langue
  /// selon le téléphone, et le tampon est posé sur une image qui voyage.
  String get dateEcrite =>
      '${_deux(date.day)}/${_deux(date.month)}/${date.year}';

  static String _deux(int v) => v.toString().padLeft(2, '0');
}

/// Le tampon dessiné : la date au-dessus, les deux noms et leurs ronds en
/// dessous.
class TamponPartie extends StatelessWidget {
  const TamponPartie({super.key, required this.tampon, required this.taille});

  final Tampon tampon;

  /// La hauteur des lettres. Tout le reste en découle : le tampon se
  /// redimensionne d'un seul nombre.
  final double taille;

  @override
  Widget build(BuildContext context) {
    final rond = taille * 0.78;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: taille * 0.5,
        vertical: taille * 0.3,
      ),
      decoration: BoxDecoration(
        // Un voile sombre : le tampon doit se lire sur une photo claire
        // comme sur une photo sombre.
        color: const Color(0xA6000000),
        borderRadius: BorderRadius.circular(taille * 0.4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tampon.dateEcrite,
            style: TextStyle(
              color: Colors.white,
              fontSize: taille * 0.8,
              fontWeight: FontWeight.bold,
              height: 1.1,
            ),
          ),
          SizedBox(height: taille * 0.2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _camp(tampon.gauche, blanc: tampon.blancAGauche, rond: rond),
              SizedBox(width: taille * 0.7),
              _camp(tampon.droite, blanc: !tampon.blancAGauche, rond: rond),
            ],
          ),
        ],
      ),
    );
  }

  /// Un nom et son rond. Le rond porte toujours un trait de l'autre couleur :
  /// sans lui, le noir disparaîtrait dans le voile sombre.
  Widget _camp(String nom, {required bool blanc, required double rond}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: rond,
        height: rond,
        decoration: BoxDecoration(
          color: blanc ? Colors.white : Colors.black,
          shape: BoxShape.circle,
          border: Border.all(
            color: blanc ? Colors.black : Colors.white,
            width: rond * 0.12,
          ),
        ),
      ),
      SizedBox(width: rond * 0.4),
      Text(
        nom,
        maxLines: 1,
        style: TextStyle(
          color: Colors.white,
          fontSize: taille,
          fontWeight: FontWeight.bold,
          height: 1.1,
        ),
      ),
    ],
  );
}
