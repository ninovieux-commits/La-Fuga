/// Les couleurs de quelqu'un d'autre.
///
/// Quand on joue contre une personne, une partie de l'écran est à elle : son
/// bandeau porte son décor, ses bulles ses couleurs. Les deux écrans de
/// partie en ligne en avaient chacun leur copie — même lecture du cache, même
/// repli sur mon thème —, et une correction faite d'un côté restait à faire
/// de l'autre.
library;

import '../net/decors_connus.dart';
import '../state/settings.dart';
import '../theme/themes.dart';

/// La palette de [pseudo] : son thème à lui, le mien tant qu'on l'ignore.
///
/// Mon thème plutôt que rien : il faut bien des couleurs, et c'est le choix
/// qui ne fait clignoter aucun écran — le sien arrive, ou n'arrive pas, mais
/// il n'y a jamais d'instant sans couleur.
ThemePalette paletteDe(String pseudo) {
  final sien = DecorsConnus.known(pseudo);
  return paletteOf(
    (sien.isEmpty ? Settings.instance.themeAxes : ThemeAxes.parse(sien))
        .general,
  );
}
