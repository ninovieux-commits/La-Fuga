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
