/// Tout premier lancement — portage de `show_first_launch_language` et de la
/// séquence de démarrage de `FugaApp.on_start` (main.py).
///
/// On demande d'abord la langue — titre bilingue, puisqu'on ne sait pas encore
/// laquelle — puis on ouvre le tuto. Les deux ne se montrent qu'une fois.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../state/settings.dart';
import 'fuga_button.dart';
import '../scale.dart';

/// Demande la langue, en grille de deux colonnes comme en Kivy.
Future<void> askFirstLanguage(BuildContext context) async {
  final code = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      backgroundColor: kFugaGrey,
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Langue / Language',
              style: TextStyle(
                fontSize: SF(20),
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: S(12)),
            Flexible(
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.6,
                children: [
                  for (final entry in kLanguageLabels.entries)
                    FugaButton(
                      text: entry.value,
                      fontSize: SF(17),
                      height: double.infinity,
                      onPressed: () => Navigator.of(context).pop(entry.key),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  final settings = Settings.instance;
  if (code != null) await settings.setLanguage(code);
  await settings.markLanguageChosen();
}
