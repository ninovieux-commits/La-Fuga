/// Fabrique les aperçus des bulles de cri, pour que Nino choisisse.
///
/// Ce fichier ne sert qu'à DESSINER : il ne fait pas partie de l'application.
/// On le lance avec `flutter test tool/apercu_bulles_cri.dart`, il écrit des
/// PNG dans `tool/apercus/`.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// La forme
// ---------------------------------------------------------------------------

/// Comment les pics se posent sur le contour.
enum Facon {
  /// Des triangles POSÉS sur le contour : la bulle d'origine reste visible
  /// entre deux pics.
  poses,

  /// Le contour lui-même devient une dent de scie : plus de partie plate.
  scie,

  /// Des triangles posés, mais seulement sur les côtés droits : les coins
  /// arrondis restent lisses.
  cotes,

  /// Une dent de scie dont les creux sont CREUSÉS : d'un pic à l'autre on ne
  /// passe plus par deux droites mais par une courbe qui rentre vers
  /// l'intérieur de la bulle. Les pics alternent deux tailles, et chacun
  /// rejoint ses deux voisins — il n'y a nulle part de partie plate.
  scieCourbe,
}

/// Le contour d'une bulle de cri.
///
/// On part de la bulle qu'on a déjà — un rectangle à coins ronds, dont un
/// coin presque droit fait la pointe du locuteur — et on parcourt ce contour
/// pour y accrocher les pics. Passer par le contour plutôt que par les quatre
/// côtés a un avantage : les coins arrondis sont traités comme le reste, donc
/// les pics y tournent au lieu de s'arrêter.
Path cheminBulleCri(
  RRect base, {
  required double hauteur,
  required double pas,
  Facon facon = Facon.poses,
  double hauteurCourte = 0,
  double creux = 0,
}) {
  final contour = Path()..addRRect(base);
  final centre = base.outerRect.center;
  final sortie = Path();

  for (final metrique in contour.computeMetrics()) {
    final long = metrique.length;
    if (long <= 0) continue;
    var nombre = math.max(4, (long / pas).round());
    // Deux tailles de pics qui alternent demandent un nombre PAIR : sinon le
    // dernier pic retrouve le premier à la même taille, et le contour porte
    // un défaut visible à l'endroit où il se referme.
    if ((hauteurCourte > 0 || facon == Facon.scieCourbe) && nombre.isOdd) {
      nombre += 1;
    }
    final pasReel = long / nombre;

    Offset point(double d) => metrique.getTangentForOffset(d % long)!.position;

    // Le sens du contour n'est pas garanti : on le mesure plutôt que de le
    // supposer. Un point poussé le long de sa normale doit s'ÉLOIGNER du
    // centre ; sinon, la normale est à l'envers.
    double signe = 1;
    {
      final t = metrique.getTangentForOffset(pasReel / 2)!;
      final n = Offset(t.vector.dy, -t.vector.dx);
      final dehors = (t.position + n * 4 - centre).distance;
      final dedans = (t.position - n * 4 - centre).distance;
      if (dedans > dehors) signe = -1;
    }

    Offset sommet(double d, double h) {
      final t = metrique.getTangentForOffset(d % long)!;
      final n = Offset(t.vector.dy, -t.vector.dx) * signe;
      return t.position + n * h;
    }

    // Vrai si le point est sur un côté droit, faux s'il est dans un coin.
    bool surUnCote(Offset p) {
      final r = base.outerRect;
      final rx = math.max(
        math.max(base.tlRadiusX, base.trRadiusX),
        math.max(base.blRadiusX, base.brRadiusX),
      );
      final ry = math.max(
        math.max(base.tlRadiusY, base.trRadiusY),
        math.max(base.blRadiusY, base.brRadiusY),
      );
      final dansX = p.dx > r.left + rx && p.dx < r.right - rx;
      final dansY = p.dy > r.top + ry && p.dy < r.bottom - ry;
      return dansX || dansY;
    }

    sortie.moveTo(point(0).dx, point(0).dy);
    for (var i = 0; i < nombre; i++) {
      final debut = i * pasReel;
      final milieu = debut + pasReel / 2;
      final fin = debut + pasReel;
      final h = hauteurCourte > 0 && i.isOdd ? hauteurCourte : hauteur;

      switch (facon) {
        case Facon.scieCourbe:
          // D'un sommet à l'autre, en passant par un creux qu'on choisit.
          final a = sommet(milieu, h);
          final hSuivant = hauteurCourte > 0 && (i + 1).isOdd
              ? hauteurCourte
              : hauteur;
          final b = sommet(milieu + pasReel, hSuivant);
          // Le fond du creux : sur le contour d'origine, ou plus bas encore.
          final t = sommet(fin, -creux);
          // Pour qu'une courbe quadratique passe EXACTEMENT par ce fond à
          // mi-chemin, son point de commande vaut 2T − (A+B)/2. Viser le fond
          // directement ferait un creux deux fois moins profond.
          final c = t * 2 - (a + b) / 2;
          if (i == 0) sortie.moveTo(a.dx, a.dy);
          sortie.quadraticBezierTo(c.dx, c.dy, b.dx, b.dy);
        case Facon.scie:
          // Le contour disparaît : on va d'un creux à l'autre par le sommet.
          final s = sommet(milieu, h);
          sortie.lineTo(s.dx, s.dy);
          final f = point(fin);
          sortie.lineTo(f.dx, f.dy);
        case Facon.poses:
        case Facon.cotes:
          final aQuart = point(debut + pasReel * 0.25);
          final aTrois = point(debut + pasReel * 0.75);
          if (facon == Facon.cotes && !surUnCote(point(milieu))) {
            // Dans un coin : on suit la bulle, sans pic.
            final f = point(fin);
            sortie.lineTo(f.dx, f.dy);
            continue;
          }
          final s = sommet(milieu, h);
          sortie.lineTo(aQuart.dx, aQuart.dy);
          sortie.lineTo(s.dx, s.dy);
          sortie.lineTo(aTrois.dx, aTrois.dy);
          final f = point(fin);
          sortie.lineTo(f.dx, f.dy);
      }
    }
    sortie.close();
  }
  return sortie;
}

// ---------------------------------------------------------------------------
// Le dessin d'un aperçu
// ---------------------------------------------------------------------------

const double kLargeur = 720;
const Color kClair = Color.fromRGBO(255, 140, 0, 1); // thème « original »
const Color kFonce = Color.fromRGBO(0, 128, 255, 1);
const Color kMenu = Color.fromRGBO(199, 199, 199, 1);

double sf(double x) => x * 1.70;

class Variante {
  const Variante({
    required this.nom,
    required this.legende,
    required this.hauteur,
    required this.pas,
    this.facon = Facon.poses,
    this.hauteurCourte = 0,
    this.creux = 0,
    this.queue = true,
  });

  final String nom;
  final String legende;
  final double hauteur;
  final double pas;
  final Facon facon;
  final double hauteurCourte;

  /// De combien le fond du creux descend SOUS le contour d'origine.
  final double creux;

  /// Garder le coin presque droit du côté du locuteur.
  ///
  /// Sur une bulle ordinaire c'est lui qui fait la pointe, à défaut de queue.
  /// Sur une bulle de cri il ne dit plus rien — le côté et la couleur s'en
  /// chargent — et il casse le hérissement.
  final bool queue;
}

const List<Variante> kVariantes = [
  Variante(
    nom: '1 — Pics fins',
    legende: 'La bulle reste la bulle, bordée de petites dents.',
    hauteur: 7,
    pas: 22,
  ),
  Variante(
    nom: '2 — Pics francs',
    legende: 'Moins nombreux, plus longs : ça crie plus fort.',
    hauteur: 14,
    pas: 36,
  ),
  Variante(
    nom: '3 — Pics sur les côtés',
    legende: 'Les coins arrondis restent lisses : plus carré.',
    hauteur: 13,
    pas: 32,
    facon: Facon.cotes,
  ),
  Variante(
    nom: '4 — Dent de scie',
    legende: 'Tout le contour devient pic, comme en BD.',
    hauteur: 12,
    pas: 32,
    facon: Facon.scie,
  ),
  Variante(
    nom: '5 — Pics alternés',
    legende: 'Un long, un court : le contour vibre.',
    hauteur: 16,
    pas: 24,
    hauteurCourte: 6,
  ),
];

/// La dent de scie retravaillée : courbes rentrantes, deux tailles de pics.
const List<Variante> kScies = [
  Variante(
    nom: 'A — Creux doux',
    legende: 'La courbe passe par le contour d\'origine : creux nul.',
    hauteur: 15,
    hauteurCourte: 7,
    pas: 30,
    facon: Facon.scieCourbe,
  ),
  Variante(
    nom: 'B — Creux marqué',
    legende: 'Le fond descend de 5 sous le contour : ça mord.',
    hauteur: 15,
    hauteurCourte: 7,
    pas: 30,
    creux: 5,
    facon: Facon.scieCourbe,
  ),
  Variante(
    nom: 'C — Fort contraste',
    legende: 'Un grand, un petit : 19 contre 6.',
    hauteur: 19,
    hauteurCourte: 6,
    pas: 30,
    creux: 4,
    facon: Facon.scieCourbe,
  ),
  Variante(
    nom: 'D — Pics serrés',
    legende: 'Plus nombreux et plus courts : une bulle qui grésille.',
    hauteur: 12,
    hauteurCourte: 5,
    pas: 21,
    creux: 3,
    facon: Facon.scieCourbe,
  ),
];

/// Creux marqués, pics larges, et plus de coin-pointe.
const List<Variante> kLarges = [
  Variante(
    nom: 'E — Larges',
    legende: 'Un pic tous les 38, hauteur 16 et 8.',
    hauteur: 16,
    hauteurCourte: 8,
    pas: 38,
    creux: 5,
    facon: Facon.scieCourbe,
    queue: false,
  ),
  Variante(
    nom: 'F — Plus larges',
    legende: 'Un pic tous les 46, hauteur 18 et 8.',
    hauteur: 18,
    hauteurCourte: 8,
    pas: 46,
    creux: 6,
    facon: Facon.scieCourbe,
    queue: false,
  ),
  Variante(
    nom: 'G — Très larges',
    legende: 'Un pic tous les 56, hauteur 20 et 9.',
    hauteur: 20,
    hauteurCourte: 9,
    pas: 56,
    creux: 7,
    facon: Facon.scieCourbe,
    queue: false,
  ),
  Variante(
    nom: 'H — Larges et profonds',
    legende: 'Comme F, mais le creux descend de 10 : ça mord franchement.',
    hauteur: 18,
    hauteurCourte: 8,
    pas: 46,
    creux: 10,
    facon: Facon.scieCourbe,
    queue: false,
  ),
];

/// Peint une bulle et rend la hauteur occupée.
double peintBulle(
  Canvas? canvas,
  double y,
  String texte, {
  required bool deMoi,
  required Variante? v,
}) {
  final marge = v == null ? 0.0 : v.hauteur;
  final peintre = TextPainter(
    text: TextSpan(
      text: texte,
      style: TextStyle(
        color: deMoi ? Colors.black : Colors.white,
        fontSize: sf(16),
        fontFamily: 'Roboto',
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: kLargeur * 0.75 - 28 - 2 * marge);

  final l = peintre.width + 28;
  final h = peintre.height + 20;
  final x = deMoi ? kLargeur - 16 - marge - l : 16 + marge;
  final boite = Rect.fromLTWH(x, y + marge, l, h);

  final rayon = const Radius.circular(18);
  final pointe = const Radius.circular(4);
  final sansQueue = v != null && !v.queue;
  final base = RRect.fromRectAndCorners(
    boite,
    topLeft: rayon,
    topRight: rayon,
    bottomLeft: deMoi || sansQueue ? rayon : pointe,
    bottomRight: !deMoi || sansQueue ? rayon : pointe,
  );

  final fond = Paint()..color = deMoi ? kClair : kFonce;
  if (canvas != null) {
    if (v == null) {
      canvas.drawRRect(base, fond);
    } else {
      canvas.drawPath(
        cheminBulleCri(
          base,
          hauteur: v.hauteur,
          pas: v.pas,
          facon: v.facon,
          hauteurCourte: v.hauteurCourte,
          creux: v.creux,
        ),
        fond,
      );
    }
    peintre.paint(canvas, Offset(boite.left + 14, boite.top + 10));
  }
  return h + 2 * marge + 10;
}

double titre(Canvas? canvas, double y, String texte, double taille, Color c) {
  final p = TextPainter(
    text: TextSpan(
      text: texte,
      style: TextStyle(
        color: c,
        fontSize: taille,
        fontWeight: FontWeight.bold,
        fontFamily: 'Roboto',
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: kLargeur - 32);
  p.paint(canvas ?? Canvas(ui.PictureRecorder()), Offset(16, y));
  return p.height;
}

Future<void> ecris(String nom, double Function(Canvas?) dessin) async {
  // Un premier passage à blanc donne la hauteur exacte de la planche : une
  // hauteur devinée rogne les pics du bas ou laisse un vide.
  final hauteur = dessin(null) + 16;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(2); // de la finesse pour regarder sur un téléphone
  canvas.drawRect(
    Rect.fromLTWH(0, 0, kLargeur, hauteur),
    Paint()..color = kMenu,
  );
  dessin(canvas);
  final image = await recorder.endRecording().toImage(
    (kLargeur * 2).round(),
    (hauteur * 2).round(),
  );
  final octets = await image.toByteData(format: ui.ImageByteFormat.png);
  File(
    'tool/apercus/$nom.png',
  ).writeAsBytesSync(Uint8List.view(octets!.buffer));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('les aperçus des bulles de cri', () async {
    // Sans cela le texte sort en rectangles noirs : la police des tests n'a
    // pas de glyphes. On prend celle de l'application.
    final police = FontLoader('Roboto')
      ..addFont(
        File(
          '/opt/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
        ).readAsBytes().then((o) => ByteData.view(o.buffer)),
      );
    await police.load();

    const court = 'Et paf !';
    const moyen = "Tu vas voir ce que tu vas voir !?";
    const long =
        "J'arrive pas à y croire, t'as vraiment poussé le garde là-dedans !";

    // Une planche par variante.
    for (var i = 0; i < kVariantes.length; i++) {
      final v = kVariantes[i];
      await ecris('bulle_cri_${i + 1}', (canvas) {
        var y = 14.0;
        y += titre(canvas, y, v.nom, sf(17), Colors.black87) + 4;
        y += titre(canvas, y, v.legende, sf(12), Colors.black54) + 14;
        y += peintBulle(canvas, y, court, deMoi: false, v: v);
        y += peintBulle(canvas, y, moyen, deMoi: true, v: v);
        y += peintBulle(canvas, y, long, deMoi: false, v: v);
        return y;
      });
    }

    // La dent de scie retravaillée.
    for (var i = 0; i < kScies.length; i++) {
      final v = kScies[i];
      await ecris('scie_courbe_${String.fromCharCode(97 + i)}', (canvas) {
        var y = 14.0;
        y += titre(canvas, y, v.nom, sf(17), Colors.black87) + 4;
        y += titre(canvas, y, v.legende, sf(12), Colors.black54) + 14;
        y += peintBulle(canvas, y, court, deMoi: false, v: v);
        y += peintBulle(canvas, y, moyen, deMoi: true, v: v);
        y += peintBulle(canvas, y, long, deMoi: false, v: v);
        return y;
      });
    }

    await ecris('scie_courbe_comparaison', (canvas) {
      var y = 14.0;
      y +=
          titre(
            canvas,
            y,
            'Dents de scie courbes, sur le même cri',
            sf(17),
            Colors.black87,
          ) +
          14;
      y +=
          titre(
            canvas,
            y,
            "4 — l'ancienne, à droites et d'une seule taille",
            sf(11),
            Colors.black54,
          ) +
          6;
      y += peintBulle(canvas, y, moyen, deMoi: false, v: kVariantes[3]) + 10;
      for (final v in kScies) {
        y += titre(canvas, y, v.nom, sf(11), Colors.black54) + 6;
        y += peintBulle(canvas, y, moyen, deMoi: false, v: v) + 10;
      }
      return y;
    });

    // Creux marqués, pics larges, sans coin-pointe.
    for (var i = 0; i < kLarges.length; i++) {
      final v = kLarges[i];
      await ecris('large_${String.fromCharCode(101 + i)}', (canvas) {
        var y = 14.0;
        y += titre(canvas, y, v.nom, sf(17), Colors.black87) + 4;
        y += titre(canvas, y, v.legende, sf(12), Colors.black54) + 14;
        y += peintBulle(canvas, y, court, deMoi: false, v: v);
        y += peintBulle(canvas, y, moyen, deMoi: true, v: v);
        y += peintBulle(canvas, y, long, deMoi: false, v: v);
        return y;
      });
    }

    await ecris('large_comparaison', (canvas) {
      var y = 14.0;
      y +=
          titre(
            canvas,
            y,
            'Pics larges, sans coin-pointe',
            sf(17),
            Colors.black87,
          ) +
          14;
      y +=
          titre(
            canvas,
            y,
            'B — pics de 30, et le coin-pointe encore là',
            sf(11),
            Colors.black54,
          ) +
          6;
      y += peintBulle(canvas, y, moyen, deMoi: false, v: kScies[1]) + 10;
      for (final v in kLarges) {
        y += titre(canvas, y, v.nom, sf(11), Colors.black54) + 6;
        y += peintBulle(canvas, y, moyen, deMoi: false, v: v) + 10;
      }
      return y;
    });

    // La planche de comparaison : le même message, les cinq façons, et la
    // bulle d'aujourd'hui en tête pour voir ce qu'on ajoute.
    await ecris('bulle_cri_comparaison', (canvas) {
      var y = 14.0;
      y +=
          titre(
            canvas,
            y,
            'Les cinq façons, sur le même cri',
            sf(17),
            Colors.black87,
          ) +
          14;
      y +=
          titre(canvas, y, "Aujourd'hui, sans pics", sf(11), Colors.black54) +
          6;
      y += peintBulle(canvas, y, moyen, deMoi: false, v: null) + 10;
      for (final v in kVariantes) {
        y += titre(canvas, y, v.nom, sf(11), Colors.black54) + 6;
        y += peintBulle(canvas, y, moyen, deMoi: false, v: v) + 10;
      }
      return y;
    });
  });
}
