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
import 'bulle_cri.dart';
import 'picto_touche.dart';

class BulleDevise extends StatelessWidget {
  const BulleDevise({
    super.key,
    required this.child,
    required this.couleur,
    this.crie = false,
    this.alignementPointe = 0.35,
  });

  final Widget child;
  final Color couleur;

  /// La devise finit par un point d'exclamation : la bulle se hérisse, comme
  /// un message de la messagerie. Nino, capture du profil à l'appui : « et la
  /// bulle là. Elle doit être encadrée ET recevoir les pics d'exclamation ! »
  ///
  /// Elle GARDE SA POINTE, elle : dans un chat les bulles alternent de gauche
  /// à droite et le cri peut se passer de queue, ici elle est seule et doit
  /// désigner quelqu'un.
  final bool crie;

  /// Où la pointe se place sur le bord gauche, de 0 (en haut) à 1 (en bas).
  /// Un peu au-dessus du milieu : c'est là que se trouve le visage.
  final double alignementPointe;

  @override
  Widget build(BuildContext context) {
    final pointe = S(9);
    // Les pics poussent vers l'extérieur du contour, donc vers l'intérieur de
    // la boîte qu'on peint : on leur réserve leur hauteur tout autour, et le
    // creux s'y ajoute pour qu'il ne morde pas sur la première lettre.
    final marge = crie ? S(kPicHaut) + S(kPicCreux) : 0.0;
    return CustomPaint(
      painter: _BullePointue(
        couleur: couleur,
        pointe: pointe,
        rayon: S(16),
        hauteurPointe: S(14),
        position: alignementPointe,
        crie: crie,
        marge: marge,
      ),
      child: Padding(
        // La marge de gauche laisse la place à la pointe, les autres sont
        // celles des bulles de la messagerie.
        padding: EdgeInsets.fromLTRB(
          pointe + S(12) + marge,
          S(10) + marge,
          S(14) + marge,
          S(10) + marge,
        ),
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
    required this.crie,
    required this.marge,
  });

  /// Le contour se hérisse, pointe comprise.
  final bool crie;

  /// Place réservée aux pics tout autour.
  final double marge;

  final Color couleur;

  /// De combien la pointe dépasse à gauche du corps de la bulle.
  final double pointe;

  final double rayon;
  final double hauteurPointe;
  final double position;

  @override
  void paint(Canvas canvas, Size size) {
    final corps = Rect.fromLTRB(
      pointe + marge,
      marge,
      size.width - marge,
      size.height - marge,
    );
    if (corps.width <= 0 || corps.height <= 0) return;

    // La pointe reste DANS la bulle : sur une bulle d'une seule ligne, la
    // coller au bord la ferait dépasser en haut ou en bas.
    final milieu = (corps.height * position).clamp(
      hauteurPointe / 2 + rayon / 2,
      corps.height - hauteurPointe / 2 - rayon / 2,
    );

    final arrondi = RRect.fromRectAndRadius(corps, Radius.circular(rayon));
    // LA POINTE NE SE HÉRISSE PAS. Essayée hérissée, elle se perdait dans ses
    // propres pics : son sommet est un angle vif, et les pics qui le
    // contournent en font une bavure. Elle reste donc lisse, et c'est le
    // CORPS qui crie — la bulle désigne toujours aussi clairement la photo.
    //
    // Sa base part un peu à l'intérieur du corps : les creux des pics mordent
    // vers le dedans, et une base posée pile sur le bord laisserait une
    // encoche entre les deux formes.
    final dedans = crie ? S(kPicCreux) + S(2) : 0.0;
    final queue = Path()
      ..moveTo(corps.left + dedans, milieu - hauteurPointe / 2)
      ..lineTo(marge, milieu)
      ..lineTo(corps.left + dedans, milieu + hauteurPointe / 2)
      ..close();
    final corpsDessine = crie
        ? cheminHerisse(
            Path()..addRRect(arrondi),
            haut: S(kPicHaut),
            court: S(kPicCourt),
            pas: S(kPicPas),
            creux: S(kPicCreux),
          )
        : (Path()..addRRect(arrondi));
    // Une seule silhouette, pour que le trait noir n'ait pas de couture là
    // où la pointe rejoint le corps.
    final chemin = Path.combine(PathOperation.union, corpsDessine, queue);

    // LE TRAIT NOIR DES TOUCHES, sur le MÊME chemin que le fond : la pointe
    // et les pics le portent donc comme le reste. Il est centré sur le tracé,
    // d'où le double, et rogné à la forme pour que la bulle ne grossisse pas
    // d'un cheveu — le même piège que pour les bulles de la messagerie.
    final trait = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = kTraitPicto * 2
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(chemin, Paint()..color = couleur)
      ..save()
      ..clipPath(chemin)
      ..drawPath(chemin, trait)
      ..restore();
  }

  @override
  bool shouldRepaint(_BullePointue old) =>
      old.couleur != couleur ||
      old.pointe != pointe ||
      old.rayon != rayon ||
      old.position != position ||
      old.crie != crie ||
      old.marge != marge;
}
