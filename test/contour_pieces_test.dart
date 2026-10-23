/// Le contour d'une pièce est pur : blanc pour les Blancs, noir pour les
/// Noirs.
///
/// Nino : « il y a un effet d'optique qui donne l'impression que les pièces
/// noires sont plus petites que les blanches. J'aimerai que le contour des
/// pièces noires soit parfaitement noir et le contour des blanches
/// parfaitement blanc (tous thèmes non spéciaux). »
///
/// Le contour se peint à cheval sur le bord : c'est sa moitié extérieure qui
/// décide de la taille qu'on croit voir. Un gris autour d'un fond crème s'y
/// fond et agrandit la pièce ; le bleu nuit des Noirs faisait de même, mais
/// moins. Deux contours purs tranchent des deux côtés, et le bord tombe au
/// même endroit pour les deux camps.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/widgets/piece_painter.dart';

/// Les pixels d'une pièce peinte sur un fond neutre.
Future<List<int>> rendre(Camp camp) async {
  const cote = 80.0;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  // Un fond qui n'est ni blanc ni noir : les deux contours doivent s'y voir.
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, cote, cote),
    Paint()..color = const Color(0xFF808080),
  );
  paintPiece(
    canvas,
    const Rect.fromLTWH(0, 0, cote, cote),
    Piece(PieceType.soldat, camp),
    paletteOf('original'),
    outlineWidth: 3,
  );
  final img = await rec.endRecording().toImage(cote.toInt(), cote.toInt());
  final d = await img.toByteData();
  return List<int>.generate(d!.lengthInBytes, d.getUint8);
}

int compte(List<int> px, int r, int v, int b) {
  var n = 0;
  for (var i = 0; i + 3 < px.length; i += 4) {
    if (px[i] == r && px[i + 1] == v && px[i + 2] == b && px[i + 3] == 255) {
      n++;
    }
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('les deux constantes sont pures', () {
    expect(FugaColors.whiteOutline, const Color(0xFFFFFFFF));
    expect(FugaColors.blackOutline, const Color(0xFF000000));
  });

  test('une pièce blanche porte un contour blanc pur', () async {
    final px = await rendre(Camp.blanc);
    expect(
      compte(px, 255, 255, 255),
      greaterThan(50),
      reason: 'le contour doit être peint, et peint en blanc pur',
    );
  });

  test('une pièce noire porte un contour noir pur', () async {
    final px = await rendre(Camp.noir);
    expect(
      compte(px, 0, 0, 0),
      greaterThan(50),
      reason: 'le contour doit être peint, et peint en noir pur',
    );
  });

  test('aucune pièce ne garde les anciens contours', () async {
    for (final camp in Camp.values) {
      final px = await rendre(camp);
      expect(compte(px, 222, 222, 222), 0, reason: 'ancien gris des Blancs');
      expect(compte(px, 51, 51, 84), 0, reason: 'ancien bleu nuit des Noirs');
    }
  });
}
