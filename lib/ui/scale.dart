/// Mise à l'échelle des tailles — portage de `_scale_factor`, `S` et `SF`
/// (main.py).
///
/// Kivy dessine tout en pixels de référence : l'appli a été composée sur un
/// écran de 720 px de large, et chaque taille est ensuite multipliée par
/// `largeur_écran / 720`. Un bouton occupe donc TOUJOURS la même fraction de
/// l'écran, qu'on soit sur un petit téléphone ou sur une tablette.
///
/// Les polices suivent la même règle, et volontairement **pas** l'unité « sp »
/// : celle-ci dépend de la densité de l'écran et du réglage système, si bien
/// qu'un même texte occuperait des proportions différentes d'un appareil à
/// l'autre. `MediaQuery.withNoTextScaling`, posé à la racine, neutralise le
/// réglage système pour la même raison.
///
/// Flutter raisonne en pixels logiques là où Kivy raisonne en pixels physiques
/// — mais la formule est la même, parce que ce qui compte est la FRACTION de
/// la largeur : `S(44)` vaut toujours 44/720 de l'écran.
///
/// ## Rien n'est en pixels fixes
///
/// Toute taille de l'application est un pourcentage d'écran. Il y en a deux
/// familles, et choisir la mauvaise est la source d'erreur la plus fréquente :
///
/// | écriture        | signifie                    | pour quoi              |
/// |-----------------|-----------------------------|------------------------|
/// | `S(12)`         | 1,67 % de la **largeur**    | écarts, rayons, marges |
/// | `S(44)`         | 6,11 % de la **largeur**    | largeurs               |
/// | `SF(14)`        | 3,31 % de la largeur (x1,7) | polices                |
/// | `SH(0.06)`      | 6 % de la **hauteur**       | bandes du menu         |
/// | `touchHeight()` | 6 % de la **hauteur**       | TOUTE touche           |
///
/// La règle : ce qui se **vise avec le pouce**, ou se lit comme une bande, se
/// mesure sur la HAUTEUR ; ce qui accompagne le texte — écarts, rayons,
/// largeurs — se mesure sur la largeur, comme les polices, sinon les deux se
/// désaccordent.
///
/// Sur un téléphone les deux familles se ressemblent et l'erreur passe
/// inaperçue : la touche « Copier » de l'historique était en `S(90)`, soit
/// 49,1 là où une touche fait 51,1 — 4 % d'écart, invisible. Sur une tablette,
/// la même ligne donnait 104,2 contre 66,7 : **56 % trop épaisse**. C'est
/// pourquoi `touch_height_test.dart` mesure trois formes d'écran.
// Les noms `S` et `SF` sont ceux de main.py, et ils se lisent partout dans le
// code comme là-bas : on les garde tels quels.
// ignore_for_file: non_constant_identifier_names
library;

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

/// Largeur de l'écran de référence, celui sur lequel l'appli a été dessinée.
const double kRefWidth = 720;

/// Coefficient de confort de lecture, appliqué à TOUTES les polices —
/// `FONT_BOOST`.
const double kFontBoost = 1.70;

double? _factor;
double? _height;

/// Facteur courant : largeur de l'écran rapportée à la référence.
double get scaleFactor => _factor ?? _fromWindow();

/// Hauteur de l'écran, en pixels logiques — le `Window.height` de Kivy.
double get screenHeight => _height ?? _windowHeight();

/// Met une taille de référence à l'échelle de l'écran — `S`.
///
/// **C'est un POURCENTAGE DE LA LARGEUR**, pas un nombre de pixels : `S(12)`
/// vaut 12/720 de la largeur, soit 1,67 %, sur n'importe quel écran. Les
/// chiffres sont ceux de main.py, qu'on relit ligne à ligne ; le tableau en
/// tête de ce fichier donne la conversion.
double S(double value) => value * scaleFactor;

/// Met une taille de police à l'échelle de l'écran — `SF`.
double SF(double value) => value * scaleFactor * kFontBoost;

/// **Pourcentage de la HAUTEUR** — les `Window.height * f` du menu, où Kivy
/// proportionne à la hauteur plutôt qu'à la largeur. `SH(0.06)` = 6 % de la
/// hauteur, sur n'importe quel écran.
double SH(double fraction) => screenHeight * fraction;

/// Épaisseur d'une touche : la fraction de hauteur des grandes touches du
/// menu.
const double kTouchFraction = 0.06;

/// Hauteur à donner à une bande qui ne contient qu'une ligne de texte.
///
/// Les bandes du menu sont des fractions de l'écran, comme chez Kivy. Sur un
/// grand écran, la police grandit plus vite que la fraction et le texte se
/// retrouve coupé : la bande ne descend donc jamais sous la hauteur d'une
/// ligne.
double labelHeight(double fraction, double fontSize) {
  final line = SF(fontSize) * 1.45;
  final band = SH(fraction);
  return band > line ? band : line;
}

/// Épaisseur d'une touche, PARTOUT dans l'appli.
///
/// C'est celle des grandes touches du menu, et c'est la seule. Les popups et
/// les écrans secondaires se réglaient chacun sur une valeur de référence en
/// largeur — `S(52)`, `S(50)`, `S(48)`, `S(44)` — qui, sur un écran de
/// téléphone (plus haut que large), donnait des touches deux fois plus fines
/// que celles du menu. Une touche se vise avec le pouce : elle a la même
/// épaisseur d'un écran à l'autre, ou elle n'est pas la même touche.
double touchHeight() => SH(kTouchFraction);

/// Fixe l'échelle depuis la taille de l'écran, en pixels logiques.
void setScaleSize(Size size) {
  _factor = size.width <= 0 ? 1 : size.width / kRefWidth;
  _height = size.height <= 0 ? null : size.height;
}

/// Oublie l'échelle fixée : on repart de la fenêtre. Pour les tests.
void resetScale() {
  _factor = null;
  _height = null;
}

/// Facteur lu directement sur la fenêtre, tant que personne ne l'a fixé.
///
/// Les peintres et le code hors widget doivent pouvoir mesurer sans contexte ;
/// et un test qui affiche un widget isolé, sans [FugaScale] au-dessus, obtient
/// ainsi la même échelle que l'appli.
double _fromWindow() {
  final size = _windowSize();
  return (size == null || size.width <= 0) ? 1 : size.width / kRefWidth;
}

double _windowHeight() {
  final size = _windowSize();
  return (size == null || size.height <= 0) ? kRefWidth : size.height;
}

Size? _windowSize() {
  final view = PlatformDispatcher.instance.implicitView;
  if (view == null) return null;
  return view.physicalSize / view.devicePixelRatio;
}

/// Tient [scaleFactor] à jour. À poser une fois, à la racine de l'appli.
class FugaScale extends StatelessWidget {
  const FugaScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    setScaleSize(MediaQuery.sizeOf(context));
    return child;
  }
}

/// Met un thème de texte à l'échelle.
///
/// Les tailles que Material fournit par défaut (boîtes de dialogue, listes,
/// boutons plats) n'ont pas d'équivalent chez Kivy, où chaque label porte son
/// `SF`. Les faire suivre le même facteur revient au même : aucune taille de
/// texte ne reste figée.
TextTheme scaleTextTheme(TextTheme t, double factor) => TextTheme(
  displayLarge: _scaled(t.displayLarge, factor),
  displayMedium: _scaled(t.displayMedium, factor),
  displaySmall: _scaled(t.displaySmall, factor),
  headlineLarge: _scaled(t.headlineLarge, factor),
  headlineMedium: _scaled(t.headlineMedium, factor),
  headlineSmall: _scaled(t.headlineSmall, factor),
  titleLarge: _scaled(t.titleLarge, factor),
  titleMedium: _scaled(t.titleMedium, factor),
  titleSmall: _scaled(t.titleSmall, factor),
  bodyLarge: _scaled(t.bodyLarge, factor),
  bodyMedium: _scaled(t.bodyMedium, factor),
  bodySmall: _scaled(t.bodySmall, factor),
  labelLarge: _scaled(t.labelLarge, factor),
  labelMedium: _scaled(t.labelMedium, factor),
  labelSmall: _scaled(t.labelSmall, factor),
);

/// Une taille sans valeur reste sans valeur : Material la résoudra plus tard.
TextStyle? _scaled(TextStyle? style, double factor) =>
    (style == null || style.fontSize == null)
    ? style
    : style.copyWith(fontSize: style.fontSize! * factor);
