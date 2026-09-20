/// « Jouer contre Deep Grey depuis cette position » — portage de
/// `_open_dg_from_position` et `start_vs_ai_from_position` (main.py).
///
/// Le joueur choisit SON camp ; le camp au trait, lui, ne bouge pas. Choisir
/// la couleur qui n'est pas au trait fait donc jouer Deep Grey en premier.
library;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../i18n/translations.dart';
import 'fuga_button.dart';

/// Renvoie le camp choisi par le joueur, ou `null` s'il a refermé la popup.
Future<Camp?> askDeepGreyCamp(BuildContext context) => showDialog<Camp>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Deep Grey'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          T('Jouer contre Deep Grey depuis cette position.\n') +
              T('Choisissez votre camp :'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FugaButton(
                text: T('Blancs'),
                color: const Color.fromRGBO(235, 235, 235, 1),
                textColor: Colors.black,
                fontSize: 16,
                onPressed: () => Navigator.of(context).pop(Camp.blanc),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FugaButton(
                text: T('Noirs'),
                color: const Color.fromRGBO(31, 31, 31, 1),
                fontSize: 16,
                onPressed: () => Navigator.of(context).pop(Camp.noir),
              ),
            ),
          ],
        ),
      ],
    ),
  ),
);
