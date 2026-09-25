/// La photo de profil, telle que Kivy la dessine (`PiecePhoto._redraw`).
///
/// Trois cas, chacun avec son décor : l'image de Deep Grey plein cadre, le logo
/// sur un carré à la couleur *menu* du thème, la pièce sur un carré à la
/// couleur *plateau*. Sans ce carré la pièce flotte sur le fond de la page ;
/// et sans le nom du thème, les rendus spéciaux — le corps gris de deepgrey,
/// les accents de l'arc-en-ciel — sortent aux couleurs de n'importe quoi.
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

  /// Couleurs des carrés arrondis affichés.
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

  testWidgets('une pièce est posée sur un carré à la couleur du plateau', (
    tester,
  ) async {
    await show(tester, 'insectes|${PieceType.nurse.wire}');
    expect(plates(tester), contains(paletteOf('insectes').board));
  });

  testWidgets('un logo est posé sur un carré à la couleur du menu', (
    tester,
  ) async {
    await show(tester, 'logo|dragon');
    expect(plates(tester), contains(paletteOf('dragon').menu));
  });

  testWidgets('la photo par défaut est le logo du thème original', (
    tester,
  ) async {
    await show(tester, null);
    expect(plates(tester), contains(paletteOf(kDefaultTheme).menu));
  });

  testWidgets('Deep Grey a son image, sans carré de couleur', (tester) async {
    await show(tester, 'deepgrey');
    expect(find.byType(Image), findsOneWidget);
    expect(plates(tester), isEmpty);
  });

  testWidgets('le thème de la photo arrive jusqu au peintre', (tester) async {
    // Le thème deepgrey n'a aucune image de pièce : tout son rendu tient au
    // nom du thème. Si ce nom ne traverse pas, la pièce sort aux couleurs
    // génériques et le corps gris disparaît.
    final canvas = _RecordingCanvas();
    paintPiece(
      canvas,
      const Rect.fromLTWH(0, 0, 80, 80),
      const Piece(PieceType.heritier, Camp.blanc),
      paletteOf('deepgrey'),
      theme: 'deepgrey',
    );
    expect(
      canvas.colors,
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
      isNot(canvas.colors),
      reason:
          'sans le thème, le dessin n est pas le même — '
          'et c est exactement ce qu on perdait',
    );

    // Et à l'écran, le carré de fond est bien celui du thème deepgrey.
    await show(tester, 'deepgrey|${PieceType.heritier.wire}');
    expect(plates(tester), contains(paletteOf('deepgrey').board));
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

  @override
  dynamic noSuchMethod(Invocation invocation) {
    for (final arg in invocation.positionalArguments) {
      if (arg is Paint) colors.add(arg.color.toARGB32());
    }
    return null;
  }
}
