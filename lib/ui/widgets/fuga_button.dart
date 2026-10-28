/// Bouton du menu — portage de `RoundButton` (main.py).
///
/// Rectangle arrondi plein, texte blanc gras centré. La couleur de fond dit
/// la fonction : clair du thème pour l'action principale, foncé pour le jeu
/// en ligne, gris pour le reste.
library;

import 'package:flutter/material.dart';

import '../scale.dart';
import 'picto_touche.dart';

/// Gris des boutons secondaires — `COL_BTN_GREY` de Kivy.
const Color kFugaGrey = Color.fromRGBO(89, 89, 89, 1);

/// Le gris de TOUTES les touches : pile à mi-chemin entre le noir et le
/// blanc.
///
/// Les deux couleurs d'un thème ne sont pas faites pour se faire contraste :
/// la claire est faite pour ressortir, la foncée pour servir de fond. Posées
/// en dessin, l'une s'effaçait sur le presque noir des touches du bandeau
/// fin, l'autre sur le gris du bandeau large. Nino : « utilise un gris qui
/// est pile à mi-chemin entre le noir et le blanc pour toutes les touches. »
/// Un même fond pour toutes, et les deux couleurs s'y posent de la même
/// façon.
///
/// « TOUTES » est à prendre au mot : les touches des deux bandeaux, les
/// flèches du bas, et les touches secondaires des popups, qui avaient un
/// gris à elles le temps d'une étape.
const Color kGrisTouche = Color.fromRGBO(128, 128, 128, 1);

/// Opacité d'une touche HORS SERVICE — le signe, partout dans l'application.
///
/// Nino : « effet pâlissant comme les autres touches. » C'est celui des
/// flèches du bandeau des coups depuis toujours ; les hachures l'ont remplacé
/// le temps d'un essai, et c'est lui qui reste. Une seule valeur, pour que
/// deux touches éteintes ne pâlissent jamais différemment.
const double kOpaciteEteinte = 0.35;

/// Le trait noir d'une touche — le MÊME que celui des symboles.
///
/// Nino, l'ayant vu sur aperçu : « je trouve ça joli en soi encadré », puis
/// « fais-le dans l'app, partout, pas que le menu ». Sur un décor à image —
/// les tourbillons de Deep Grey — les touches grises se dissolvaient dans le
/// fond : on devinait le texte, pas la touche. Le trait leur rend un bord.
const BorderSide kTraitDeTouche = BorderSide(
  color: Color(0xFF000000),
  width: kTraitPicto,
);

/// La forme d'une touche : son arrondi, avec le trait DEDANS.
///
/// Dedans, et c'est tout l'enjeu : `strokeAlignInside` — le défaut — pose le
/// trait à l'intérieur du bord existant au lieu de l'ajouter autour. La
/// silhouette et le rayon des coins ne bougent pas d'un pixel. Nino : « NE
/// CHANGE PAS LA FORME DES TOUCHES, AJOUTE SEULEMENT LE TRAIT NOIR ! »
ShapeBorder formeDeTouche(BorderRadius rayon) =>
    RoundedRectangleBorder(borderRadius: rayon, side: kTraitDeTouche);

/// Ce qui reste du FOND d'une touche éteinte.
///
/// Ce fond s'obtenait en mélangeant le gris de la touche à la couleur du
/// bandeau. C'était une transparence FEINTE, juste tant qu'il y avait un
/// bandeau derrière : en analyse, la touche d'annulation flotte sur le
/// décor, et elle y portait un carré aux couleurs d'un bandeau absent. Nino :
/// « la touche d'annulation de coup prend la couleur du bandeau lorsqu'elle
/// essaie d'imiter la transparence, alors qu'il n'y a pas le bandeau
/// derrière. Les touches inutilisables doivent toujours se mettre à la
/// couleur de ce qui est derrière. »
///
/// Une VRAIE transparence le fait d'elle-même, quel que soit le fond, et au
/// même poids qu'avant : quatre dixièmes, ce que laissait le mélange.
const double kFondEteint = 0.4;

/// Le fond d'une touche éteinte : le sien, rendu translucide.
Color fondEteint(Color fond) => fond.withValues(alpha: kFondEteint);

class FugaButton extends StatelessWidget {
  const FugaButton({
    super.key,
    this.text = '',
    required this.onPressed,
    this.color = kFugaGrey,
    this.textColor = Colors.white,
    this.height,
    this.fontSize,
    this.radius,
    this.enfant,
  });

  final String text;

  /// Un dessin À LA PLACE du texte, réduit de la même façon s'il est trop
  /// large. Les touches qui portent un symbole plutôt qu'un mot s'en
  /// servent.
  final Widget? enfant;
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
      shape: formeDeTouche(BorderRadius.circular(r)),
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
              child:
                  enfant ??
                  Text(
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
    return SizedBox(
      height: height ?? comfortableHeight,
      // Sans geste, la touche PÂLIT. Aucun appelant n'a à y penser : une
      // touche sans `onPressed` est une touche éteinte, et elle se voit.
      child: onPressed == null
          ? Opacity(opacity: kOpaciteEteinte, child: button)
          : button,
    );
  }
}
