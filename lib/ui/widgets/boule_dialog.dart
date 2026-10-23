/// La boule de cristal : analyser, ou préparer ses coups.
///
/// Nino : « analyse et pré-coups doivent être réunis sur ce bouton, et quand
/// on clique dessus ça fait apparaître un popup qui demande si on veut aller
/// en analyse ou en pré-coups. »
///
/// ## Pourquoi les réunir
///
/// Les deux regardent DEVANT : l'une explore la position, l'autre prépare la
/// réponse. Elles n'avaient pas de raison d'occuper deux touches dans un
/// bandeau qui n'en a la place que pour quelques-unes.
///
/// Et elles réglent du même coup un défaut que Nino signale : « quand le
/// bouton pré-coups disparaît car c'est mon tour de jouer, les autres boutons
/// se décalent vers la gauche ». Une touche qui va et vient déplace ses
/// voisines ; la boule, elle, est toujours là. C'est à l'INTÉRIEUR du popup
/// que « Pré-coups » pâlit quand ce n'est pas le moment.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'fuga_button.dart';
import 'fuga_popup.dart';

/// Ce que la boule propose.
enum GesteBoule { analyse, precoups }

/// Ouvre la boule. Rien ne se confirme : on va quelque part, on en revient.
Future<void> ouvrirBoule(
  BuildContext context, {
  required ThemePalette palette,
  VoidCallback? onAnalyse,
  VoidCallback? onPremove,
  String? raisonPremove,
}) async {
  final choix = await showFugaPopup<GesteBoule>(
    context,
    widthFactor: 0.82,
    heightFactor: 0.40,
    dismissible: true,
    rows: [
      (0.30, popupText(T('Analyser ou préparer ses coups ?'), size: 17)),
      (
        0.22,
        popupText(
          onPremove == null ? (raisonPremove ?? '') : '',
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
                text: T('Analyser'),
                fontSize: SF(16),
                color: palette.clair,
                onPressed: onAnalyse == null
                    ? null
                    : () => Navigator.of(context).pop(GesteBoule.analyse),
              ),
            ),
            SizedBox(width: S(8)),
            Expanded(
              child: FugaButton(
                text: T('Pré-coups'),
                fontSize: SF(16),
                color: palette.clair,
                // Pâle quand ce n'est pas le moment — c'est à vous de jouer,
                // ou vous n'êtes que spectateur. La raison est écrite
                // au-dessus plutôt que cachée.
                onPressed: onPremove == null
                    ? null
                    : () => Navigator.of(context).pop(GesteBoule.precoups),
              ),
            ),
          ],
        ),
      ),
    ],
  );
  if (choix == null) return;
  (choix == GesteBoule.analyse ? onAnalyse : onPremove)?.call();
}
