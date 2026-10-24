/// Le « Plus » du lecteur de partie : tout ce qu'on peut faire d'une partie
/// qu'on relit.
///
/// Nino : « les boutons "deep grey", "copier" et le bouton play doivent
/// disparaître. À la place, on met un bouton "plus" juste à droite du bouton
/// flip de plateau, qui ouvre un popup laissant 4 choix : copier la position
/// (fichier .fug), copier la partie (fichier .nmc), jouer contre deep-grey,
/// lire la partie. »
///
/// Trois touches larges tenaient dans le bandeau d'un téléphone, et c'était
/// déjà juste : la quatrième débordait. Derrière une seule touche, les quatre
/// gestes ont la place de dire ce qu'ils font, en toutes lettres et dans les
/// dix langues.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'fuga_button.dart';
import 'fuga_popup.dart';

/// Ce que le « Plus » du lecteur propose.
enum GestePlus { position, partie, deepGrey, lecture }

/// Ouvre le « Plus ». Rien ne se confirme : chaque geste est défaisable.
Future<void> ouvrirPlusLecteur(
  BuildContext context, {
  required ThemePalette palette,
  required VoidCallback onCopierPosition,
  required VoidCallback onCopierPartie,
  required VoidCallback onDeepGrey,
  required VoidCallback onLecture,

  /// Vraie quand la lecture automatique tourne : la touche l'arrête.
  bool enLecture = false,
}) async {
  Widget touche(String texte, GestePlus geste, {Color? couleur}) => FugaButton(
    text: texte,
    fontSize: SF(15),
    color: couleur ?? kFugaGrey,
    onPressed: () => Navigator.of(context).pop(geste),
  );

  final choix = await showFugaPopup<GestePlus>(
    context,
    widthFactor: 0.82,
    heightFactor: 0.62,
    dismissible: true,
    rows: [
      (0.20, popupText(T('Plus'), size: 17)),
      (kTouchRow, touche(T('Copier la position'), GestePlus.position)),
      (kTouchRow, touche(T('Copier la partie'), GestePlus.partie)),
      (
        kTouchRow,
        touche(
          T('Jouer contre Deep Grey'),
          GestePlus.deepGrey,
          couleur: const Color.fromRGBO(77, 77, 87, 1),
        ),
      ),
      (
        kTouchRow,
        touche(
          enLecture ? T('Arrêter la lecture') : T('Lire la partie'),
          GestePlus.lecture,
          couleur: palette.clair,
        ),
      ),
    ],
  );
  switch (choix) {
    case null:
      return;
    case GestePlus.position:
      onCopierPosition();
    case GestePlus.partie:
      onCopierPartie();
    case GestePlus.deepGrey:
      onDeepGrey();
    case GestePlus.lecture:
      onLecture();
  }
}
