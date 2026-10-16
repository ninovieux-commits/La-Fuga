/// La bulle de cri : celle des messages qui finissent par un point
/// d'exclamation.
///
/// Nino : « lorsqu'un message se finit par "!" ou "!?", ça fait des bulles
/// avec des pics. […] On reprend la forme de bulle qu'on a déjà, on ajoute
/// des pics vers l'extérieur. » Puis, les aperçus en main : « creux marqués
/// mais avec pics plus larges, on enlève le truc qui est censé servir de
/// queue. »
///
/// ## La forme
///
/// On part de la bulle ordinaire — le même rectangle à coins ronds — et on
/// PARCOURT son contour pour y accrocher les pics. Passer par le contour
/// plutôt que par les quatre côtés a un avantage net : les coins arrondis
/// sont traités comme le reste, donc les pics y tournent au lieu de s'arrêter
/// au début de l'arrondi.
///
/// D'un sommet au suivant on ne passe pas par deux droites mais par une
/// courbe qui RENTRE vers l'intérieur. Son point de commande vaut
/// `2×fond − (A+B)/2` et non le fond lui-même : une quadratique ne passe pas
/// par son point de commande, et viser le fond directement donnerait un creux
/// deux fois moins profond que demandé. Avec cette formule, [kPicCreux] dit
/// vraiment de combien le creux descend.
///
/// ## Le nombre de pics est PAIR
///
/// Les pics alternent deux tailles. Avec un nombre impair, le dernier
/// retrouve le premier à la même taille là où le contour se referme, et
/// l'alternance porte une couture visible à cet endroit. Le défaut ne
/// paraîtrait que sur certaines largeurs de bulle — donc en partie, et pas
/// ici.
///
/// ## Plus de coin-pointe
///
/// La bulle ordinaire a un coin presque droit du côté du locuteur, qui lui
/// tient lieu de queue. Sur une bulle hérissée il ne dit plus rien et casse
/// le dessin : les quatre coins sont ronds. Qui parle se lit au côté et à la
/// couleur, comme pour un émoji seul, qui se passe de bulle sans qu'on perde
/// jamais le locuteur.
///
/// ## Le creux s'ajoute à la marge du texte
///
/// Le creux mord vers l'intérieur. Sans rien faire, le fond du creux
/// s'approcherait de la première lettre d'autant. La marge intérieure porte
/// donc `marge + creux` : la bulle s'élargit, le texte garde son air.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../scale.dart';

/// Distance d'un sommet au suivant, le long du contour.
const double kPicPas = 38;

/// Hauteur d'un grand pic, et du petit qui le suit.
const double kPicHaut = 16;
const double kPicCourt = 8;

/// De combien le fond du creux descend SOUS le contour d'origine.
const double kPicCreux = 5;

/// Rayon des coins de la bulle — celui de [MessageBubble].
const double kPicRayon = 18;

/// Ce message est-il un cri ?
///
/// Nino dit « "!" ou "!?" ». On prend donc toute FIN faite de `!` et de `?`
/// pourvu qu'elle contienne au moins un `!` : `!`, `!!`, `!?`, `?!`, `!!!`
/// passent tous. Un message qui finit par `?` seul reste une bulle ordinaire
/// — c'est une question, pas un cri.
bool estUnCri(String texte) {
  final t = texte.trimRight();
  var i = t.length;
  var exclamation = false;
  while (i > 0) {
    final c = t[i - 1];
    if (c == '!') {
      exclamation = true;
    } else if (c != '?') {
      break;
    }
    i--;
  }
  return exclamation;
}

/// Le contour hérissé, autour de [base].
///
/// [haut] et [court] sont les deux hauteurs de pic qui alternent, [pas] la
/// distance d'un sommet au suivant, [creux] la profondeur du creux sous le
/// contour.
Path cheminBulleCri(
  RRect base, {
  required double haut,
  required double court,
  required double pas,
  required double creux,
}) {
  final contour = Path()..addRRect(base);
  final centre = base.outerRect.center;
  final sortie = Path();

  for (final metrique in contour.computeMetrics()) {
    final long = metrique.length;
    if (long <= 0) continue;
    var nombre = math.max(4, (long / pas).round());
    if (nombre.isOdd) nombre += 1;
    final pasReel = long / nombre;

    // Le sens du contour n'est pas garanti : on le MESURE plutôt que de le
    // supposer. Un point poussé le long de sa normale doit s'éloigner du
    // centre ; sinon, la normale est à l'envers et les pics rentreraient.
    var signe = 1.0;
    {
      final t = metrique.getTangentForOffset(pasReel / 2)!;
      final n = Offset(t.vector.dy, -t.vector.dx);
      if ((t.position - n * 4 - centre).distance >
          (t.position + n * 4 - centre).distance) {
        signe = -1;
      }
    }

    Offset sommet(double d, double h) {
      final t = metrique.getTangentForOffset(d % long)!;
      final n = Offset(t.vector.dy, -t.vector.dx) * signe;
      return t.position + n * h;
    }

    for (var i = 0; i < nombre; i++) {
      final milieu = i * pasReel + pasReel / 2;
      final a = sommet(milieu, i.isOdd ? court : haut);
      final b = sommet(milieu + pasReel, (i + 1).isOdd ? court : haut);
      final fond = sommet(i * pasReel + pasReel, -creux);
      final commande = fond * 2 - (a + b) / 2;
      if (i == 0) sortie.moveTo(a.dx, a.dy);
      sortie.quadraticBezierTo(commande.dx, commande.dy, b.dx, b.dy);
    }
    sortie.close();
  }
  return sortie;
}

/// Les chemins déjà calculés, par taille de bulle.
///
/// `computeMetrics` aplatit les courbes du contour : ce n'est pas cher, mais
/// c'est du travail refait à chaque image pendant qu'on fait défiler une
/// conversation. Les bulles d'une conversation ont peu de tailles différentes
/// — on garde les derniers chemins, et le défilement ne calcule plus rien.
final Map<String, Path> _chemins = {};

/// Au-delà, on vide : une conversation n'a pas besoin de plus, et un cache
/// sans borne est une fuite.
const int _cacheMax = 64;

/// Le fond hérissé d'une bulle de cri.
class PeintreBulleCri extends CustomPainter {
  const PeintreBulleCri({required this.fond, required this.marge});

  /// La couleur de la bulle.
  final Color fond;

  /// La place réservée aux pics tout autour, qui vaut leur hauteur.
  final double marge;

  @override
  void paint(Canvas canvas, Size size) {
    final rayon = Radius.circular(S(kPicRayon));
    final boite = Rect.fromLTWH(
      marge,
      marge,
      size.width - 2 * marge,
      size.height - 2 * marge,
    );
    final peinture = Paint()..color = fond;

    // Une bulle plus petite que ses pics n'arrive pas — la marge fait partie
    // de son rembourrage — mais un contour vide planterait le dessin.
    if (boite.width <= 0 || boite.height <= 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, rayon),
        peinture,
      );
      return;
    }

    final base = RRect.fromRectAndRadius(boite, rayon);
    final cle = '${size.width.round()}x${size.height.round()}@${marge.round()}';
    final chemin = _chemins[cle] ??= cheminBulleCri(
      base,
      haut: S(kPicHaut),
      court: S(kPicCourt),
      pas: S(kPicPas),
      creux: S(kPicCreux),
    );
    if (_chemins.length > _cacheMax) {
      _chemins
        ..clear()
        ..[cle] = chemin;
    }
    canvas.drawPath(chemin, peinture);
  }

  @override
  bool shouldRepaint(PeintreBulleCri ancien) =>
      ancien.fond != fond || ancien.marge != marge;
}
