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
/// ## La couleur du contour se déduit de l'encre
///
/// Noir autour d'un mot clair, BLANC autour d'un mot sombre — la règle de
/// [contourDe], celle des symboles et des touches. `Texte` la suit tout seul
/// : il résout le style comme Flutter le fera — celui qu'il porte, fondu dans
/// celui qui descend du `DefaultTextStyle` — et lit l'encre qui en sort.
/// C'est pour cela qu'il fait ce travail ici et non chez l'appelant : au
/// moment d'écrire `Texte(...)`, on ne sait pas toujours de quelle couleur il
/// sortira.
///
/// Un style qui porte DÉJÀ des ombres est laissé tel quel : la gravure des
/// titres ([FugaHeader]) et les ombres portées restent ce qu'elles sont.
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

  /// L'encre par défaut, quand ni le style ni ce qui descend n'en nomment
  /// une : c'est celle de `Text` lui-même.
  static const Color _encreParDefaut = Color(0xFFFFFFFF);

  /// Le style final, cerné — tel que Flutter le calculera, en avance.
  TextStyle _cerne(BuildContext context) {
    final herite = DefaultTextStyle.of(context).style;
    final fusion = style == null
        ? herite
        : (style!.inherit ? herite.merge(style) : style!);
    if (fusion.shadows != null) return fusion;
    return fusion.copyWith(
      shadows: contourDesLettres(fusion.color ?? _encreParDefaut),
    );
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
