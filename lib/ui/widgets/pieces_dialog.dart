/// Le choix d'une pièce à envoyer dans un message.
///
/// Nino : « je voudrais pouvoir envoyer les images des pièces par messages
/// comme si c'était des emojis (ils sont déjà tous listés dans le choix de
/// l'image de profil). On peut rajouter un bouton qui permet d'y accéder
/// juste au-dessus du texte saisi au-dessus du clavier (au milieu) uniquement
/// lorsque ce dernier est déployé. »
///
/// Les dix pièces du thème courant — cinq types, deux camps — dans l'ordre de
/// la galerie des photos de profil, qui les montre déjà ainsi.
library;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../pieces_emoji.dart';
import '../scale.dart';
import 'fuga_button.dart';
import 'fuga_popup.dart';
import 'profile_photo.dart';

/// Côté d'une pièce dans la grille : assez grand pour se viser au doigt.
double get kCotePieceChoix => touchHeight();

/// Ouvre la grille et rend le JETON de la pièce choisie, ou `null`.
///
/// TOUS LES THÈMES, et pas seulement celui qu'on porte. Nino : « ça doit
/// donner accès aux pièces de TOUS les thèmes, pas d'un seul. » C'est le même
/// catalogue que la galerie des photos de profil, dans le même ordre — le
/// sien d'abord, puisque c'est celui qu'il cherchera le plus souvent.
Future<String?> choisirPieceEmoji(
  BuildContext context, {
  required ThemePalette palette,
}) {
  final sien = Settings.instance.themeAxes.general;
  final themes = [sien, ...kThemeOrder.where((t) => t != sien)];

  Widget rangee(String theme, Camp camp) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (final type in kPiecesEnvoyables)
        Padding(
          padding: EdgeInsets.all(S(3)),
          child: Tooltip(
            message: type.wire,
            child: InkWell(
              onTap: () => Navigator.of(
                context,
              ).pop(jetonPiece(type, camp, theme: theme)),
              child: ProfilePhoto(
                photo:
                    '$theme|${type.wire}'
                    '${camp == Camp.noir ? '|${Camp.noir.wire}' : ''}',
                size: kCotePieceChoix,
              ),
            ),
          ),
        ),
    ],
  );

  return showFugaPopup<String>(
    context,
    widthFactor: 0.90,
    heightFactor: 0.72,
    dismissible: true,
    rows: [
      (0.14, popupText(T('Envoyer une pièce'), size: 17)),
      // LE CATALOGUE DÉFILE. Seize thèmes de dix pièces ne tiennent sur aucun
      // écran ; le popup s'arrête à son plafond et laisse glisser le reste.
      for (final theme in themes) ...[
        (
          0,
          popupText(
            kThemeLabels[theme] ?? theme,
            size: 12,
            color: const Color.fromRGBO(190, 190, 190, 1),
          ),
        ),
        (0, rangee(theme, Camp.blanc)),
        (0, rangee(theme, Camp.noir)),
      ],
      (
        kTouchRow,
        FugaButton(
          text: T('Fermer'),
          fontSize: SF(16),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
    ],
  );
}
