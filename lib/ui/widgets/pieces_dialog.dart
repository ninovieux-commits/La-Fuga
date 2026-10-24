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
Future<String?> choisirPieceEmoji(
  BuildContext context, {
  required ThemePalette palette,
}) {
  final theme = Settings.instance.themeAxes.general;

  return showFugaPopup<String>(
    context,
    widthFactor: 0.86,
    heightFactor: 0.62,
    dismissible: true,
    rows: [
      (0.18, popupText(T('Envoyer une pièce'), size: 17)),
      for (final camp in Camp.values)
        (
          0,
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final type in kPiecesEnvoyables)
                Padding(
                  padding: EdgeInsets.all(S(4)),
                  child: Tooltip(
                    message: type.wire,
                    child: InkWell(
                      onTap: () =>
                          Navigator.of(context).pop(jetonPiece(type, camp)),
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
          ),
        ),
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
