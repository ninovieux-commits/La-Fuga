/// Le drapeau : abandonner, ou proposer la nulle.
///
/// Nino : « quand on est en partie, le bouton abandonner et le bouton match
/// nul doivent disparaître. À la place on met un bouton avec ce drapeau.
/// Quand on clique dessus, un popup apparaît nous proposant abandonner et
/// match nul. Quand on clique sur un des deux, "confirmer l'abandon / la
/// demande de nulle ? (Oui) (Non)". Le bouton match nul ne doit être
/// cliquable que si on a déjà joué notre coup (comme maintenant). »
///
/// ## Deux gestes rares, une seule touche
///
/// Abandonner et proposer la nulle sont les deux seuls gestes d'une partie
/// qui la terminent sans la jouer. Ils tenaient chacun leur carré dans le
/// bandeau, à côté de ceux dont on se sert à chaque coup — et le rouge de
/// l'abandon était à un doigt du reste. Les voilà derrière un drapeau, le
/// signe qu'on lève quand on ne joue plus.
///
/// ## La confirmation n'est pas une politesse
///
/// Les deux sont irréversibles : une nulle proposée part chez l'adversaire,
/// un abandon donne la partie. Chacun se confirme donc, et le texte de
/// l'abandon vient de l'écran qui appelle — une partie locale dit qui
/// abandonne et ce que l'autre marque, ce qu'une formule générale ne saurait
/// pas dire.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'fuga_button.dart';
import 'fuga_popup.dart';

/// Ce que le drapeau propose.
enum GesteDrapeau { nulle, abandon }

/// Ouvre le drapeau, puis la confirmation du geste choisi.
///
/// [nulleActive] dit si le coup est joué : sinon la touche pâlit, et la
/// raison est écrite au-dessus plutôt que cachée dans une infobulle.
Future<void> ouvrirDrapeau(
  BuildContext context, {
  required ThemePalette palette,
  required bool nulleActive,
  required bool nulleProposee,
  required String messageAbandon,
  String? raisonNulle,
  VoidCallback? onNulle,
  VoidCallback? onAbandon,
}) async {
  final choix = await showFugaPopup<GesteDrapeau>(
    context,
    widthFactor: 0.82,
    heightFactor: 0.40,
    dismissible: true,
    rows: [
      (0.30, popupText(T('Abandonner ou proposer la nulle ?'), size: 17)),
      (
        0.22,
        popupText(
          onNulle == null
              ? ''
              : nulleActive
              ? (nulleProposee ? T('Nulle proposée') : '')
              : (raisonNulle ?? T('Jouez votre coup d abord')),
          size: 13,
          color: const Color.fromRGBO(217, 217, 217, 1),
        ),
      ),
      (
        kTouchRow,
        Row(
          children: [
            // Pas de nulle du tout contre Deep Grey : on ne négocie pas
            // avec lui. Une touche pâle laisserait croire le contraire.
            if (onNulle != null)
              Expanded(
                child: FugaButton(
                  text: T('Proposer nulle'),
                  fontSize: SF(16),
                  color: nulleProposee ? palette.clair : kFugaGrey,
                  // Pâle et sans geste quand le coup n'est pas joué : la
                  // touche dit d'elle-même qu'elle n'est pas pour
                  // maintenant.
                  onPressed: nulleActive
                      ? () => Navigator.of(context).pop(GesteDrapeau.nulle)
                      : null,
                ),
              ),
            if (onNulle != null) SizedBox(width: S(8)),
            Expanded(
              child: FugaButton(
                text: T('Abandonner'),
                fontSize: SF(16),
                color: const Color.fromRGBO(140, 26, 26, 1),
                onPressed: () =>
                    Navigator.of(context).pop(GesteDrapeau.abandon),
              ),
            ),
          ],
        ),
      ),
    ],
  );
  if (choix == null || !context.mounted) return;

  final nulle = choix == GesteDrapeau.nulle;
  final confirme = await _confirme(
    context,
    palette: palette,
    titre: nulle
        ? T('Confirmer la demande de nulle ?')
        : T("Confirmer l'abandon ?"),
    message: nulle ? '' : messageAbandon,
  );
  if (!confirme) return;
  (nulle ? onNulle : onAbandon)?.call();
}

/// « Oui » ou « Non », et rien d'autre.
Future<bool> _confirme(
  BuildContext context, {
  required ThemePalette palette,
  required String titre,
  required String message,
}) async {
  final ok = await showFugaPopup<bool>(
    context,
    widthFactor: 0.82,
    heightFactor: message.isEmpty ? 0.34 : 0.42,
    rows: [
      (message.isEmpty ? 0.42 : 0.30, popupText(titre, size: 17, bold: true)),
      if (message.isNotEmpty)
        (
          0.25,
          popupText(
            message,
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
                text: T('Non'),
                fontSize: SF(16),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
            SizedBox(width: S(8)),
            Expanded(
              child: FugaButton(
                text: T('Oui'),
                color: palette.fonce,
                fontSize: SF(16),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        ),
      ),
    ],
  );
  return ok == true;
}
