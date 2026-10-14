/// Fond d'écran du thème, posé derrière une page.
///
/// Kivy ne le met que sur le menu (`_bg_stone`). Il se propage ici à toutes
/// les pages — **sauf la boîte de messages**, où une image derrière le texte
/// le rendrait illisible.
///
/// Les thèmes à fond clair (fleur, dragon) reçoivent le même voile blanc
/// qu'en Kivy, pour que les écritures restent lisibles.
library;

import 'package:flutter/material.dart';

import '../../state/settings.dart';
import '../../theme/theme_assets.dart';
import '../../theme/themes.dart';

/// À passer en `theme` pour n'afficher AUCUNE image de fond.
///
/// Trois états, et il en faut bien trois : `null` prend le mien, un nom prend
/// le sien, et celui-ci n'en prend aucun. La boîte de messages s'en sert tant
/// qu'elle ne connaît pas le fond de l'interlocuteur : afficher le mien en
/// attendant, c'est le faire remplacer une seconde plus tard, et Nino l'a vu
/// clignoter.
const String kSansFond = '';

/// Thèmes dont le fond est trop clair pour qu'on écrive dessus sans voile.
///
/// Le voile blanc est celui de Kivy. Il vaut partout où ce fond est montré —
/// la page entière, mais aussi la tranche qu'en prend le bandeau du profil —
/// et il décide de la couleur de l'encre : noire sur un fond voilé, blanche
/// ailleurs.
const Set<String> kThemesVoiles = {'fleur', 'dragon'};

/// L'encre lisible sur le fond de ce thème.
Color encreSurFond(String theme) =>
    kThemesVoiles.contains(theme) ? Colors.black : Colors.white;

class FugaBackground extends StatelessWidget {
  const FugaBackground({super.key, required this.child, this.theme});

  final Widget child;

  /// Le thème dont on prend le fond. Le sien par défaut.
  ///
  /// La boîte de messages passe celui de l'INTERLOCUTEUR : on entre chez lui,
  /// on voit son décor. [kSansFond] n'affiche aucune image.
  final String? theme;

  @override
  Widget build(BuildContext context) {
    final theme = this.theme ?? Settings.instance.themeAxes.menu;
    final background = imagesFor(theme)?.background;
    if (background == null) return child;

    return DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage(background),
          fit: BoxFit.cover,
        ),
      ),
      child: kThemesVoiles.contains(theme)
          ? Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
                child,
              ],
            )
          : child,
    );
  }
}

/// Couleur de fond d'une page, quand le thème n'a pas d'image.
Color pageBackground() => paletteOf(Settings.instance.themeAxes.menu).menu;

/// Page de l'application : la couleur du thème, son image de fond, et le
/// contenu par-dessus.
///
/// C'est le `Scaffold` de toutes les pages sauf la boîte de messages, qui
/// garde un fond uni pour que les messages restent lisibles.
class FugaScaffold extends StatelessWidget {
  const FugaScaffold({
    super.key,
    required this.body,
    this.color,
    this.bottomNavigationBar,
  });

  final Widget body;

  /// Couleur de fond, quand le thème n'a pas d'image. Par défaut celle du
  /// menu.
  final Color? color;

  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: color ?? pageBackground(),
    bottomNavigationBar: bottomNavigationBar,
    body: FugaBackground(child: body),
  );
}
