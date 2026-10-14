/// L'étoile des favoris — une seule, partout où un nom s'écrit.
///
/// Nino : « il doit y avoir une étoile dans les infos de joueur s'il est
/// favori […] Il doit y avoir cette même étoile quand on est sur le profil
/// d'une personne », puis, en montrant la boîte de discussion, la fiche et le
/// lecteur de parties : « à ces endroits, l'étoile doit aussi apparaître
/// devant le nom. »
///
/// Elle vivait dans `player_panel.dart` ; quatre écrans la réclament, et
/// aucun d'eux n'a affaire aux pièces prises ni aux touches d'abandon.
library;

import 'package:flutter/material.dart';

/// Or de l'étoile des favoris — celui de l'étoile du menu.
const Color kEtoileFavori = Color(0xFFFFC928);

/// L'étoile EN TÊTE d'un texte, en FRAGMENT et non en rangée.
///
/// Une rangée « étoile + nom » déborde dès que la place manque : une icône ne
/// rétrécit pas, et sur un bandeau étroit — mesuré, seize pixels pour le nom
/// quand la photo a pris le reste — l'étoile seule n'y tenait plus, et
/// Flutter peignait la bande jaune du débordement.
///
/// En fragment, l'ellipse du texte s'occupe de tout. Et comme l'étoile est en
/// tête, c'est la fin du NOM qu'elle ronge, jamais l'étoile : « il est dans
/// mes favoris » survit à n'importe quel pseudo.
InlineSpan etoileSpan({required double taille}) => WidgetSpan(
  alignment: PlaceholderAlignment.middle,
  child: Padding(
    padding: EdgeInsets.only(right: taille * 0.25),
    child: Icon(Icons.star, size: taille, color: kEtoileFavori),
  ),
);

/// Un nom précédé de son étoile, quand il est dans mes favoris.
///
/// `taille` est celle du nom : l'étoile la suit, donc elle grandit avec les
/// titres et reste discrète dans les bandeaux, sans qu'aucun appelant ait à
/// choisir un nombre.
TextSpan nomEtoile(
  String nom, {
  required bool favori,
  required double taille,
}) => TextSpan(
  children: [
    if (favori) etoileSpan(taille: taille),
    TextSpan(text: nom),
  ],
);
