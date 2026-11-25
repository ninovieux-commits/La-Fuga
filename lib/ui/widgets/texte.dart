/// TOUT TEXTE DE L'APPLICATION, et son contour.
///
/// Nino, devant une fiche de joueur : « pourquoi les textes ici n'ont pas
/// tous le contour noir ? Il faut vérifier chacune des parties de l'App et
/// mettre ce contour noir de partout. De partout. »
///
/// Le contour existait déjà — les touches le portent depuis « toutes les
/// écritures sur les boutons doivent avoir le contour comme en analyse » —
/// mais il fallait le demander, mot par mot, et tout ce qui n'était pas une
/// touche l'oubliait : les titres, les scores, les notices, les bulles.
///
/// Il ne se demande plus : `Texte` remplace `Text` dans toute l'interface, et
/// cerne ce qu'il écrit. Un essai de source (`contour_partout_test.dart`)
/// interdit `Text(` ailleurs, pour que la prochaine ligne écrite le porte
/// aussi.
///
/// ## BLANC, CERNÉ DE NOIR. Toujours.
///
/// Nino, après un premier tour où l'encre suivait son fond : « en fait disons
/// blanc à contour noir de partout. Absolument tous les textes doivent être
/// blanc à contour noir. Comme ça c'est réglé. »
///
/// C'est donc réglé ici, et une fois pour toutes : la couleur qu'un appelant
/// donne à son texte est IGNORÉE. Plus de gris de notice, plus de vert
/// « en ligne », plus de rouge d'erreur — le mot est blanc, et son contour
/// noir le tient sur n'importe quel fond, clair ou sombre.
///
/// Ce qui reste coloré n'est pas du texte mais un SIGNE, écrit avec une
/// police faute d'un dessin : l'étoile des favoris, le « + » d'une case
/// vide, le `*` qui dit une partie gagnée. Ceux-là passent `symbole: true`
/// et gardent la couleur qui les fait parler.
///
/// Un style qui porte DÉJÀ des ombres garde son relief : la gravure des
/// titres ([FugaHeader]) reste ce qu'elle est.
library;

import 'package:flutter/material.dart';

import 'picto_touche.dart';

class Texte extends StatelessWidget {
  const Texte(
    String this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
    this.strutStyle,
    this.symbole = false,
  }) : span = null;

  const Texte.rich(
    InlineSpan this.span, {
    super.key,
    this.style,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
    this.strutStyle,
    this.symbole = false,
  }) : data = null;

  final String? data;
  final InlineSpan? span;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;
  final StrutStyle? strutStyle;

  /// CE N'EST PAS UN MOT, mais un signe dont la couleur dit quelque chose :
  /// il garde la sienne. Tout le reste est blanc.
  final bool symbole;

  /// L'encre de TOUT texte de l'application.
  static const Color kEncre = Color(0xFFFFFFFF);

  /// Le style final — blanc, cerné de noir.
  TextStyle _cerne(BuildContext context) {
    final herite = DefaultTextStyle.of(context).style;
    final fusion = style == null
        ? herite
        : (style!.inherit ? herite.merge(style) : style!);
    final encre = symbole ? (fusion.color ?? kEncre) : kEncre;
    if (fusion.shadows != null) return fusion.copyWith(color: encre);
    return fusion.copyWith(color: encre, shadows: contourDesLettres(encre));
  }

  @override
  Widget build(BuildContext context) {
    final style = _cerne(context);
    return data != null
        ? Text(
            data!,
            style: style,
            textAlign: textAlign,
            textDirection: textDirection,
            locale: locale,
            softWrap: softWrap,
            overflow: overflow,
            textScaler: textScaler,
            maxLines: maxLines,
            semanticsLabel: semanticsLabel,
            textWidthBasis: textWidthBasis,
            textHeightBehavior: textHeightBehavior,
            selectionColor: selectionColor,
            strutStyle: strutStyle,
          )
        : Text.rich(
            span!,
            style: style,
            textAlign: textAlign,
            textDirection: textDirection,
            locale: locale,
            softWrap: softWrap,
            overflow: overflow,
            textScaler: textScaler,
            maxLines: maxLines,
            semanticsLabel: semanticsLabel,
            textWidthBasis: textWidthBasis,
            textHeightBehavior: textHeightBehavior,
            selectionColor: selectionColor,
            strutStyle: strutStyle,
          );
  }
}
