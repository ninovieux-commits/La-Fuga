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

/// Découpe une liste en paires, pour une grille de deux colonnes.
List<List<T>> _byTwo<T>(List<T> items) => [
  for (var i = 0; i < items.length; i += 2)
    items.sublist(i, (i + 2).clamp(0, items.length)),
];

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
            // Deux colonnes comme en Kivy, mais des touches à l'épaisseur
            // des autres : une grille à rapport fixe leur imposait la sienne.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final pair in _byTwo(kLanguageLabels.entries.toList()))
                      Padding(
                        padding: EdgeInsets.only(bottom: S(8)),
                        child: Row(
                          children: [
                            for (var i = 0; i < 2; i++) ...[
                              if (i > 0) SizedBox(width: S(8)),
                              Expanded(
                                child: i < pair.length
                                    ? FugaButton(
                                        text: pair[i].value,
                                        fontSize: SF(17),
                                        onPressed: () => Navigator.of(
                                          context,
                                        ).pop(pair[i].key),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
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
