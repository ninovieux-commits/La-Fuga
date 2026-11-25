/// « En direct, ou par correspondance ? » — ce que demande désormais toute
/// touche « Défier ».
///
/// Nino : « tous les boutons défier doivent lancer un popup avec [direct] et
/// [correspondance] ce qui fait qu'on est plus obligés de passer par les
/// plateaux vides pour lancer une corresp, et qu'on peut en jouer contre des
/// gens qui ne sont pas dans les favoris en les recherchant simplement. »
///
/// Jusqu'ici les deux défis partaient d'endroits différents : le direct
/// d'une touche « Défier », la correspondance d'une case VIDE de la grille du
/// menu — et cette case ne proposait que les favoris. On ne pouvait donc pas
/// jouer par correspondance contre quelqu'un qu'on venait de chercher.
///
/// Les deux se demandent maintenant au même endroit, et la question est
/// toujours la même : qui, puis comment.
library;

import 'package:flutter/material.dart';

import '../../game/defi_relais.dart';
import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import 'fuga_button.dart';
import 'fuga_popup.dart';

/// Les deux façons de jouer contre quelqu'un.
enum TypeDeDefi { direct, correspondance }

/// Demande laquelle des deux. Nul si l'on referme sans choisir.
///
/// Le popup ne s'ouvre que depuis une touche « Défier », et cette touche est
/// éteinte quand aucun des deux défis n'est possible — voir
/// [DefiRelais.disponible]. Les deux gardes qui suivent ne sont donc que des
/// ceintures : on n'envoie pas un défi que personne ne mènera.
Future<TypeDeDefi?> demandeLeTypeDeDefi(BuildContext context, String pseudo) {
  final palette = paletteOf(Settings.instance.themeAxes.general);
  return showFugaPopup<TypeDeDefi>(
    context,
    widthFactor: 0.82,
    heightFactor: 0.5,
    dismissible: true,
    rows: [
      (
        0.3,
        popupText(
          T('Défier %s').replaceAll('%s', pseudo),
          size: 17,
          bold: true,
        ),
      ),
      (
        kTouchRow,
        FugaButton(
          text: T('En direct'),
          color: palette.clair,
          onPressed: DefiRelais.pret
              ? () => Navigator.of(context).pop(TypeDeDefi.direct)
              : null,
        ),
      ),
      (
        kTouchRow,
        FugaButton(
          text: T('Correspondance'),
          color: palette.fonce,
          onPressed: DefiRelais.pretCorresp
              ? () => Navigator.of(context).pop(TypeDeDefi.correspondance)
              : null,
        ),
      ),
      (
        kTouchRow,
        FugaButton(
          text: T('Fermer'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
    ],
  );
}

/// LA façon de défier depuis une touche : on demande, puis on lance.
///
/// Les deux défis sont menés par le menu, resté sous l'écran courant — voir
/// [DefiRelais] : lui seul tient le salon du direct et le service de
/// correspondance.
Future<void> lancerUnDefi(BuildContext context, String pseudo) async {
  final type = await demandeLeTypeDeDefi(context, pseudo);
  switch (type) {
    case null:
      return;
    case TypeDeDefi.direct:
      await DefiRelais.defier(pseudo);
    case TypeDeDefi.correspondance:
      await DefiRelais.defierParCorrespondance(pseudo);
  }
}
