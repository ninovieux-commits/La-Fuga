/// Pause — portage d'`open_pause_popup` et `_confirm_cancel_match` (main.py).
///
/// La pause est visuelle : **le chrono du joueur au trait continue**, sinon
/// elle donnerait du temps de réflexion gratuit. Le popup le dit.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../screens/settings_screen.dart';
import 'fuga_button.dart';

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
  final left = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      backgroundColor: kFugaGrey,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            T('Pause'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            T("Le chrono du joueur au trait continue à s'écouler."),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: Color.fromRGBO(204, 204, 204, 1),
            ),
          ),
          const SizedBox(height: 12),
          FugaButton(
            text: T('Reprendre'),
            color: palette.clair,
            fontSize: 15,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          const SizedBox(height: 8),
          FugaButton(
            text: T('Réglages'),
            fontSize: 15,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                // Depuis une partie, Kivy n'offre ni la langue ni le
                // composeur : ils reconstruiraient l'écran sous les pieds du
                // joueur.
                builder: (_) => const SettingsScreen(fromMenu: false),
              ),
            ),
          ),
          if (quit != PauseQuit.none) ...[
            const SizedBox(height: 8),
            FugaButton(
              text: quit == PauseQuit.menu
                  ? T('Revenir au menu')
                  : T('Annuler le match'),
              color: palette.fonce,
              fontSize: 15,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ],
      ),
    ),
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

  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      backgroundColor: kFugaGrey,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            T('Annuler le match ?'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: Color.fromRGBO(217, 217, 217, 1),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FugaButton(
                  text: T('Continuer'),
                  fontSize: 15,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FugaButton(
                  text: (online || corr)
                      ? T('Abandonner')
                      : T('Annuler le match'),
                  color: palette.fonce,
                  fontSize: 15,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return confirmed == true;
}
