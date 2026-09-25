/// Popups de fin de partie — portage de `_popup_finish`, `_popup_continue`
/// et `_popup_continue_online` (main.py).
///
/// Kivy n'a pas de barre d'action sous le plateau : la suite d'un match et le
/// retour au menu passent par ces popups, et par la touche « Retour au menu »
/// que la fin de partie fait apparaître dans le bandeau.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import 'fuga_button.dart';
import '../scale.dart';

/// Fin de partie (ou de match). Le popup se ferme d'une tape à côté : on peut
/// vouloir regarder la position finale.
Future<void> showFinishDialog(
  BuildContext context, {
  required ThemePalette palette,
  required String title,
  required String body,
  String? winner,
  String? meloLine,
  required VoidCallback onMenu,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    backgroundColor: kFugaGrey,
    title: Text(title, style: const TextStyle(color: Colors.white)),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: SF(14), color: Colors.white),
        ),
        SizedBox(height: S(10)),
        Text(
          winner == null
              ? T('Match nul')
              : T('Victoire de {name} !').replaceAll('{name}', winner),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: SF(18),
            fontWeight: FontWeight.bold,
            color: winner == null
                ? const Color.fromRGBO(51, 51, 51, 1)
                : palette.clair,
          ),
        ),
        if (meloLine != null) ...[
          SizedBox(height: S(8)),
          Text(
            meloLine,
            style: TextStyle(
              fontSize: SF(15),
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
        SizedBox(height: S(12)),
        FugaButton(
          text: T('Retour au menu'),
          color: palette.fonce,
          fontSize: SF(16),
          onPressed: () {
            Navigator.of(context).pop();
            onMenu();
          },
        ),
      ],
    ),
  ),
);

/// Le match continue : on annonce qui prendra les Blancs, et on enchaîne.
/// Pas de fermeture à côté — il faut choisir.
Future<void> showContinueDialog(
  BuildContext context, {
  required ThemePalette palette,
  required String title,
  required String body,
  required String nextFirstBlanc,
  required VoidCallback onNext,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) => AlertDialog(
    backgroundColor: kFugaGrey,
    title: Text(title, style: const TextStyle(color: Colors.white)),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: SF(14), color: Colors.white),
        ),
        SizedBox(height: S(8)),
        Text(
          T(
            'Prochaine partie : {name} joue les Blancs',
          ).replaceAll('{name}', nextFirstBlanc),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: SF(12),
            fontStyle: FontStyle.italic,
            color: const Color.fromRGBO(204, 204, 204, 1),
          ),
        ),
        SizedBox(height: S(12)),
        FugaButton(
          text: T('Partie suivante'),
          color: palette.clair,
          fontSize: SF(16),
          onPressed: () {
            Navigator.of(context).pop();
            onNext();
          },
        ),
      ],
    ),
  ),
);

/// Le match en ligne continue. On signale au serveur qu'on est prêt, puis on
/// attend l'adversaire — c'est lui l'arbitre, pas le client.
Future<void> showOnlineContinueDialog(
  BuildContext context, {
  required ThemePalette palette,
  required String title,
  required String body,
  required bool readySent,
  required VoidCallback onReady,
  required VoidCallback onQuit,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) => StatefulBuilder(
    builder: (context, setLocal) {
      var ready = readySent;
      return AlertDialog(
        backgroundColor: kFugaGrey,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: SF(14), color: Colors.white),
            ),
            SizedBox(height: S(8)),
            Text(
              ready
                  ? T("En attente de l'adversaire…")
                  : T(
                      'Clique sur « Partie suivante » pour continuer le match.',
                    ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: SF(12),
                fontStyle: FontStyle.italic,
                color: const Color.fromRGBO(217, 217, 217, 1),
              ),
            ),
            SizedBox(height: S(12)),
            FugaButton(
              text: ready
                  ? T("En attente de l'adversaire…")
                  : T('Partie suivante'),
              color: palette.clair,
              fontSize: SF(16),
              onPressed: ready
                  ? null
                  : () {
                      setLocal(() => ready = true);
                      onReady();
                    },
            ),
            SizedBox(height: S(8)),
            FugaButton(
              text: T('Quitter le match'),
              fontSize: SF(14),
              onPressed: () {
                Navigator.of(context).pop();
                onQuit();
              },
            ),
          ],
        ),
      );
    },
  ),
);
