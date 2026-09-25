/// La photo de profil : une pièce, un logo, ou l'image de Deep Grey.
///
/// Portage de `PiecePhoto._redraw`, **sans** le carré de fond coloré de Kivy :
/// le dessin se pose directement sur la page. Ce que ce fichier surveille, en
/// revanche, c'est que le thème de la photo arrive jusqu'au dessin — sinon les
/// rendus spéciaux (le corps gris de deepgrey, les accents de l'arc-en-ciel)
/// sortent aux couleurs du premier thème venu.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/widgets/piece_painter.dart';
import 'package:lafuga/ui/widgets/profile_photo.dart';

void main() {
  Future<void> show(WidgetTester tester, String? photo) => tester.pumpWidget(
    MaterialApp(
      home: Center(child: ProfilePhoto(photo: photo, size: 80)),
    ),
  );

  /// Les carrés arrondis colorés affichés — il ne doit y en avoir aucun.
  List<Color> plates(WidgetTester tester) => [
    for (final box in tester.widgetList<DecoratedBox>(
      find.byType(DecoratedBox),
    ))
      if (box.decoration case BoxDecoration(
        :final color,
        borderRadius: != null,
      ))
        if (color != null) color,
  ];

  testWidgets('une pièce se pose sans carré de fond', (tester) async {
    await show(tester, 'insectes|${PieceType.nurse.wire}');
    expect(find.byType(CustomPaint), findsWidgets);
    expect(plates(tester), isEmpty);
  });

  testWidgets('un logo se pose sans carré de fond', (tester) async {
    await show(tester, 'logo|dragon');
    expect(plates(tester), isEmpty);
  });

  testWidgets('Deep Grey a son image, sans carré de fond', (tester) async {
    await show(tester, 'deepgrey');
    expect(find.byType(Image), findsOneWidget);
    expect(plates(tester), isEmpty);
  });

  testWidgets('la photo par défaut est le logo du thème original', (
    tester,
  ) async {
    await show(tester, null);
    final image = tester.widget<Image>(find.byType(Image));
    expect('${image.image}', contains(logoAssetOf(kDefaultTheme)));
  });

  test('le thème de la photo change le dessin de la pièce', () {
    // Le thème deepgrey n'a aucune image de pièce : tout son rendu tient au
    // nom du thème. S'il ne traverse pas, la pièce perd son corps gris.
    final avecTheme = _RecordingCanvas();
    paintPiece(
      avecTheme,
      const Rect.fromLTWH(0, 0, 80, 80),
      const Piece(PieceType.heritier, Camp.blanc),
      paletteOf('deepgrey'),
      theme: 'deepgrey',
    );
    expect(
      avecTheme.colors,
      contains(kDeepGreyBody.toARGB32()),
      reason: 'le corps gris de deepgrey',
    );

    final sansTheme = _RecordingCanvas();
    paintPiece(
      sansTheme,
      const Rect.fromLTWH(0, 0, 80, 80),
      const Piece(PieceType.heritier, Camp.blanc),
      paletteOf('deepgrey'),
    );
    expect(
      sansTheme.colors,
      isNot(avecTheme.colors),
      reason: 'sans le thème, le dessin n est pas le même',
    );
  });

  group('Le grossissement de certaines photos', () {
    test('la nurse du thème insectes est grossie de 15 %', () {
      expect(profileZoomFor('insectes', PieceType.nurse), 1.15);
    });

    test('et elle seule', () {
      expect(profileZoomFor('insectes', PieceType.heritier), 1);
      expect(profileZoomFor('insectes', PieceType.soldat), 1);
      expect(profileZoomFor('fleur', PieceType.nurse), 1);
      expect(profileZoomFor(null, PieceType.nurse), 1);
    });

    test('le cadre ne bouge pas : c est un zoom, pas un débordement', () {
      const frame = Rect.fromLTWH(10, 20, 80, 80);

      final zoome = _RecordingCanvas();
      paintProfilePiece(
        zoome,
        frame,
        const Piece(PieceType.nurse, Camp.blanc),
        paletteOf('insectes'),
        theme: 'insectes',
      );
      expect(
        zoome.clips,
        contains(frame),
        reason: 'ce qui dépasse est coupé au cadre',
      );
      // Le même dessin sans grossissement, pour comparer.
      final normal = _RecordingCanvas();
      paintProfilePiece(
        normal,
        frame,
        const Piece(PieceType.nurse, Camp.blanc),
        paletteOf('fleur'),
        theme: 'fleur',
      );
      expect(
        normal.widest,
        greaterThan(0),
        reason: 'quelque chose est dessiné',
      );
      expect(
        zoome.widest / normal.widest,
        moreOrLessEquals(1.15, epsilon: 0.001),
        reason: 'la coccinelle est dessinée 15 % plus grande',
      );

      final autrePiece = _RecordingCanvas();
      paintProfilePiece(
        autrePiece,
        frame,
        const Piece(PieceType.heritier, Camp.blanc),
        paletteOf('insectes'),
        theme: 'insectes',
      );
      expect(autrePiece.clips, isEmpty, reason: 'rien à couper sans zoom');
      expect(autrePiece.widest, lessThanOrEqualTo(80.0));
    });
  });

  test(
    'une photo illisible retombe sur l Héritier blanc du thème original',
    () {
      final parts = parsePhoto('nimportequoi');
      expect(parts.theme, kDefaultTheme);
      expect(parts.piece, PieceType.heritier);
      expect(parts.camp, Camp.blanc);
    },
  );
}

/// Un `Canvas` qui ne dessine rien et retient les couleurs demandées.
///
/// Les couleurs sont gardées en ARGB : un `Color` repassé par un `Paint` ne
/// revient pas forcément égal, au bit près, à la constante d'origine.
class _RecordingCanvas implements Canvas {
  final List<int> colors = [];

  /// Rectangles passés à `clipRect`.
  final List<Rect> clips = [];

  /// Tailles demandées au canevas : côtés de rectangles et diamètres de
  /// cercles. Une pièce se dessine de l'une ou l'autre façon, selon que son
  /// thème a des images ou non.
  final List<double> sizes = [];

  /// La plus grande dimension dessinée.
  double get widest =>
      sizes.isEmpty ? 0 : sizes.reduce((a, b) => a > b ? a : b);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    for (final arg in invocation.positionalArguments) {
      if (arg is Paint) colors.add(arg.color.toARGB32());
      if (arg is Rect) {
        if (name.contains('clipRect')) {
          clips.add(arg);
        } else {
          sizes.add(arg.width);
        }
      }
      // Rayon d'un cercle : le rendu géométrique d'une ronde.
      if (arg is double) sizes.add(arg * 2);
    }
    return null;
  }
}
