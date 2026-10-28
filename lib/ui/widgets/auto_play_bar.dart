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
        // Le curseur se prend du bout du doigt : il lui faut de l'air sous
        // lui, sans quoi on attrape une touche en voulant le saisir. Nino :
        // « il doit aussi être légèrement plus éloigné des boutons qui sont
        // en dessous. »
        SizedBox(height: S(14)),
        SizedBox(
          height: touchHeight() * 0.8,
          child: Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: T('Début'),
                  child: FugaButton(
                    // Le signe SEUL, et dessiné. Il était écrit « ⏮ Début » :
                    // le caractère tombait en émoji de couleur sur Android,
                    // à côté du « ▶ » tout noir de la touche voisine. Nino :
                    // « dessine le comme le bouton play qui est juste à
                    // côté, et retire le mot début, tout le monde comprend ce
                    // signe. »
                    enfant: GlypheDebut(taille: SF(18), couleur: Colors.white),
                    height: double.infinity,
                    onPressed: onDebut,
                  ),
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
            trackHeight: S(5),
            // Gros, parce qu'on le saisit avec un doigt et non avec une
            // souris. Nino : « le bouton pour choisir le nombre de secondes
            // doit être plus gros, là il est dur à attraper. »
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: S(14)),
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

/// Le « retour au début » : un trait, puis deux triangles vers la gauche.
///
/// Dessiné et non écrit : le caractère ⏮ s'affiche en émoji de couleur sur
/// Android, alors que le ▶ de la touche voisine reste un triangle plein. Les
/// deux touches doivent se ressembler.
class GlypheDebut extends StatelessWidget {
  const GlypheDebut({super.key, required this.taille, required this.couleur});

  /// Hauteur du signe. Sa largeur vaut autant : il est carré.
  final double taille;

  final Color couleur;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: taille,
    height: taille,
    child: CustomPaint(painter: _PeintreDebut(couleur)),
  );
}

class _PeintreDebut extends CustomPainter {
  const _PeintreDebut(this.couleur);

  final Color couleur;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final encre = Paint()..color = couleur;
    // Le trait, collé à gauche, puis les deux triangles qui le visent.
    final largeurTrait = h * 0.16;
    canvas.drawRect(Rect.fromLTWH(0, 0, largeurTrait, h), encre);
    final debut = largeurTrait + h * 0.08;
    final cote = h * 0.38;
    for (var i = 0; i < 2; i++) {
      final x = debut + i * cote;
      canvas.drawPath(
        Path()
          ..moveTo(x, h / 2)
          ..lineTo(x + cote, 0)
          ..lineTo(x + cote, h)
          ..close(),
        encre,
      );
    }
  }

  @override
  bool shouldRepaint(_PeintreDebut vieux) => vieux.couleur != couleur;
}
