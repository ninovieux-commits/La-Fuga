/// Pause — portage d'`open_pause_popup` et `_confirm_cancel_match` (main.py).
///
/// La pause est visuelle : **le chrono du joueur au trait continue**, sinon
/// elle donnerait du temps de réflexion gratuit. Le popup le dit.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import '../screens/settings_screen.dart';
import 'fuga_button.dart';
import 'fuga_popup.dart';

/// Ce que la pause peut faire quitter, selon le mode de la partie.
enum PauseQuit {
  /// Partie locale ou contre Deep Grey : « Annuler le match ».
  match,

  /// Correspondance : on revient au menu, la partie continue sur le serveur.
  menu,

  /// En ligne : rien. On abandonne la partie par le [×] du panneau, et on
  /// quitte le match entre deux parties.
  none,
}

/// Ouvre la pause. Renvoie `true` si le joueur a décidé de quitter.
Future<bool> showPauseDialog(
  BuildContext context, {
  required ThemePalette palette,
  PauseQuit quit = PauseQuit.match,
}) async {
  // Kivy : `Popup(size_hint=(0.82, 0.52))`, un peu plus court quand il n'y a
  // que deux boutons — et des lignes à 14 %, 20 %, 18 % de sa hauteur.
  final left = await showFugaPopup<bool>(
    context,
    widthFactor: 0.82,
    heightFactor: quit == PauseQuit.none ? 0.44 : 0.52,
    rows: [
      (0.14, popupText(T('Pause'), size: 20, bold: true)),
      (
        0.20,
        popupText(
          T("Le chrono du joueur au trait continue à s'écouler."),
          size: 13,
          italic: true,
          color: const Color.fromRGBO(204, 204, 204, 1),
        ),
      ),
      (
        kTouchRow,
        FugaButton(
          text: T('Reprendre'),
          color: palette.clair,
          fontSize: SF(16),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      (
        kTouchRow,
        Builder(
          builder: (context) => FugaButton(
            text: T('Réglages'),
            fontSize: SF(16),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                // Depuis une partie, Kivy n'offre ni la langue ni le
                // composeur : ils reconstruiraient l'écran sous les pieds du
                // joueur.
                builder: (_) => const SettingsScreen(fromMenu: false),
              ),
            ),
          ),
        ),
      ),
      if (quit != PauseQuit.none)
        (
          kTouchRow,
          FugaButton(
            text: quit == PauseQuit.menu
                ? T('Revenir au menu')
                : T('Annuler le match'),
            color: palette.fonce,
            fontSize: SF(16),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ),
    ],
  );

  if (left != true || !context.mounted) return false;
  // La correspondance ne demande rien : la partie reste en cours sur le
  // serveur, on y reviendra.
  if (quit == PauseQuit.menu) return true;
  return confirmCancelMatch(context, palette: palette);
}

/// Confirmation avant d'annuler le match — `_confirm_cancel_match`.
Future<bool> confirmCancelMatch(
  BuildContext context, {
  required ThemePalette palette,
  bool online = false,
  bool corr = false,
}) async {
  final message = online
      ? T(
          'Abandonner compte comme une DÉFAITE.\nVotre adversaire gagne les points.',
        )
      : corr
      ? T(
          'Abandonner compte comme une défaite\ndans cette partie de correspondance.',
        )
      : T('La partie en cours sera perdue.');

  // Kivy : `Popup(size_hint=(0.82, 0.42))`, lignes à 30 %, 25 % et 32 %.
  final confirmed = await showFugaPopup<bool>(
    context,
    widthFactor: 0.82,
    heightFactor: 0.42,
    rows: [
      (0.30, popupText(T('Annuler le match ?'), size: 18, bold: true)),
      (
        0.25,
        popupText(
          message,
          size: 13,
          color: const Color.fromRGBO(217, 217, 217, 1),
        ),
      ),
      (
        kTouchRow,
        Row(
          children: [
            Expanded(
              child: FugaButton(
                text: T('Continuer'),
                fontSize: SF(16),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
            SizedBox(width: S(8)),
            Expanded(
              child: FugaButton(
                text: (online || corr)
                    ? T('Abandonner')
                    : T('Annuler le match'),
                color: palette.fonce,
                fontSize: SF(16),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        ),
      ),
    ],
  );
  return confirmed == true;
}
