/// La touche d'annulation est LA MÊME, à la MÊME PLACE, en partie et en
/// analyse.
///
/// Nino : « tu trouves pas que le bouton d'annulation de coup en analyse est
/// bien trop petit et mal placé ? Il doit être LE MÊME et placé AU MÊME
/// ENDROIT qu'en partie. » Elle était déjà le même widget, mais dans une
/// rangée deux fois plus mince et collée au bord : une touche carrée prend la
/// hauteur de sa rangée, donc elle était deux fois plus petite, et elle
/// tombait là où le drapeau tombe en partie.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/game_screen.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:lafuga/ui/widgets/game_layout.dart';
import 'package:lafuga/ui/widgets/player_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ecran = Size(393, 851);

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
  });

  /// Ouvre l'écran, compose un coup SANS le valider — c'est à ce moment-là
  /// que la touche d'annulation paraît — et rend sa place à l'écran.
  Future<Rect> placeDuAnnuler(
    WidgetTester tester, {
    required bool analyse,
  }) async {
    tester.view.physicalSize = ecran;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    setScaleSize(ecran);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          aiCamp: null,
          analysis: analyse,
          initialFlipped: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final view = tester.widget<GameBoardView>(find.byType(GameBoardView));
    final coup = generateMoves(
      view.board,
      Camp.blanc,
    ).firstWhere((m) => m.movedCells.length == 1 && m.movedCells.first.onBoard);
    view.onTapCell(coup.from);
    await tester.pump();
    view.onTapCell(coup.movedCells.first);
    await tester.pumpAndSettle();

    // En partie, les DEUX bandeaux en portent une : chacun son joueur. On
    // compare celle du bas, la nôtre — la plus basse à l'écran.
    final touches = find.byTooltip(T('Annuler'));
    expect(touches, findsWidgets, reason: 'un coup est en cours');
    final places = touches
        .evaluate()
        .map((e) => tester.getRect(find.byWidget(e.widget)))
        .toList();
    places.sort((a, b) => a.center.dy.compareTo(b.center.dy));
    return places.last;
  }

  /// La touche d'annulation d'un bandeau de joueur COMPLET — celui d'une
  /// partie en ligne, avec le message rapide et le drapeau à sa droite.
  ///
  /// C'est de celui-là que parle Nino : une partie locale n'a personne à qui
  /// écrire, son message rapide n'existe pas, et son ↆ est donc déjà d'une
  /// place plus à droite.
  Future<Rect> placeDansUnBandeauComplet(WidgetTester tester) async {
    tester.view.physicalSize = ecran;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    setScaleSize(ecran);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: hauteurBandeauEnPartie(ecran),
            child: PlayerPanel(
              name: 'nino',
              clock: '15:00',
              palette: paletteOf('foret'),
              isWhite: true,
              isTurn: true,
              captures: const [],
              onUndo: () {},
              onMessageRapide: () {},
              onResign: () {},
              onDraw: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getRect(find.byTooltip(T('Annuler')));
  }

  testWidgets('même taille qu en partie, et sur la même ligne', (tester) async {
    final enPartie = await placeDuAnnuler(tester, analyse: false);
    final enAnalyse = await placeDuAnnuler(tester, analyse: true);

    expect(
      enAnalyse.size.width,
      moreOrLessEquals(enPartie.size.width, epsilon: 0.5),
      reason: 'la même touche, pas une deux fois plus petite',
    );
    expect(
      enAnalyse.size.height,
      moreOrLessEquals(enPartie.size.height, epsilon: 0.5),
    );
    expect(
      enAnalyse.center.dy,
      moreOrLessEquals(enPartie.center.dy, epsilon: 0.5),
      reason: 'le bas des deux bandeaux tombe sur la même ligne',
    );
  });

  testWidgets('et à la même distance du bord droit', (tester) async {
    final enAnalyse = await placeDuAnnuler(tester, analyse: true);
    final enPartie = await placeDansUnBandeauComplet(tester);

    expect(
      ecran.width - enAnalyse.right,
      moreOrLessEquals(ecran.width - enPartie.right, epsilon: 0.5),
      reason: 'les places du message rapide et du drapeau restent prises',
    );
  });

  testWidgets('elle est carrée, et à la taille des touches de l appli', (
    tester,
  ) async {
    final place = await placeDuAnnuler(tester, analyse: true);
    // La place compte l'écart de gauche ; le carré, lui, est la hauteur.
    expect(place.height, greaterThan(touchHeight() * 0.8));
  });
}
