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

/// Vrai quand ce mode ne connaît pas les pré-coups : la boule EST alors la
/// touche « Analyser », et ouvrir un popup pour une seule touche vivante
/// serait un geste pour rien.
///
/// Nino : « dans les modes de jeu sans pré-coups, le bouton analyse est alors
/// simplement remplacé par la boule de cristal. » Une relecture, une analyse,
/// une position composée : on n'y prépare pas la réponse de l'adversaire.
///
/// LE SIGNE QU'UN MODE LES CONNAÎT EST SA RAISON. Une touche pâle sans raison
/// écrite est un défaut en soi : un mode qui offre les pré-coups en donne donc
/// toujours une, y compris quand il les ouvre. Pas de raison, pas de
/// pré-coups — et la règle se tient d'elle-même, sans un drapeau de plus à
/// garder d'accord avec le reste.
bool bouleSansChoix({VoidCallback? onPremove, String? raisonPremove}) =>
    onPremove == null && raisonPremove == null;

/// Ouvre la boule. Rien ne se confirme : on va quelque part, on en revient.
Future<void> ouvrirBoule(
  BuildContext context, {
  required ThemePalette palette,
  VoidCallback? onAnalyse,
  VoidCallback? onPremove,
  String? raisonPremove,
}) async {
  if (bouleSansChoix(onPremove: onPremove, raisonPremove: raisonPremove)) {
    onAnalyse?.call();
    return;
  }
  // Pourquoi les pré-coups sont fermés, quand ils le sont. Une ligne VIDE
  // n'est pas une ligne : elle tenait sa part de la hauteur sans rien y
  // écrire, et c'était le gros du vide que Nino voyait.
  final raison = onPremove == null ? (raisonPremove ?? '') : '';

  final choix = await showFugaPopup<GesteBoule>(
    context,
    widthFactor: 0.82,
    heightFactor: 0.40,
    dismissible: true,
    rows: [
      (0.30, popupText(T('Analyser ou préparer ses coups ?'), size: 17)),
      if (raison.isNotEmpty)
        (
          0.22,
          popupText(
            raison,
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
