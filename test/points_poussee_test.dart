/// Les points de poussée, sur TOUS les thèmes.
///
/// Nino : « quand on utilise un thème spécial, il n'y a pas les points de
/// marquage de poussée quand une pièce a poussé. Il faut qu'ils y soient,
/// partout tout le temps. »
///
/// Le dessin d'une pièce à images porte déjà ses quatre points — ils font
/// partie de l'image. Ce qui manquait, c'est le marquage des directions
/// ENCORE jouables après une poussée : le rendu à images s'arrêtait à
/// l'image, et l'information disparaissait dès qu'on quittait les thèmes
/// géométriques.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/widgets/piece_painter.dart';
import 'package:lafuga/ui/widgets/theme_image_cache.dart';

/// Une image de pièce, uniforme : ce qui compte est ce qu'on dessine PAR
/// DESSUS, pas elle.
Future<ui.Image> carre(Color couleur, {int cote = 64}) async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(
    Rect.fromLTWH(0, 0, cote.toDouble(), cote.toDouble()),
    Paint()..color = couleur,
  );
  return rec.endRecording().toImage(cote, cote);
}

/// Les pixels d'un rendu, pour les comparer.
Future<List<int>> rendre(
  Piece piece, {
  LoadedThemeImages? images,
  List<(int, int)> disponibles = const [],
  String? theme,
}) async {
  const cote = 80.0;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, cote, cote),
    Paint()..color = const Color(0xFF404040),
  );
  paintPiece(
    canvas,
    const Rect.fromLTWH(0, 0, cote, cote),
    piece,
    paletteOf(theme ?? 'original'),
    images: images,
    theme: theme,
    pushHighlightDirs: disponibles,
  );
  final img = await rec.endRecording().toImage(cote.toInt(), cote.toInt());
  final d = await img.toByteData();
  return List<int>.generate(d!.lengthInBytes, d.getUint8);
}

int ecart(List<int> a, List<int> b) {
  var n = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) n++;
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LoadedThemeImages themeAImages;

  setUp(() async {
    // Un thème dont toutes les pièces sont des images, comme medieval ou
    // insectes.
    final blanche = await carre(const Color(0xFFE8E0C8));
    final noire = await carre(const Color(0xFF1A1A2E));
    themeAImages = LoadedThemeImages(
      pieces: {
        for (final t in PieceType.values) ...{
          (t, Camp.blanc): blanche,
          (t, Camp.noir): noire,
        },
      },
    );
  });

  group('Sur un thème à IMAGES', () {
    test('le Soldat marque ses directions encore jouables', () async {
      const soldat = Piece(PieceType.soldat, Camp.blanc);
      final sans = await rendre(soldat, images: themeAImages);
      final avec = await rendre(
        soldat,
        images: themeAImages,
        disponibles: const [(1, 1)],
      );
      expect(
        ecart(sans, avec),
        greaterThan(100),
        reason:
            'aucun point n a été posé sur l image : '
            '${ecart(sans, avec)} pixels de différence',
      );
    });

    test('le Garde aussi', () async {
      const garde = Piece(PieceType.garde, Camp.noir);
      final sans = await rendre(garde, images: themeAImages);
      final avec = await rendre(
        garde,
        images: themeAImages,
        disponibles: const [(0, 1)],
      );
      expect(ecart(sans, avec), greaterThan(100));
    });

    test('deux directions marquent DEUX fois plus', () async {
      const soldat = Piece(PieceType.soldat, Camp.blanc);
      final sans = await rendre(soldat, images: themeAImages);
      final une = ecart(
        sans,
        await rendre(soldat, images: themeAImages, disponibles: const [(1, 1)]),
      );
      final deux = ecart(
        sans,
        await rendre(
          soldat,
          images: themeAImages,
          disponibles: const [(1, 1), (-1, -1)],
        ),
      );
      expect(deux, greaterThan(une * 1.5));
    });

    test('et sans poussée disponible, rien n est ajouté', () async {
      // L'image seule : une pièce qui n'a pas poussé ne porte aucune marque
      // de plus.
      const soldat = Piece(PieceType.soldat, Camp.blanc);
      final a = await rendre(soldat, images: themeAImages);
      final b = await rendre(soldat, images: themeAImages);
      expect(ecart(a, b), 0);
    });

    test('une pièce qui ne pousse PAS n en reçoit aucun', () async {
      // L'Héritier ne pousse pas : lui en poser serait inventer une règle.
      const heritier = Piece(PieceType.heritier, Camp.blanc);
      final sans = await rendre(heritier, images: themeAImages);
      final avec = await rendre(
        heritier,
        images: themeAImages,
        disponibles: const [(1, 1)],
      );
      expect(ecart(sans, avec), 0);
    });
  });

  group('Sur un thème géométrique, rien ne change', () {
    test('le Soldat marque toujours ses directions', () async {
      const soldat = Piece(PieceType.soldat, Camp.blanc);
      final sans = await rendre(soldat);
      final avec = await rendre(soldat, disponibles: const [(1, 1)]);
      expect(ecart(sans, avec), greaterThan(50));
    });
  });

  group('La définition de la poussée est UNE', () {
    test('le Soldat pousse en diagonale, le Garde en orthogonal', () {
      expect(pousseeDe(PieceType.soldat)!.dirs, const [
        (-1, -1),
        (1, -1),
        (-1, 1),
        (1, 1),
      ]);
      expect(pousseeDe(PieceType.garde)!.dirs, const [
        (0, -1),
        (0, 1),
        (-1, 0),
        (1, 0),
      ]);
    });

    test('et les autres ne poussent pas', () {
      for (final t in PieceType.values) {
        if (t == PieceType.soldat || t == PieceType.garde) continue;
        expect(pousseeDe(t), isNull, reason: '$t');
      }
    });
  });
}
