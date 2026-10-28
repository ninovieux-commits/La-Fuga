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

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Part de la touche qu'occupe le dessin — le reste est le carré qu'on voit.
const double kPartPicto = 0.58;

/// Épaisseur du trait noir qui détache le dessin du fond de la touche.
///
/// Nino : « mets un fin trait de tracé noir qui fait la séparation entre le
/// symbole et le fond de la touche, ça rendra tout plus lisible, et réglera
/// le souci avec le thème deepgrey. »
///
/// Il règle en effet le cas limite : deepgrey peint ses deux couleurs en
/// `RGB(128, 128, 128)`, c'est-à-dire exactement le gris des touches — son
/// dessin y était invisible, et c'est le trait qui le fait exister.
/// Le plus fin possible : Nino l'a vu trop épais au premier essai, à 1,6.
/// Un demi-pixel de référence donne un trait d'un pixel d'écran sur un
/// téléphone ordinaire — on ne peut pas descendre en dessous.
const double kTraitPicto = 0.5;

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
    widthFactor: kPartPicto,
    heightFactor: kPartPicto,
    // LE TRAIT NOIR EST LE MÊME DESSIN, ÉLARGI ET PEINT EN NOIR, posé
    // DERRIÈRE : ce qui dépasse tout autour fait le contour. Un pictogramme
    // n'est qu'une forme pleine, il n'a pas de tracé à épaissir ; c'est la
    // forme elle-même qu'on dilate.
    child: Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ui.ImageFilter.dilate(
            radiusX: kTraitPicto,
            radiusY: kTraitPicto,
          ),
          child: _dessin(Colors.black),
        ),
        _dessin(couleur),
      ],
    ),
  );
}
