/// Le contenu `.nmc` d'une partie, copié et montré.
///
/// Kivy affiche le fichier dans une zone de texte qu'on sélectionne à la
/// main ; ici le presse-papiers fait le travail, et la popup reste pour ceux
/// qui veulent relire avant de coller.
///
/// Partagé par l'historique et par le lecteur : la même touche doit donner la
/// même chose des deux côtés.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/translations.dart';
import '../scale.dart';
import 'fuga_button.dart';

/// Met [content] dans le presse-papiers, puis le montre, sélectionnable.
Future<void> showNmcDialog(BuildContext context, String content) async {
  await Clipboard.setData(ClipboardData(text: content));
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: kFugaGrey,
      title: Text(
        T('Contenu .nmc'),
        style: const TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: SelectableText(
            content,
            style: TextStyle(color: Colors.white, fontSize: SF(13)),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(T('Fermer')),
        ),
      ],
    ),
  );
}

/// La POSITION affichée, au format `.fug`, copiée dans le presse-papier.
///
/// Le pendant de [showNmcDialog] pour l'autre format : l'un décrit une
/// partie, l'autre un plateau.
Future<void> showFugDialog(BuildContext context, String fug) async {
  await Clipboard.setData(ClipboardData(text: fug));
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: kFugaGrey,
      title: Text(
        T('Position .fug'),
        style: const TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: SelectableText(
            fug,
            style: TextStyle(
              color: Colors.white,
              fontSize: SF(14),
              // Huit lignes de sept caractères ne s'alignent qu'en chasse
              // fixe : c'est ce qui rend le plateau reconnaissable.
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(T('Fermer')),
        ),
      ],
    ),
  );
}
