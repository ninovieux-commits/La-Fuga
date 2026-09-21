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
// Les noms `S` et `SF` sont ceux de main.py, et ils se lisent partout dans le
// code comme là-bas : on les garde tels quels.
// ignore_for_file: non_constant_identifier_names
library;

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';

/// Largeur de l'écran de référence, celui sur lequel l'appli a été dessinée.
const double kRefWidth = 720;

/// Coefficient de confort de lecture, appliqué à TOUTES les polices —
/// `FONT_BOOST`.
const double kFontBoost = 1.70;

double? _factor;

/// Facteur courant : largeur de l'écran rapportée à la référence.
double get scaleFactor => _factor ?? _fromWindow();

/// Met une taille de référence à l'échelle de l'écran — `S`.
double S(double value) => value * scaleFactor;

/// Met une taille de police à l'échelle de l'écran — `SF`.
double SF(double value) => value * scaleFactor * kFontBoost;

/// Fixe le facteur depuis la largeur, en pixels logiques.
void setScaleWidth(double width) =>
    _factor = width <= 0 ? 1 : width / kRefWidth;

/// Oublie le facteur fixé : on repart de la fenêtre. Pour les tests.
void resetScale() => _factor = null;

/// Facteur lu directement sur la fenêtre, tant que personne ne l'a fixé.
///
/// Les peintres et le code hors widget doivent pouvoir mesurer sans contexte ;
/// et un test qui affiche un widget isolé, sans [FugaScale] au-dessus, obtient
/// ainsi la même échelle que l'appli.
double _fromWindow() {
  final view = PlatformDispatcher.instance.implicitView;
  if (view == null) return 1;
  final width = view.physicalSize.width / view.devicePixelRatio;
  return width <= 0 ? 1 : width / kRefWidth;
}

/// Tient [scaleFactor] à jour. À poser une fois, à la racine de l'appli.
class FugaScale extends StatelessWidget {
  const FugaScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    setScaleWidth(MediaQuery.sizeOf(context).width);
    return child;
  }
}
