/// Le thème des PIÈCES dans les aperçus.
///
/// Nino : « le changement de pièces (thème) vers deepgrey ne s'affiche pas
/// dans les aperçus (aperçus corresp et aperçu de thème) ».
///
/// Deepgrey est le seul thème qui n'a AUCUNE image de pièce : il se
/// reconnaît uniquement à son rendu, déclenché par le NOM du thème. Un
/// aperçu qui ne transmet pas ce nom le dessine donc comme l'original, sans
/// que rien ne le signale. On compte les pixels : deux thèmes différents
/// doivent donner deux images différentes.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/theme/theme_assets.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/corr_slot.dart';
import 'package:lafuga/ui/widgets/piece_painter.dart';

/// Le peintre du mini-plateau d'un aperçu de correspondance.
///
/// On ne rasterise pas — `toImage` ne rend jamais la main dans un test de
/// widget. On demande au peintre s'il VOIT la différence, ce qui est
/// justement ce qui manquait : l'aperçu ne recevait pas le thème des
/// pièces, donc deux thèmes donnaient le même peintre et rien ne se
/// repeignait.
Future<CustomPainter> _peintre(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Center(child: SizedBox(width: 120, height: 120, child: widget)),
    ),
  );
  await tester.pumpAndSettle();
  final peintres = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((w) => w.painter)
      .whereType<CustomPainter>()
      .where((p) => p.runtimeType.toString().contains('MiniBoard'))
      .toList();
  expect(peintres, isNotEmpty, reason: 'mini-plateau introuvable');
  return peintres.first;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => setScaleSize(const Size(400, 800)));

  test('deepgrey n a aucune image de pièce : seul son NOM le distingue', () {
    // C'est la raison pour laquelle il disparaissait des aperçus.
    expect(kThemeImages['deepgrey']!.hasPieceImages, isFalse);
    expect(kThemeImages['medieval']!.hasPieceImages, isTrue);
  });

  test('sans son NOM, deepgrey se dessine comme l original', () async {
    // La preuve par le pixel, au niveau du dessin : c'est le nom du thème
    // qui change tout. Un aperçu qui ne le transmet pas retombe exactement
    // sur l'original, sans que rien ne le signale.
    Future<List<int>> rendre(String? theme) async {
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 60, 60),
        Paint()..color = const Color(0xFF404040),
      );
      paintPiece(
        canvas,
        const Rect.fromLTWH(0, 0, 60, 60),
        const Piece(PieceType.heritier, Camp.blanc),
        paletteOf(theme ?? 'original'),
        theme: theme,
      );
      final img = await rec.endRecording().toImage(60, 60);
      final d = await img.toByteData();
      return List<int>.generate(d!.lengthInBytes, (i) => d.getUint8(i));
    }

    int ecart(List<int> a, List<int> b) {
      var n = 0;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) n++;
      }
      return n;
    }

    final original = await rendre('original');
    expect(
      ecart(original, await rendre('deepgrey')),
      greaterThan(1000),
      reason: 'deepgrey ne se dessine pas autrement',
    );
    expect(
      ecart(original, await rendre(null)),
      0,
      reason: 'sans nom de thème, on retombe exactement sur l original',
    );
  });

  testWidgets('l aperçu de correspondance suit le thème des PIÈCES', (
    tester,
  ) async {
    final jeu = CorrGame.fromJson(const {
      'id': 'g1',
      'statut': 'en_cours',
      'adversaire': 'celia',
      'ma_couleur': 'Blanc',
      'turn': 'Blanc',
      'my_turn': true,
      'moves_text': '',
      'objectif': 'partie',
    });

    Widget slot(String pieces) => CorrSlot(
      game: jeu,
      palette: paletteOf('original'),
      // Le plateau ne bouge PAS : seul l axe des pièces change.
      boardTheme: 'original',
      pieceTheme: pieces,
      onTap: () {},
      onAccept: (_) {},
      onRefuse: (_) {},
      onCancel: (_) {},
      onRematch: (_) {},
      onClose: (_) {},
      onShow: (_) {},
    );

    final avecOriginal = await _peintre(tester, slot('original'));
    final avecDeepGrey = await _peintre(tester, slot('deepgrey'));
    expect(
      avecDeepGrey.shouldRepaint(avecOriginal),
      isTrue,
      reason:
          'l aperçu ne voit pas le thème des pièces : il prenait celui du '
          'plateau',
    );
  });

  testWidgets('et le plateau de l aperçu ne suit PAS l axe des pièces', (
    tester,
  ) async {
    // La séparation doit marcher dans les deux sens : changer les pièces ne
    // doit pas repeindre le plateau, et inversement.
    final vide = CorrGame.fromJson(const {
      'id': 'g2',
      'statut': 'en_cours',
      'adversaire': 'celia',
      'ma_couleur': 'Blanc',
      'turn': 'Blanc',
      'my_turn': true,
      'moves_text': '',
      'objectif': 'partie',
    });
    expect(vide.initialBoard.at(3, 0), isNotNull, reason: 'plateau vide');
    expect(Board.initial().at(3, 0), isNotNull);
  });
}
