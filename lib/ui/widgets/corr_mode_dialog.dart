/// Les deux choix d'un défi par correspondance : le mode, puis la couleur.
///
/// Jusqu'ici, un défi de correspondance prenait la position de départ du
/// MENU : standard, ou Random Fuga si l'interrupteur du menu était mis. On ne
/// pouvait pas défier quelqu'un en random sans basculer tout le menu, et on
/// pouvait partir en random sans l'avoir voulu.
///
/// Le mode se choisit maintenant au moment de défier, et la correspondance ne
/// dépend plus de l'état du menu.
library;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../i18n/translations.dart';
import '../scale.dart';
import 'fuga_button.dart';

/// D'où part une partie de correspondance.
enum CorrMode {
  /// La position de toujours.
  standard('standard'),

  /// Une des 3 500 positions tirées au sort, par son code.
  random('random'),

  /// Une position composée de toutes pièces, décrite en `.fug`.
  personnalise('personnalise');

  const CorrMode(this.wire);

  /// Ce que le serveur reçoit et renvoie.
  final String wire;

  static CorrMode fromWire(String s) => switch (s) {
    'random' => CorrMode.random,
    'personnalise' => CorrMode.personnalise,
    _ => CorrMode.standard,
  };

  /// Le nom à afficher sur un aperçu de défi.
  String get label => switch (this) {
    CorrMode.standard => T('Standard'),
    CorrMode.random => T('Random'),
    CorrMode.personnalise => T('Personnalisé'),
  };
}

/// La couleur demandée par le défieur. `null` = aléatoire.
///
/// Aléatoire veut dire que PERSONNE ne sait : le tirage n'a pas lieu au défi,
/// mais à son acceptation. Tant qu'il n'a pas eu lieu, il n'y a rien à cacher
/// — donc rien qui puisse fuir.
typedef CorrCouleur = Camp?;

/// « D'où part la partie ? » Trois touches, et rien d'autre.
Future<CorrMode?> askCorrMode(BuildContext context) => showDialog<CorrMode>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(T('Position de départ'), style: TextStyle(fontSize: SF(17))),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final mode in CorrMode.values) ...[
          SizedBox(
            width: double.infinity,
            child: FugaButton(
              text: mode.label,
              fontSize: SF(16),
              onPressed: () => Navigator.of(context).pop(mode),
            ),
          ),
          SizedBox(height: S(10)),
        ],
      ],
    ),
  ),
);

/// « Avec quelle couleur ? » — les mêmes touches que contre Deep Grey, plus
/// « Aléatoire ».
///
/// Renvoie `(camp: …)` avec un camp nul pour aléatoire, ou `null` si la popup
/// a été refermée sans choisir : il faut distinguer « aléatoire » de « rien ».
Future<({Camp? camp})?> askCorrCouleur(BuildContext context) =>
    showDialog<({Camp? camp})>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(T('Votre couleur'), style: TextStyle(fontSize: SF(17))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: FugaButton(
                    text: T('Blancs'),
                    color: const Color.fromRGBO(235, 235, 235, 1),
                    textColor: Colors.black,
                    fontSize: SF(16),
                    onPressed: () =>
                        Navigator.of(context).pop((camp: Camp.blanc)),
                  ),
                ),
                SizedBox(width: S(12)),
                Expanded(
                  child: FugaButton(
                    text: T('Noirs'),
                    color: const Color.fromRGBO(31, 31, 31, 1),
                    fontSize: SF(16),
                    onPressed: () =>
                        Navigator.of(context).pop((camp: Camp.noir)),
                  ),
                ),
              ],
            ),
            SizedBox(height: S(12)),
            SizedBox(
              width: double.infinity,
              child: FugaButton(
                text: T('Aléatoire'),
                fontSize: SF(16),
                onPressed: () => Navigator.of(context).pop((camp: null)),
              ),
            ),
            SizedBox(height: S(8)),
            Text(
              T(
                'Aléatoire : la couleur est tirée quand la partie démarre, et '
                'aucun des deux joueurs ne la connaît avant.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: SF(12)),
            ),
          ],
        ),
      ),
    );
