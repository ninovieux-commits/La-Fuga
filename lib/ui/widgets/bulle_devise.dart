/// La devise d'un joueur, dans une bulle qui POINTE vers sa photo.
///
/// Nino : « la devise doit être dans une bulle qui pointe vers l'image de
/// profil à gauche (comme dans les chats). »
///
/// Les bulles de la messagerie n'ont pas de queue : elles se contentent d'un
/// coin presque droit du côté du locuteur, ce qui suffit quand les bulles
/// alternent de gauche à droite. Ici il n'y en a qu'une, et elle doit désigner
/// quelqu'un : il lui faut une vraie pointe.
library;

import 'package:flutter/material.dart';

import '../scale.dart';

class BulleDevise extends StatelessWidget {
  const BulleDevise({
    super.key,
    required this.child,
    required this.couleur,
    this.alignementPointe = 0.35,
  });

  final Widget child;
  final Color couleur;

  /// Où la pointe se place sur le bord gauche, de 0 (en haut) à 1 (en bas).
  /// Un peu au-dessus du milieu : c'est là que se trouve le visage.
  final double alignementPointe;

  @override
  Widget build(BuildContext context) {
    final pointe = S(9);
    return CustomPaint(
      painter: _BullePointue(
        couleur: couleur,
        pointe: pointe,
        rayon: S(16),
        hauteurPointe: S(14),
        position: alignementPointe,
      ),
      child: Padding(
        // La marge de gauche laisse la place à la pointe, les autres sont
        // celles des bulles de la messagerie.
        padding: EdgeInsets.fromLTRB(pointe + S(12), S(10), S(14), S(10)),
        child: child,
      ),
    );
  }
}

class _BullePointue extends CustomPainter {
  const _BullePointue({
    required this.couleur,
    required this.pointe,
    required this.rayon,
    required this.hauteurPointe,
    required this.position,
  });

  final Color couleur;

  /// De combien la pointe dépasse à gauche du corps de la bulle.
  final double pointe;

  final double rayon;
  final double hauteurPointe;
  final double position;

  @override
  void paint(Canvas canvas, Size size) {
    final corps = Rect.fromLTRB(pointe, 0, size.width, size.height);
    if (corps.width <= 0 || corps.height <= 0) return;

    // La pointe reste DANS la bulle : sur une bulle d'une seule ligne, la
    // coller au bord la ferait dépasser en haut ou en bas.
    final milieu = (corps.height * position).clamp(
      hauteurPointe / 2 + rayon / 2,
      corps.height - hauteurPointe / 2 - rayon / 2,
    );

    final chemin = Path()
      ..addRRect(RRect.fromRectAndRadius(corps, Radius.circular(rayon)))
      ..moveTo(corps.left, milieu - hauteurPointe / 2)
      ..lineTo(0, milieu)
      ..lineTo(corps.left, milieu + hauteurPointe / 2)
      ..close();

    canvas.drawPath(chemin, Paint()..color = couleur);
  }

  @override
  bool shouldRepaint(_BullePointue old) =>
      old.couleur != couleur ||
      old.pointe != pointe ||
      old.rayon != rayon ||
      old.position != position;
}
