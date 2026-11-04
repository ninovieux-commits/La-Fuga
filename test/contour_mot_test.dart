/// Le contour noir d'un mot tombe EXACTEMENT sur ses lettres.
///
/// Nino, devant les mélos du classement : « je ne veux pas que les mélos
/// dans le classement soient en perspective. » Le contour s'obtenait en
/// retraçant le mot avec un `TextPainter` à part : un tracé mesure plus
/// large et plus haut que le même texte plein, le peintre se centrait donc
/// sur une autre boîte que les lettres, et le noir glissait de trois points
/// vers le haut et la gauche — un relief.
///
/// Ce test COMPTE LES PIXELS, parce que c'est la seule mesure qui parle du
/// défaut : l'arbre des widgets, lui, était parfaitement sain.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/ui/widgets/picto_touche.dart';

const Key _cadre = Key('cadre');

/// Les bords de l'encre d'une couleur, dans l'image rendue.
({int gauche, int haut, int droite, int bas})? _bords(
  ByteData image,
  int largeur,
  int hauteur,
  bool Function(int r, int g, int b) estDeLaCouleur,
) {
  int? gauche, haut, droite, bas;
  for (var y = 0; y < hauteur; y++) {
    for (var x = 0; x < largeur; x++) {
      final i = (y * largeur + x) * 4;
      if (!estDeLaCouleur(
        image.getUint8(i),
        image.getUint8(i + 1),
        image.getUint8(i + 2),
      )) {
        continue;
      }
      haut ??= y;
      bas = y;
      if (gauche == null || x < gauche) gauche = x;
      if (droite == null || x > droite) droite = x;
    }
  }
  if (haut == null) return null;
  return (gauche: gauche!, haut: haut, droite: droite!, bas: bas!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('le noir déborde d autant de tous les côtés', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RepaintBoundary(
          key: _cadre,
          child: ColoredBox(
            color: Color(0xFFFFFFFF),
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: MotTouche(
                  texte: '1930',
                  couleur: Color(0xFF0080FF),
                  style: TextStyle(fontSize: 60, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    late ByteData image;
    late int largeur;
    late int hauteur;
    await tester.runAsync(() async {
      final limite =
          tester.renderObject(find.byKey(_cadre)) as RenderRepaintBoundary;
      final rendu = await limite.toImage();
      largeur = rendu.width;
      hauteur = rendu.height;
      image = (await rendu.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    });

    final bleu = _bords(
      image,
      largeur,
      hauteur,
      (r, g, b) => b > 200 && r < 90,
    );
    final noir = _bords(image, largeur, hauteur, (r, g, b) => r + g + b < 120);
    expect(bleu, isNotNull, reason: 'le mot doit être peint');
    expect(noir, isNotNull, reason: 'le contour doit être peint');

    final debords = <String, int>{
      'à gauche': bleu!.gauche - noir!.gauche,
      'à droite': noir.droite - bleu.droite,
      'en haut': bleu.haut - noir.haut,
      'en bas': noir.bas - bleu.bas,
    };
    for (final d in debords.entries) {
      expect(
        d.value,
        greaterThan(0),
        reason: 'le contour doit dépasser ${d.key}',
      );
    }
    final valeurs = debords.values.toList();
    final mini = valeurs.reduce((a, b) => a < b ? a : b);
    final maxi = valeurs.reduce((a, b) => a > b ? a : b);
    expect(
      maxi - mini,
      lessThanOrEqualTo(1),
      reason:
          'le contour doit déborder également partout, sinon le mot paraît '
          'en relief — mesuré : $debords',
    );
  });
}
