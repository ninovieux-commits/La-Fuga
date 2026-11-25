/// LE THÈME DE L'APPLICATION, en un seul endroit.
///
/// Il vivait dans `main.dart`, donc nulle part ailleurs : un aperçu ou un
/// essai qui montait un écran sous un `MaterialApp` nu le dessinait avec les
/// couleurs d'usine de Material, et ne pouvait rien prouver de ce qu'on voit
/// vraiment. Ils s'en servent maintenant tous.
library;

import 'package:flutter/material.dart';

import 'scale.dart';
import 'widgets/fuga_button.dart';
import 'widgets/picto_touche.dart';

/// Épaisseur minimale d'une touche Material : celle de toutes les autres.
/// La largeur reste libre — c'est bien l'épaisseur qui doit être la même.
Size _tailleDeTouche() => Size(0, touchHeight());

/// Le contour noir posé sur TOUS les styles du thème.
///
/// Nino : « il faut vérifier chacune des parties de l'App et mettre ce
/// contour noir de partout. De partout. » [Texte] s'occupe de ce que
/// l'application écrit elle-même ; restent les textes que Material tire du
/// thème sans passer par lui — l'invite d'un champ de saisie, ce qu'on y
/// tape, le libellé d'une touche plate. Ils fondent le style du thème avec
/// le leur, et un style sans ombres garde celles du thème : le contour leur
/// vient donc d'ici.
///
/// Noir : les écrans de l'application sont sombres et leurs lettres claires.
/// Un mot sombre, lui, porte son propre contour — voir [contourDesLettres].
TextTheme _cerne(TextTheme t) {
  TextStyle? c(TextStyle? s) =>
      s?.copyWith(shadows: contourDesLettres(const Color(0xFFFFFFFF)));
  return TextTheme(
    displayLarge: c(t.displayLarge),
    displayMedium: c(t.displayMedium),
    displaySmall: c(t.displaySmall),
    headlineLarge: c(t.headlineLarge),
    headlineMedium: c(t.headlineMedium),
    headlineSmall: c(t.headlineSmall),
    titleLarge: c(t.titleLarge),
    titleMedium: c(t.titleMedium),
    titleSmall: c(t.titleSmall),
    bodyLarge: c(t.bodyLarge),
    bodyMedium: c(t.bodyMedium),
    bodySmall: c(t.bodySmall),
    labelLarge: c(t.labelLarge),
    labelMedium: c(t.labelMedium),
    labelSmall: c(t.labelSmall),
  );
}

ThemeData themeFuga() {
  final base = ThemeData(
    brightness: Brightness.dark,
    fontFamily: 'NotoSansCJK',
    useMaterial3: true,
  );

  return base.copyWith(
    textTheme: _cerne(scaleTextTheme(base.textTheme, scaleFactor * kFontBoost)),
    primaryTextTheme: _cerne(
      scaleTextTheme(base.primaryTextTheme, scaleFactor * kFontBoost),
    ),
    // Une touche a la même épaisseur partout, y compris celles que
    // Material fournit lui-même — les actions d'une boîte de dialogue,
    // les touches plates d'un micromenu. Sans cela, elles gardaient la
    // hauteur minimale de Material, deux fois plus fine que les touches
    // du menu.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: _tailleDeTouche()),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(minimumSize: _tailleDeTouche()),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: _tailleDeTouche()),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: _tailleDeTouche()),
    ),
    // LE TRAIT NOIR FAIT LE TOUR DE CHAQUE POPUP. Nino : « pour chaque
    // popup je veux le trait noir qui fait le tour du popup stp. »
    //
    // Posé ici, dans le thème, et non sur les vingt-neuf boîtes de
    // dialogue une par une : celles qu'on écrira demain l'auront aussi,
    // et aucune ne peut l'oublier.
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(S(28)),
        side: kTraitDeTouche,
      ),
      // ET LE GRIS DE L'APPLICATION, avec des lettres blanches.
      //
      // Nino, devant la fiche d'un joueur : « pourquoi les textes ici
      // n'ont pas tous le contour noir ? » Un contour se déduit de son
      // encre — noir autour d'un mot clair, blanc autour d'un mot sombre
      // (voir [contourDe]) —, et ces boîtes-là étaient les seules de
      // l'application à écrire NOIR SUR BLANC : leur contour était blanc
      // sur blanc, c'est-à-dire rien. Elles gardaient la couleur d'usine
      // de Material, que personne n'avait choisie.
      //
      // Elles prennent donc le gris des popups maison, et leurs lettres
      // le blanc de partout ailleurs. Ici, dans le thème, et non sur les
      // vingt-neuf boîtes une par une.
      //
      // Les deux styles PARTENT DU THÈME : un `TextStyle` nu n'a pas de
      // police, et ces deux-là décident de tout ce qui s'écrit dans une
      // boîte de dialogue — son titre et son corps. Nus, ils tombaient sur
      // la police par défaut au lieu de celle de l'application.
      backgroundColor: kFugaGrey,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: Colors.white,
        fontSize: SF(18),
        fontWeight: FontWeight.bold,
      ),
      contentTextStyle: base.textTheme.bodyMedium?.copyWith(
        color: Colors.white,
        fontSize: SF(15),
      ),
    ),
  );
}
