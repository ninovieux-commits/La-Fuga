/// LA touche « chat » : la même en partie et partout ailleurs.
///
/// Nino, le volet des favoris en main : « la touche chat doit être
/// exactement la même que ingame, ni plus ni moins. » Exactement la même veut
/// dire LE MÊME WIDGET, pas deux dessins qui se ressemblent — c'est la seule
/// façon qu'ils ne divergent plus jamais. Le bandeau des parties et le volet
/// des favoris s'en servent tous les deux.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'fuga_button.dart';
import 'picto_touche.dart';

class ToucheChat extends StatelessWidget {
  const ToucheChat({super.key, required this.palette, required this.onPressed});

  final ThemePalette palette;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: T('Chat'),
    child: AspectRatio(
      aspectRatio: 1,
      child: Material(
        // Le gris de toutes les touches ; `kBarButtonDark` du bandeau n'est
        // que son autre nom.
        color: kGrisTouche,
        shape: formeDeTouche(BorderRadius.circular(S(20))),
        child: InkWell(
          borderRadius: BorderRadius.circular(S(20)),
          onTap: onPressed,
          child: Center(
            // LES DEUX BULLES, et non le mot « Chat ».
            //
            // L'AUTRE COULEUR DU THÈME, pour équilibrer la rangée du bandeau :
            // la pause et le retournement en clair, la boule et le chat en
            // foncé.
            child: PictoTouche(
              asset: 'assets/images/chat.webp',
              couleur: palette.fonce,
              secours: '…',
            ),
          ),
        ),
      ),
    ),
  );
}
