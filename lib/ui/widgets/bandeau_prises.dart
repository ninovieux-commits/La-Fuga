/// Le matériel mangé, quand il n'y a pas de bandeau de joueur pour le porter.
///
/// Nino : « en mode analyse, il doit y avoir le matériel mangé qui apparaît
/// autour du plateau comme en partie. Ainsi que dans tous les modes
/// comprenant un plateau de jeu et des pièces pouvant être mangées. » Puis,
/// l'ayant vu : « il y a beaucoup trop de place pour les pièces mangées en
/// analyse et pré-coups, fais les deux lignes de pièces au-dessus du
/// plateau, aussi fines que possible selon la taille à laquelle les pièces
/// mangées sont montrées. »
///
/// ## Deux lignes, et rien d'autre
///
/// En partie, les prises vivent dans le bandeau du joueur, à côté de son nom
/// et de son chrono : la bande fait 12 parts sur 104, parce qu'il y a tout
/// cela à loger. Ici il n'y a QUE les pièces — la hauteur est donc celle
/// d'une pièce, et pas un pixel de plus. Deux bandes de joueur prenaient 196
/// pixels sur un écran de 851 ; les deux lignes en prennent une quarantaine,
/// et le plateau récupère le reste.
///
/// Les deux sont AU-DESSUS du plateau, l'une sur l'autre, parce qu'on ne
/// regarde pas le matériel en jouant : on y jette un œil, et deux lignes
/// voisines se comparent mieux que deux bandes séparées par tout le plateau.
///
/// ## La touche d'annulation
///
/// Elle ne paraît que s'il y a un coup à annuler — comme en partie, où elle
/// s'éteint tant qu'on n'a rien bougé. Elle occupe la hauteur des DEUX
/// lignes : c'est ce qui lui donne de quoi se viser au doigt sans rien
/// ajouter à la hauteur du bloc.
library;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'fuga_button.dart';
import 'player_panel.dart';

/// Hauteur d'UNE ligne de prises : celle d'une pièce, plus un cheveu.
///
/// Kivy plafonne une pièce prise à 36 de l'écran de référence ; `S(34)` la
/// laisse donc dessiner à sa taille sans qu'il reste du vide autour.
const double kLignePrises = 34;

class BandeauPrises extends StatelessWidget {
  const BandeauPrises({
    super.key,
    required this.prisesHaut,
    required this.prisesBas,
    required this.palette,
    required this.hautEstBlanc,
    this.avecAnnuler = false,
    this.onAnnuler,
  });

  /// Les pièces prises par le camp du HAUT — donc celles de l'autre.
  final List<Piece> prisesHaut;

  /// Celles prises par le camp du bas.
  final List<Piece> prisesBas;

  final ThemePalette palette;

  /// Quel camp occupe la ligne du haut : il donne sa couleur de fond.
  final bool hautEstBlanc;

  /// Cet écran a-t-il une touche d'annulation ? L'analyse n'en a pas ; les
  /// pré-coups, si.
  ///
  /// Séparé de [onAnnuler] parce que la touche NE DISPARAÎT PLUS quand il
  /// n'y a rien à annuler : elle s'éteint. Nino : « le bouton annulation de
  /// coup ne doit plus disparaître lorsqu'il n'est pas cliquable, il doit
  /// faire comme les autres touches quand elles ne sont pas cliquables. »
  final bool avecAnnuler;

  /// Annuler le coup en cours. Nulle = il n'y a rien à annuler, et la touche
  /// est éteinte.
  final VoidCallback? onAnnuler;

  /// Ce que le bloc entier occupe en hauteur.
  static double hauteur() => S(kLignePrises) * 2;

  Widget _ligne(List<Piece> pieces, {required bool blanc}) => Container(
    height: S(kLignePrises),
    color: blanc ? palette.clairDim : palette.fonceDim,
    padding: EdgeInsets.symmetric(horizontal: S(8), vertical: S(3)),
    child: CapturesStrip(pieces: pieces, palette: palette),
  );

  @override
  Widget build(BuildContext context) {
    final lignes = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ligne(prisesHaut, blanc: hautEstBlanc),
        _ligne(prisesBas, blanc: !hautEstBlanc),
      ],
    );
    if (!avecAnnuler) return lignes;
    // Hauteur donnée EXPLICITEMENT : la touche s'étire sur les deux lignes,
    // et une rangée qui s'étire dans une page qui défile n'a aucune hauteur
    // à quoi s'étirer. Le bloc en impose donc une, qu'il connaît.
    return SizedBox(
      height: hauteur(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: lignes),
          Tooltip(
            message: T('Annuler'),
            child: Material(
              color: onAnnuler == null ? fondEteint(kGrisTouche) : kGrisTouche,
              shape: formeDeTouche(BorderRadius.zero),
              child: InkWell(
                onTap: onAnnuler,
                child: SizedBox(
                  width: hauteur(),
                  child: Center(
                    child: Opacity(
                      opacity: onAnnuler == null ? kOpaciteEteinte : 1,
                      child: glypheAnnuler(palette),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
