/// Les commandes de la lecture automatique, sous le plateau.
///
/// À la place des informations du joueur du bas, dont on ne garde que les
/// pièces capturées : un curseur de vitesse, puis le retour au début et le
/// play/pause.
///
/// Il y a eu ici un troisième réglage, « choisir une rythmique », qui imposait
/// la cadence d'une valse, d'une gigue ou d'une sarabande. Essayé sur un vrai
/// téléphone, il ne tenait pas à l'oreille : une partie n'est pas une mélodie.
library;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../game/vitesse_lecture.dart';
import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'player_panel.dart';
import 'fuga_button.dart';

class AutoPlayBar extends StatelessWidget {
  const AutoPlayBar({
    super.key,
    required this.palette,
    required this.captures,
    required this.secondes,
    required this.enLecture,
    required this.onTempo,
    required this.onDebut,
    required this.onPlayPause,
  });

  final ThemePalette palette;

  /// Les pièces sorties : la seule information qu'on garde du panneau.
  final List<Piece> captures;

  /// Temps entre deux coups, en secondes.
  final double secondes;

  /// Vrai quand ça défile : la touche montre alors la pause.
  final bool enLecture;

  /// Nouvelle durée entre deux coups, en secondes.
  final void Function(double) onTempo;

  final VoidCallback onDebut;
  final VoidCallback onPlayPause;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: S(10), vertical: S(2)),
    // La hauteur vient de la pile : la colonne la remplit, et les pièces
    // capturées prennent ce qui reste.
    child: Column(
      children: [
        Expanded(
          child: CapturesStrip(pieces: captures, palette: palette),
        ),
        _curseur(),
        SizedBox(height: S(4)),
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
      ],
    ),
  );

  /// Le curseur de vitesse, et ce qu'il vaut.
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
            value: secondes.clamp(kVitesseMin, kVitesseMax),
            min: kVitesseMin,
            max: kVitesseMax,
            // Un cran toutes les demi-secondes : le curseur ne s'arrête
            // qu'entre 0,5 et 5,0, de demi-seconde en demi-seconde.
            divisions: kVitesseCrans - 1,
            activeColor: palette.clair,
            inactiveColor: Colors.white24,
            onChanged: onTempo,
          ),
        ),
      ),
      SizedBox(
        width: S(96),
        child: Text(
          '${secondes.toStringAsFixed(1)} s',
          textAlign: TextAlign.center,
          maxLines: 1,
          style: TextStyle(
            color: Colors.white,
            fontSize: SF(12),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ],
  );
}
