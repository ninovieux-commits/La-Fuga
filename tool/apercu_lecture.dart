/// Aperçu du MODE LECTURE refait, pour que Nino le voie avant de télécharger.
///
/// Ce fichier ne sert qu'à dessiner : il ne fait pas partie de l'application.
/// On le lance avec `flutter test tool/apercu_lecture.dart`, il écrit un PNG
/// dans `tool/apercus/`.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/game/move_controller.dart';
import 'package:lafuga/game/sound_player.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/theme_assets.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/replay_screen.dart';
import 'package:lafuga/ui/widgets/move_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Size _ecran = Size(393, 851);

/// Une partie AVEC DES PRISES : sans elles, les deux bandeaux montrent une
/// rangée vide et on ne voit pas où vont les pièces mangées.
///
/// On la joue ici même, en préférant à chaque coup celui qui éjecte, et on
/// écrit ses notations comme un `.nmc`.
String _nmcAvecPrises({int demiCoups = 24}) {
  final jeu = MoveController(board: Board.initial());
  final hasard = math.Random(7);
  for (var i = 0; i < demiCoups && !jeu.gameOver; i++) {
    final coups = generateMoves(jeu.board, jeu.turn);
    if (coups.isEmpty) break;
    // Une fugue finirait la partie : on la laisse de côté, on veut des
    // prises.
    final jouables = [
      for (final m in coups)
        if (!m.fugue && m.fugueBy == null) m,
    ];
    if (jouables.isEmpty) break;
    final mangeurs = [
      for (final m in jouables)
        if (m.ejected > 0) m,
    ];
    final choix = mangeurs.isNotEmpty
        ? mangeurs[hasard.nextInt(mangeurs.length)]
        : jouables[hasard.nextInt(jouables.length)];
    jeu.applyGeneratedMove(choix);
  }
  final lignes = <String>[];
  for (var i = 0; i < jeu.history.length; i += 2) {
    final noir = i + 1 < jeu.history.length ? '/${jeu.history[i + 1]}' : '';
    lignes.add('${i ~/ 2 + 1}.${jeu.history[i]}$noir');
  }
  return '[Date "2026-10-30"]\n'
      '[Joueur1 "nino"]\n'
      '[Joueur2 "celia"]\n'
      '[Blanc "nino"]\n'
      '[Cadence "15"]\n\n'
      '${lignes.join('\n')}';
}

final GlobalKey _cadre = GlobalKey();

/// Un lecteur de sons MUET : le vrai ouvre un canal de plateforme qui
/// n'existe pas dans un test, et l'erreur tombe au milieu du dessin.
final class SansSon implements SoundPlayer {
  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}

  @override
  void noSuchMethod(Invocation invocation) {}
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('aperçu du mode lecture', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(_ecran);
    final partie = _nmcAvecPrises();
    tester.view.physicalSize = _ecran;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Sans cela le texte sort en rectangles noirs : la police des tests n'a
    // pas de glyphes.
    // DANS `runAsync` : hors de lui, le temps du test est faux et la lecture
    // du fichier de police ne se termine jamais — le test se bloque là.
    await tester.runAsync(() async {
      final police = FontLoader('Roboto')
        ..addFont(
          File(
            '/opt/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
          ).readAsBytes().then((o) => ByteData.view(o.buffer)),
        );
      await police.load();
    });

    await tester.pumpWidget(
      RepaintBoundary(
        key: _cadre,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: ReplayScreen(nmc: partie, sounds: SansSon()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Les images (pictos des touches, visages) ne sont pas chargées dans un
    // test : sans ce passage, l'aperçu les montre vides.
    final images = find.byType(Image).evaluate().toList();
    await tester.runAsync(() async {
      for (final e in images) {
        final image = e.widget as Image;
        await precacheImage(image.image, e);
      }
      final fond = imagesFor(Settings.instance.themeAxes.general)?.background;
      if (fond != null) {
        await precacheImage(
          AssetImage(fond),
          tester.element(find.byType(ReplayScreen)),
        );
      }
    });
    await tester.pumpAndSettle();

    // On entre en mode lecture : la touche « + », puis « Lire la partie ».
    await tester.tap(find.text('+'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lire la partie'));
    await tester.pumpAndSettle();

    // On va au bout de la partie : c'est là que les deux bandeaux ont des
    // pièces mangées à montrer, et que le bandeau des coups a défilé.
    final coups = tester.widget<MoveStrip>(find.byType(MoveStrip));
    coups.onSelect(coups.moves.length - 1);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    final limite =
        _cadre.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await tester.runAsync(() => limite.toImage(pixelRatio: 2));
    final octets = await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.png),
    );
    Directory('tool/apercus').createSync(recursive: true);
    File(
      'tool/apercus/mode_lecture.png',
    ).writeAsBytesSync(Uint8List.view(octets!.buffer));
  });
}
