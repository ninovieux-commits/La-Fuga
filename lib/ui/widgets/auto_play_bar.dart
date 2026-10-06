/// Les commandes de la lecture automatique, sous le plateau.
///
/// À la place des informations du joueur du bas, dont on ne garde que les
/// pièces capturées : un curseur de vitesse, le retour au début et le
/// play/pause, puis le choix d'une rythmique.
///
/// Le curseur et la rythmique ne coexistent pas. Choisir une danse fige la
/// vitesse — c'est elle qui la donne — et le curseur s'éteint ; le reprendre
/// abandonne la danse.
library;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../game/rythmique.dart';
import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'player_panel.dart';
import 'fuga_button.dart';
import 'game_top_bar.dart';

class AutoPlayBar extends StatelessWidget {
  const AutoPlayBar({
    super.key,
    required this.palette,
    required this.captures,
    required this.tempo,
    required this.enLecture,
    required this.onTempo,
    required this.onRythmique,
    required this.onDebut,
    required this.onPlayPause,
  });

  final ThemePalette palette;

  /// Les pièces sorties : la seule information qu'on garde du panneau.
  final List<Piece> captures;

  final TempoLecture tempo;

  /// Vrai quand ça défile : la touche montre alors la pause.
  final bool enLecture;

  /// Nouvelle durée entre deux coups, en secondes. Abandonne la rythmique.
  final void Function(double) onTempo;

  /// Choisir une danse, ou `null` pour revenir au curseur.
  final void Function(Rythmique?) onRythmique;

  final VoidCallback onDebut;
  final VoidCallback onPlayPause;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: S(10), vertical: S(2)),
    // La hauteur vient de la pile, qui donne trente parts à cette bande : la
    // colonne la remplit, et les pièces capturées prennent ce qui reste.
    child: Column(
      children: [
        Expanded(
          child: CapturesStrip(pieces: captures, palette: palette),
        ),
        _curseur(),
        SizedBox(height: S(2)),
        SizedBox(
          height: touchHeight() * 0.8,
          child: Row(
            children: [
              Expanded(
                child: FugaButton(
                  text: '⏮  ${T('Début')}',
                  height: double.infinity,
                  fontSize: SF(14),
                  onPressed: onDebut,
                ),
              ),
              SizedBox(width: S(8)),
              Expanded(
                child: FugaButton(
                  // Le symbole seul : il se lit sans traduction, et à cette
                  // taille un mot tiendrait mal.
                  text: enLecture ? '⏸' : '▶',
                  color: palette.clair,
                  textColor: Colors.black,
                  height: double.infinity,
                  fontSize: SF(18),
                  onPressed: onPlayPause,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: S(4)),
        SizedBox(
          width: double.infinity,
          height: touchHeight() * 0.8,
          child: FugaButton(
            text: tempo.estLibre
                ? T('Choisir une rythmique')
                : tempo.rythmique!.etiquette,
            color: tempo.estLibre ? kBarButtonDark : palette.fonce,
            height: double.infinity,
            fontSize: SF(14),
            onPressed: () => _choisir(context),
          ),
        ),
      ],
    ),
  );

  /// Le curseur de vitesse, et ce qu'il vaut.
  ///
  /// Éteint quand une rythmique est choisie : la vitesse vient alors de la
  /// danse, et laisser le curseur actif laisserait croire le contraire.
  Widget _curseur() => Row(
    children: [
      Expanded(
        child: SliderTheme(
          data: SliderThemeData(
            trackHeight: S(3),
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: S(8)),
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(
            value: tempo.estLibre
                ? tempo.secondes.clamp(kVitesseMin, kVitesseMax)
                : kVitesseMin,
            min: kVitesseMin,
            max: kVitesseMax,
            // Un cran toutes les demi-secondes : le curseur ne s'arrête
            // qu'entre 0,5 et 5,0, de demi-seconde en demi-seconde.
            divisions: kVitesseCrans - 1,
            activeColor: palette.clair,
            inactiveColor: Colors.white24,
            onChanged: tempo.estLibre ? onTempo : null,
          ),
        ),
      ),
      SizedBox(
        width: S(96),
        child: Text(
          tempo.etiquette,
          textAlign: TextAlign.center,
          maxLines: 1,
          style: TextStyle(
            color: tempo.estLibre ? Colors.white : palette.clair,
            fontSize: SF(12),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ],
  );

  Future<void> _choisir(BuildContext context) async {
    final choix = await showDialog<Object>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.fonce,
        title: Text(
          T('Choisir une rythmique'),
          style: TextStyle(color: Colors.white, fontSize: SF(16)),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final r in Rythmique.values) ...[
                  SizedBox(
                    width: double.infinity,
                    child: FugaButton(
                      // La vitesse est écrite à côté du nom : « les vitesses
                      // sont prédéfinies » ne dit pas lesquelles.
                      text:
                          '${r.etiquette}  ·  '
                          '${r.secondesParCoup.toStringAsFixed(2)} s',
                      fontSize: SF(14),
                      color: tempo.rythmique == r ? palette.clair : kFugaGrey,
                      textColor: tempo.rythmique == r
                          ? Colors.black
                          : Colors.white,
                      onPressed: () => Navigator.of(context).pop(r),
                    ),
                  ),
                  SizedBox(height: S(6)),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FugaButton(
                    text: T('Aucune (régler à la main)'),
                    fontSize: SF(14),
                    color: kBarButtonDark,
                    onPressed: () => Navigator.of(context).pop('aucune'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (choix == null) return;
    onRythmique(choix is Rythmique ? choix : null);
  }
}
