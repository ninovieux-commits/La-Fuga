/// Les commandes de la lecture automatique, dans le bandeau du joueur du bas.
///
/// C'EST UN BANDEAU DE JOUEUR, pas une barre à part. Nino : « il doit y avoir
/// les bandeaux larges d'infos des deux joueurs, mais ne doivent pas contenir
/// les infos telles que le temps ou le score, qui de toutes façons sont
/// erronées. » Les commandes prennent donc la place que le chrono et le score
/// laissent libre : le curseur de vitesse là où s'écrivait le temps, le retour
/// au début et le play/pause là où un joueur a ses touches. Le bandeau garde
/// ses douze parts, l'écran ses 7 + 12 + 66 + 12 + 7, et il n'y a plus rien à
/// faire défiler — « si on fait bien les choses, peut-être que tout peut
/// rentrer sur l'écran et qu'il n'y aura plus besoin de défilement. Ce serait
/// l'idéal. »
///
/// Il y a eu ici un troisième réglage, « choisir une rythmique », qui imposait
/// la cadence d'une valse, d'une gigue ou d'une sarabande. Essayé sur un vrai
/// téléphone, il ne tenait pas à l'oreille : une partie n'est pas une mélodie.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../game/vitesse_lecture.dart';
import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'etoile_favori.dart';
import 'player_panel.dart';
import 'picto_touche.dart';
import 'profile_photo.dart';

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
    this.nom = '',
    this.photo = '',
    this.favori = false,
    this.onNameTap,
  });

  final ThemePalette palette;

  /// Les pièces sorties, comme dans le bandeau d'un joueur.
  final List<Piece> captures;

  /// Temps entre deux coups, en secondes.
  final double secondes;

  /// Vrai quand ça défile : la touche montre alors la pause.
  final bool enLecture;

  /// Nouvelle durée entre deux coups, en secondes.
  final void Function(double) onTempo;

  final VoidCallback onDebut;
  final VoidCallback onPlayPause;

  /// Le joueur du bas : son nom, son visage, son étoile. Le bandeau reste le
  /// sien — ce sont le chrono et le score qui s'en vont, pas lui.
  final String nom;
  final String photo;
  final bool favori;
  final VoidCallback? onNameTap;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(
      horizontal: PlayerPanel.margeH(),
      vertical: PlayerPanel.margeV(),
    ),
    color: palette.menu,
    child: LayoutBuilder(
      builder: (context, box) {
        final actions = box.maxHeight.isFinite
            ? PlayerPanel.hauteurActions(box.maxHeight)
            : S(32);
        return Row(
          children: [
            GestureDetector(
              onTap: onNameTap,
              child: ProfilePhoto(
                photo: photo,
                size: box.maxHeight.isFinite ? box.maxHeight - 2 * S(4) : S(58),
              ),
            ),
            SizedBox(width: S(8)),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // LE BANDEAU DU BAS EST UN MIROIR : la rangée des touches
                  // est celle qui touche le plateau, comme dans une partie.
                  SizedBox(height: actions, child: _touches(actions)),
                  Expanded(child: _identite()),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  /// Le nom, et le curseur de vitesse là où le chrono s'écrivait.
  Widget _identite() => Row(
    children: [
      Expanded(
        flex: 40,
        child: GestureDetector(
          onTap: onNameTap,
          // UN SEUL texte, étoile comprise, comme dans un bandeau de
          // joueur : voir `nomEtoile`, qui dit pourquoi.
          child: Text.rich(
            nomEtoile(nom, favori: favori, taille: SF(16)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: kPanelInk,
              fontSize: SF(16),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      Expanded(flex: 60, child: _curseur()),
    ],
  );

  /// Les prises, puis les deux touches de la lecture — à la place qu'occupent
  /// l'annulation, le message rapide et le drapeau dans une partie.
  Widget _touches(double rangee) => Row(
    children: [
      Expanded(
        child: CapturesStrip(pieces: captures, palette: palette),
      ),
      ToucheAction(
        tooltip: T('Début'),
        onPressed: onDebut,
        palette: palette,
        // Le signe SEUL, et dessiné. Il était écrit « ⏮ Début » : le
        // caractère tombait en émoji de couleur sur Android, à côté du « ▶ »
        // tout noir de la touche voisine. Nino : « dessine le comme le bouton
        // play qui est juste à côté, et retire le mot début, tout le monde
        // comprend ce signe. »
        enfant: GlypheDebut(
          taille: rangee * kPartPicto,
          couleur: palette.fonce,
        ),
      ),
      ToucheAction(
        tooltip: enLecture ? T('Pause') : T('Lire'),
        onPressed: onPlayPause,
        palette: palette,
        // DESSINÉS, les deux. Nino : « le bouton pause en emoji ne me
        // convient pas. Dessine le de la même manière que le bouton |<< et le
        // bouton play. »
        enfant: enLecture
            ? GlyphePause(taille: rangee * kPartPicto, couleur: palette.clair)
            : GlyphePlay(taille: rangee * kPartPicto, couleur: palette.clair),
      ),
    ],
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
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: S(12)),
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(
            value: secondes.clamp(kVitesseMin, kVitesseMax),
            min: kVitesseMin,
            max: kVitesseMax,
            // Un cran toutes les demi-secondes : le curseur ne s'arrête
            // qu'entre 0,5 et 5,0, de demi-seconde en demi-seconde.
            divisions: kVitesseCrans - 1,
            activeColor: palette.fonce,
            inactiveColor: Colors.black26,
            onChanged: onTempo,
          ),
        ),
      ),
      SizedBox(
        // De quoi écrire « 2.0 s » en entier : à 52 le « s » se faisait
        // couper, sans rien pour le dire.
        width: S(64),
        child: Text(
          '${secondes.toStringAsFixed(1)} s',
          textAlign: TextAlign.right,
          maxLines: 1,
          style: TextStyle(
            color: kPanelInk,
            fontSize: SF(14),
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
/// trois touches de la lecture doivent se ressembler, et porter le même fin
/// trait noir que tous les symboles de touches.
class GlypheDebut extends StatelessWidget {
  const GlypheDebut({super.key, required this.taille, required this.couleur});

  /// Hauteur du signe. Sa largeur vaut autant : il est carré.
  final double taille;

  final Color couleur;

  @override
  Widget build(BuildContext context) => _signe(taille, couleur, _tracerDebut);
}

/// La PAUSE : deux barres verticales.
class GlyphePause extends StatelessWidget {
  const GlyphePause({super.key, required this.taille, required this.couleur});

  final double taille;
  final Color couleur;

  @override
  Widget build(BuildContext context) => _signe(taille, couleur, _tracerPause);
}

/// LA LECTURE : un triangle plein, pointe à droite.
class GlyphePlay extends StatelessWidget {
  const GlyphePlay({super.key, required this.taille, required this.couleur});

  final double taille;
  final Color couleur;

  @override
  Widget build(BuildContext context) => _signe(taille, couleur, _tracerPlay);
}

/// Un signe dessiné, à la taille d'un picto de touche.
Widget _signe(double taille, Color couleur, Path Function(Size) tracer) =>
    SizedBox(
      width: taille,
      height: taille,
      child: CustomPaint(painter: _PeintreSigne(couleur, tracer)),
    );

/// Le peintre commun aux trois signes : le trait noir, puis la couleur.
///
/// LE MÊME CONTOUR QUE LES AUTRES SYMBOLES. Nino : « j'aimerais que ça
/// reproduise fidèlement les formes des angles/arrondis, que ce soit pour ce
/// nouveau symbole comme pour tous ceux qu'on a mis jusque-là ». Le contour
/// est donc la forme elle-même, reposée [kCopiesDuBord] fois en couronne à
/// [kTraitPicto] de rayon — une vraie dilatation par un disque, comme pour les
/// pictos et les mots.
class _PeintreSigne extends CustomPainter {
  const _PeintreSigne(this.couleur, this.tracer);

  final Color couleur;
  final Path Function(Size) tracer;

  @override
  void paint(Canvas canvas, Size size) {
    final forme = tracer(size);
    final noir = Paint()..color = const Color(0xFF000000);
    final rayon = S(kTraitPicto);
    for (var i = 0; i < kCopiesDuBord; i++) {
      final angle = 2 * math.pi * i / kCopiesDuBord;
      canvas.save();
      canvas.translate(rayon * math.cos(angle), rayon * math.sin(angle));
      canvas.drawPath(forme, noir);
      canvas.restore();
    }
    canvas.drawPath(forme, Paint()..color = couleur);
  }

  @override
  bool shouldRepaint(_PeintreSigne vieux) =>
      vieux.couleur != couleur || vieux.tracer != tracer;
}

/// Le trait collé à gauche, puis les deux triangles qui le visent.
Path _tracerDebut(Size size) {
  final h = size.height;
  final largeurTrait = h * 0.16;
  final chemin = Path()..addRect(Rect.fromLTWH(0, 0, largeurTrait, h));
  final debut = largeurTrait + h * 0.08;
  final cote = h * 0.38;
  for (var i = 0; i < 2; i++) {
    final x = debut + i * cote;
    chemin
      ..moveTo(x, h / 2)
      ..lineTo(x + cote, 0)
      ..lineTo(x + cote, h)
      ..close();
  }
  return chemin;
}

/// Deux barres, et entre elles un vide de leur propre largeur.
Path _tracerPause(Size size) {
  final h = size.height;
  final largeur = h * 0.28;
  final x = (size.width - 3 * largeur) / 2;
  return Path()
    ..addRect(Rect.fromLTWH(x, 0, largeur, h))
    ..addRect(Rect.fromLTWH(x + 2 * largeur, 0, largeur, h));
}

/// Un triangle franc, aux proportions des triangles du retour au début.
Path _tracerPlay(Size size) {
  final h = size.height;
  final cote = h * 0.76;
  final x = (size.width - cote) / 2;
  return Path()
    ..moveTo(x, 0)
    ..lineTo(x + cote, h / 2)
    ..lineTo(x, h)
    ..close();
}
