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

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Part de la touche qu'occupe le dessin — le reste est le carré qu'on voit.
///
/// Deux tiers : le dessin doit remplir la touche sans la manger. Nino l'a
/// d'abord vu à 0,58, trop timide — « les symboles peuvent être un peu plus
/// grands dans leurs touches » — et le carré gris doit rester visible tout
/// autour, sans quoi la touche n'a plus de forme.
const double kPartPicto = 0.66;

/// Épaisseur du trait noir qui détache le dessin du fond de la touche.
///
/// Nino : « mets un fin trait de tracé noir qui fait la séparation entre le
/// symbole et le fond de la touche, ça rendra tout plus lisible, et réglera
/// le souci avec le thème deepgrey. »
///
/// Il règle en effet le cas limite : deepgrey peint ses deux couleurs en
/// `RGB(128, 128, 128)`, c'est-à-dire exactement le gris des touches — son
/// dessin y était invisible, et c'est le trait qui le fait exister.
/// Quatre essais ont réglé ce nombre : 1,6 d'abord, « trop épais » ; puis
/// 0,5, « le plus fin possible », qui était le plancher — un demi-pixel de
/// référence donne un trait d'un pixel d'écran sur un téléphone ordinaire, et
/// on ne descend pas en dessous ; puis 0,8, « finalement le trait noir un peu
/// plus épais » ; et enfin 1,15.
///
/// Ce dernier saut n'est pas un goût qui change, c'est une mesure. Le carré
/// d'avant avançait de 0,8 sur les côtés, mais de 0,8 × √2 ≈ 1,13 dans les
/// coins : un bord en biais — et un chevron n'est fait que de biais — portait
/// donc 1,13, pas 0,8. En passant au rond, qui avance pareil partout, le
/// trait se mit à maigrir sur ces bords-là. Nino : « on a perdu de
/// l'épaisseur comparé à avant. » On reprend donc le MAXIMUM de l'ancien,
/// désormais servi partout.
const double kTraitPicto = 1.15;

/// Combien de copies forment la couronne qui fait le contour.
///
/// Douze : l'écart entre le cercle vrai et le douzaine-gone qu'elles
/// dessinent vaut 3 % du trait, soit trois centièmes de pixel. Personne ne
/// peut le voir, et chaque copie de plus est un dessin de plus à chaque
/// image.
const int kCopiesDuBord = 12;

/// En dessous de cette luminance, une couleur EST le noir.
///
/// La couleur la plus sombre qu'un thème donne à ses accents est le violet
/// de Spatial, rgb(76, 26, 128), qui pèse 0,038 : le seuil est posé bien en
/// dessous, pour qu'aucun thème existant ne bascule par accident. Il laisse
/// toutefois passer un noir ADOUCI — jusqu'à rgb(40, 40, 40) environ —, au
/// cas où le noir franc se révélerait trop dur à l'usage.
const double kSeuilDuNoir = 0.02;

/// Cette couleur est-elle le noir ?
bool estNoire(Color couleur) => couleur.computeLuminance() < kSeuilDuNoir;

/// Le contour de ce qui est dessiné en [encre] : noir, sauf sur du noir.
///
/// Nino : « à chaque fois que quelque chose prend la couleur noire, il doit
/// prendre les contours blancs. » Le contour existe pour détacher un dessin
/// de son fond ; peint de la couleur du dessin lui-même, il ne détache plus
/// rien. Le thème Deep Grey donne le noir à sa couleur 2 — un symbole, un
/// mot, une zone qui la prennent disparaissaient donc avec leur cerne.
///
/// La règle se lit sur la COULEUR, pas sur le nom du thème : un thème
/// composé à la main qui tomberait sur le noir est soigné du même coup.
Color contourDe(Color encre) =>
    estNoire(encre) ? const Color(0xFFFFFFFF) : const Color(0xFF000000);

class PictoTouche extends StatelessWidget {
  const PictoTouche({
    super.key,
    required this.asset,
    required this.couleur,
    this.secours = '?',
    this.part = kPartPicto,
  });

  /// Le fichier : blanc sur fond transparent, teinté ici par le thème, comme
  /// les instruments des réglages.
  final String asset;

  final Color couleur;

  /// Ce qui s'affiche si le dessin manque : une touche sans rien dessus n'est
  /// plus une touche.
  final String secours;

  /// La part de la touche qu'occupe le dessin. [kPartPicto] partout, sauf là
  /// où un symbole demande à se voir davantage — l'enveloppe de la boîte de
  /// messages, par exemple, dont Nino a voulu qu'elle soit « un peu plus
  /// grande, ×1,2 ».
  final double part;

  /// Le dessin, teinté de [teinte].
  Widget _dessin(Color teinte) => Image.asset(
    asset,
    color: teinte,
    fit: BoxFit.contain,
    errorBuilder: (context, error, stack) => FittedBox(
      child: Text(
        secours,
        style: TextStyle(color: teinte, fontWeight: FontWeight.bold),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    widthFactor: part,
    heightFactor: part,
    // LE TRAIT NOIR EST LE MÊME DESSIN, ÉLARGI ET PEINT EN NOIR, posé
    // DERRIÈRE : ce qui dépasse tout autour fait le contour. Un pictogramme
    // n'est qu'une forme pleine, il n'a pas de tracé à épaissir ; c'est la
    // forme elle-même qu'on élargit.
    //
    // ON L'ÉLARGIT EN ROND, ET C'EST TOUTE LA DIFFÉRENCE.
    //
    // `ImageFilter.dilate` élargit avec un CARRÉ : chaque point de la forme
    // devient un petit carré. Là où la forme pointe — la pointe d'un chevron,
    // l'angle d'une flèche — le contour reprenait le haut plat de ce carré.
    // Nino, en entourant la pointe : « on voit bien que le contour noir fait
    // plat. J'aimerais que ça reproduise fidèlement les formes des
    // angles/arrondis. »
    //
    // Il n'existe pas de dilatation RONDE toute faite. On en fabrique une,
    // et de la façon la plus simple qui soit : on pose la forme noire
    // [kCopiesDuBord] fois, en couronne, à [kTraitPicto] du centre. Leur
    // réunion est la forme élargie d'un disque — donc à distance CONSTANTE
    // du bord, partout, pointes comprises.
    //
    // On a d'abord essayé un flou qu'on recoupait net : rond, lui aussi, mais
    // seulement APPROCHÉ. Le flou dépend de la matière qu'il a autour, et le
    // trait maigrissait au bout des branches. Nino : « c'est mieux mais
    // imparfait, le trait noir devient plus fin par endroits. » Une réunion
    // de copies, elle, ne se discute pas.
    child: Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < kCopiesDuBord; i++)
          Transform.translate(
            offset: Offset(
              kTraitPicto * math.cos(2 * math.pi * i / kCopiesDuBord),
              kTraitPicto * math.sin(2 * math.pi * i / kCopiesDuBord),
            ),
            child: _dessin(contourDe(couleur)),
          ),
        _dessin(couleur),
      ],
    ),
  );
}

/// Un MOT sur une touche, traité comme un symbole.
///
/// Nino : « quand il n'y a pas de symbole mais des mots, tu mets quand même
/// le mot en couleur de thème sur fond gris médian avec le trait noir fin en
/// faisant comme si les lettres étaient des symboles. »
///
/// ## Le contour est fait des MÊMES lettres, posées en couronne
///
/// Exactement comme pour un dessin : [kCopiesDuBord] copies noires du mot, à
/// [kTraitPicto] du centre, et le mot plein par-dessus. Ce qui dépasse tout
/// autour fait le contour, à distance constante du bord.
///
/// Elles sont posées en OMBRES du texte lui-même, sans flou : le moteur les
/// dessine dans la même passe que les lettres, et surtout À LA MÊME PLACE,
/// puisque c'est le même texte.
///
/// ## Pourquoi ce n'est plus un tracé
///
/// Le contour s'obtenait en RETRAÇANT le mot avec un `TextPainter` à part,
/// peint derrière. Un tracé mesure plus large et plus haut que le même texte
/// plein : le peintre se centrait donc sur une autre boîte que les lettres,
/// et le contour glissait. Sur les mélos du classement, écrits sans rien
/// autour qui les recadre, le décalage atteignait trois points et les
/// chiffres paraissaient en relief. Nino : « je ne veux pas que les mélos
/// dans le classement soient en perspective. »
///
/// Une ombre, elle, part du même texte, de la même boîte, de la même ligne :
/// il n'y a plus de seconde mesure, donc plus rien à faire coïncider.
///
/// ## Et l'épaisseur n'est plus doublée
///
/// Un tracé est CENTRÉ sur le contour de la lettre : la moitié partait en
/// dedans, recouverte par les lettres pleines, et il fallait le doubler pour
/// qu'il se voie autant qu'autour d'un dessin. Une copie décalée, elle, ne
/// dépasse que par dehors — c'est [kTraitPicto] tout rond, le même nombre
/// que pour les symboles.
class MotTouche extends StatelessWidget {
  const MotTouche({
    super.key,
    required this.texte,
    required this.couleur,
    required this.style,
    this.maxLines = 1,
  });

  final String texte;
  final Color couleur;

  /// Taille et graisse ; la couleur vient de [couleur].
  final TextStyle style;

  final int maxLines;

  /// La couronne de copies, en ombres sans flou.
  ///
  /// Noires autour d'un mot clair, BLANCHES autour d'un mot noir — voir
  /// [contourDe]. Nino : « les écritures aussi. »
  static List<Shadow> contourDesLettres(Color encre) => [
    for (var i = 0; i < kCopiesDuBord; i++)
      Shadow(
        color: contourDe(encre),
        offset: Offset(
          kTraitPicto * math.cos(2 * math.pi * i / kCopiesDuBord),
          kTraitPicto * math.sin(2 * math.pi * i / kCopiesDuBord),
        ),
      ),
  ];

  @override
  Widget build(BuildContext context) => Text(
    texte,
    textAlign: TextAlign.center,
    maxLines: maxLines,
    style: style.copyWith(color: couleur, shadows: contourDesLettres(couleur)),
  );
}
