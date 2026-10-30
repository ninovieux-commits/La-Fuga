/// La pièce qu'on tient en main, dans le composeur de position.
///
/// Elle portait une plaque de couleur translucide par-dessous — le vieux
/// langage de sélection. Nino l'avait écarté partout ailleurs : « la couleur
/// de sélection ne me convient pas, c'est pas clair. Et pourquoi on mettrait
/// pas plutôt la pièce en "enfoncée" ? » Le composeur était le dernier
/// endroit à parler l'ancien ; il parle maintenant le même langage que le
/// plateau — la pièce s'atténue, son contour reste net.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/widgets/piece_tile.dart';

/// Un gris franc, ni blanc ni noir : le contour blanc des Blancs s'y voit,
/// et une plaque de couleur aussi.
const Color _fond = Color(0xFF808080);
const double _cote = 80;

final GlobalKey _cadre = GlobalKey();

/// Les pixels d'une tuile, choisie ou non.
///
/// La capture ET la lecture des octets passent par `runAsync` : hors de lui,
/// le temps du test est faux et `toByteData` ne rend jamais la main.
Future<List<int>> _rendre(WidgetTester tester, {required bool enMain}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: _cadre,
          child: Container(
            width: _cote,
            height: _cote,
            color: _fond,
            child: PieceTile(
              piece: const Piece(PieceType.soldat, Camp.blanc),
              palette: paletteOf('original'),
              selected: enMain,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final limite =
      _cadre.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final octets = await tester.runAsync(() async {
    final image = await limite.toImage();
    return image.toByteData();
  });
  final d = octets!;
  return List<int>.generate(d.lengthInBytes, d.getUint8);
}

int _compte(List<int> px, Color couleur) {
  var n = 0;
  for (var i = 0; i + 3 < px.length; i += 4) {
    if (px[i] == (couleur.r * 255).round() &&
        px[i + 1] == (couleur.g * 255).round() &&
        px[i + 2] == (couleur.b * 255).round() &&
        px[i + 3] == 255) {
      n++;
    }
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('plus de plaque de couleur sous la pièce en main', (
    tester,
  ) async {
    final libre = await _rendre(tester, enMain: false);
    final enMain = await _rendre(tester, enMain: true);

    // Les coins de la tuile sont hors de la pièce : ils montraient la plaque,
    // ils montrent maintenant le fond, exactement comme sans sélection.
    final fondLibre = _compte(libre, _fond);
    expect(fondLibre, greaterThan(0), reason: 'repère : le fond se voit');
    expect(
      _compte(enMain, _fond),
      fondLibre,
      reason: 'une plaque par-dessous repeindrait tout le carré',
    );
  });

  testWidgets('la pièce en main s atténue, son contour reste net', (
    tester,
  ) async {
    final libre = await _rendre(tester, enMain: false);
    final enMain = await _rendre(tester, enMain: true);

    // Le crème des Blancs s'efface : c'est ce qu'« enfoncée » veut dire.
    const creme = FugaColors.whitePiece;
    expect(_compte(libre, creme), greaterThan(0), reason: 'repère');
    expect(
      _compte(enMain, creme),
      lessThan(_compte(libre, creme) ~/ 2),
      reason: 'la pièce choisie doit s atténuer',
    );

    // Le contour, lui, est repeint par-dessus à pleine opacité. Nino :
    // « j'aimerais que le trait noir qui fait le tour de la pièce (ou blanc
    // quand il s'agit des blancs) ne soit pas concerné par la transparence. »
    expect(
      _compte(enMain, FugaColors.whiteOutline),
      greaterThan(0),
      reason: 'le contour blanc doit rester pur',
    );
  });
}
