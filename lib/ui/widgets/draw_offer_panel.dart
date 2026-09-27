/// La proposition de nulle, à la place du panneau de l'adversaire.
///
/// Kivy la pose en popup. Une popup mange le plateau : on ne peut plus
/// regarder la position, ni passer par l'analyse avant de répondre — or
/// c'est précisément ce qu'on veut faire avant d'accepter une nulle. Elle
/// prend donc la place des infos du joueur qui la propose, dans son propre
/// bandeau : le plateau reste entier, et toutes les touches restent
/// atteignables.
///
/// Le panneau garde la forme et la hauteur d'un [PlayerPanel] : la mise en
/// page ne bouge pas d'un pixel quand l'offre apparaît ou disparaît.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'fuga_button.dart';
import 'player_panel.dart';

/// Vert de l'acceptation. Le refus garde le gris : c'est le geste neutre,
/// celui qui laisse la partie continuer.
const Color kDrawAccept = Color.fromRGBO(30, 110, 60, 1);

class DrawOfferPanel extends StatelessWidget {
  const DrawOfferPanel({
    super.key,
    required this.proposer,
    required this.palette,
    required this.onAccept,
    required this.onRefuse,
    this.busy = false,
  });

  /// Pseudo de celui qui propose.
  final String proposer;
  final ThemePalette palette;

  /// Nuls pendant l'envoi de la réponse : on ne répond pas deux fois.
  final VoidCallback? onAccept;
  final VoidCallback? onRefuse;
  final bool busy;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // Les mêmes deux rangées qu'un PlayerPanel, à la même épaisseur : le
      // plateau ne bouge pas quand l'offre s'affiche.
      final actions = box.maxHeight.isFinite
          ? math.min(touchHeight(), (box.maxHeight - 2 * S(4)) * 0.55)
          : S(32);

      final texte = Row(
        children: [
          Expanded(
            child: Text(
              '$proposer ${T('propose la nulle')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: kPanelInk,
                fontSize: SF(16),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (busy)
            SizedBox(
              width: S(14),
              height: S(14),
              child: CircularProgressIndicator(strokeWidth: S(2)),
            ),
        ],
      );

      final boutons = Row(
        children: [
          Expanded(
            child: FugaButton(
              text: T('Refuser'),
              height: double.infinity,
              fontSize: SF(15),
              radius: S(16),
              onPressed: busy ? null : onRefuse,
            ),
          ),
          SizedBox(width: S(8)),
          Expanded(
            child: FugaButton(
              text: T('Accepter'),
              height: double.infinity,
              fontSize: SF(15),
              radius: S(16),
              color: kDrawAccept,
              onPressed: busy ? null : onAccept,
            ),
          ),
        ],
      );

      return Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: S(10), vertical: S(4)),
        decoration: BoxDecoration(
          color: palette.menu,
          borderRadius: BorderRadius.circular(S(14)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            box.maxHeight.isFinite
                ? Expanded(child: texte)
                : SizedBox(height: S(34), child: texte),
            SizedBox(height: actions, child: boutons),
          ],
        ),
      );
    },
  );
}
