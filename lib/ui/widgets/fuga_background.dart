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

class FugaBackground extends StatelessWidget {
  const FugaBackground({super.key, required this.child});

  final Widget child;

  /// Thèmes dont le fond est trop clair pour qu'on écrive dessus sans voile.
  static const Set<String> _veiled = {'fleur', 'dragon'};

  @override
  Widget build(BuildContext context) {
    final theme = Settings.instance.themeAxes.menu;
    final background = imagesFor(theme)?.background;
    if (background == null) return child;

    return DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage(background),
          fit: BoxFit.cover,
        ),
      ),
      child: _veiled.contains(theme)
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
