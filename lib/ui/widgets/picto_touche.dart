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

/// Un MOT sur une touche, traité comme un symbole.
///
/// Nino : « quand il n'y a pas de symbole mais des mots, tu mets quand même
/// le mot en couleur de thème sur fond gris médian avec le trait noir fin en
/// faisant comme si les lettres étaient des symboles. »
///
/// Le trait noir est le même qu'autour des dessins — [kTraitPicto] — mais il
/// s'obtient autrement : une lettre a un CONTOUR, qu'on peut tracer
/// directement (`PaintingStyle.stroke`), là où un pictogramme n'est qu'une
/// forme pleine qu'il faut dilater. Les deux textes sont superposés : le
/// trait dessous, les lettres pleines dessus.
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

  @override
  Widget build(BuildContext context) {
    // Le style tel que le `Text` l'aura vraiment : celui qu'on lui donne,
    // posé sur celui que l'arbre impose. Le contour doit être dessiné avec
    // EXACTEMENT la même police et la même taille, sans quoi il ne tombe pas
    // sur les lettres.
    final effectif = DefaultTextStyle.of(context).style.merge(style);
    return CustomPaint(
      // Un peintre peint DERRIÈRE son enfant : le contour passe donc sous
      // les lettres pleines, comme la copie dilatée sous un picto.
      painter: _ContourMot(
        texte: texte,
        style: effectif,
        maxLines: maxLines,
        echelle: MediaQuery.textScalerOf(context),
      ),
      child: Text(
        texte,
        textAlign: TextAlign.center,
        maxLines: maxLines,
        style: style.copyWith(color: couleur),
      ),
    );
  }
}

/// Le contour noir d'un mot : les mêmes lettres, tracées et non remplies.
///
/// Un `CustomPaint` plutôt qu'un second `Text` : le mot ne doit figurer
/// qu'UNE fois dans l'arbre, sinon chaque `find.text` du code d'essai en
/// trouve deux, et surtout un lecteur d'écran le dirait deux fois.
class _ContourMot extends CustomPainter {
  const _ContourMot({
    required this.texte,
    required this.style,
    required this.maxLines,
    required this.echelle,
  });

  final String texte;
  final TextStyle style;
  final int maxLines;
  final TextScaler echelle;

  @override
  void paint(Canvas canvas, Size size) {
    final peintre = TextPainter(
      text: TextSpan(
        text: texte,
        style: style.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = kTraitPicto
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFF000000),
        ),
      ),
      textAlign: TextAlign.center,
      maxLines: maxLines,
      textDirection: TextDirection.ltr,
      textScaler: echelle,
    )..layout(maxWidth: size.width);
    // La boîte est celle du `Text`, donc de la même hauteur à l'arrondi
    // près ; on recentre pour que le contour ne glisse pas d'un pixel.
    peintre.paint(canvas, Offset(0, (size.height - peintre.height) / 2));
  }

  @override
  bool shouldRepaint(_ContourMot vieux) =>
      vieux.texte != texte ||
      vieux.style != style ||
      vieux.maxLines != maxLines ||
      vieux.echelle != echelle;
}
