/// Le plateau de l'écran de pré-coups tient dans sa place.
///
/// Nino : « La ligne tout en bas du plateau fonctionne mal, sûrement parce que
/// la ligne nmc qui défile passe devant le tactile. »
///
/// Le mécanisme est celui-là, le coupable était ailleurs. Un plateau de La
/// Fuga dessine **dix** rangées de haut : les huit jouables, plus les deux
/// zones de ralliement de l'Héritier. Sa hauteur dessinée vaut donc toujours
/// `largeur × 10 / 8`.
///
/// L'écran de composition lui donnait un CARRÉ. Les deux zones de ralliement
/// débordaient alors d'un huitième de largeur en haut et en bas — peintes
/// par-dessus les textes voisins, et surtout **hors de la boîte**, donc hors
/// de portée du doigt : Flutter arrête le test de contact aux bords d'un
/// widget, quoi qu'il peigne au-delà.
///
/// `GameLayout` résout la même chose autrement, en posant le plateau dans une
/// pile par-dessus une place réservée. Ici, l'écran défile : il suffit de lui
/// donner la place qu'il dessine.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/premove_screen.dart';
import 'package:lafuga/ui/widgets/board_geometry.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
  });
  tearDown(resetScale);

  Future<void> ouvrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: PremoveScreen(
          game: CorrGame.fromJson(const {
            'id': 'g1',
            'statut': 'en_cours',
            'adversaire': 'celia',
            'ma_couleur': 'Noir',
            'turn': 'Blanc',
            'my_turn': false,
            'moves_text': 'Fa3-Sol4',
            'objectif': 'partie',
          }),
          service: CorrespondenceService(OnlineClient(api: ApiClient())),
          board: Board.initial(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('il reçoit la place qu il dessine', (tester) async {
    await ouvrir(tester);
    final boite = tester.getSize(find.byType(GameBoardView));
    expect(
      boite.height,
      greaterThanOrEqualTo(boite.width * kExtRows / kCols - 0.5),
      reason:
          'un plateau dessine $kExtRows rangées de haut, zones de ralliement '
          'comprises : avec moins de place, elles débordent par-dessus ce qui '
          'l entoure et le doigt ne les atteint plus',
    );
  });

  testWidgets('le doigt atteint les rangées extrêmes, ralliement compris', (
    tester,
  ) async {
    await ouvrir(tester);
    final plateau = find.byType(GameBoardView);
    final cadre = tester.getRect(plateau);
    final geometrie = BoardGeometry(size: cadre.size, flipped: false);

    // Celui qui écoute vraiment le doigt, à l'intérieur du plateau.
    final ecoute = tester.renderObject(
      find.descendant(of: plateau, matching: find.byType(Listener)).first,
    );

    // Les deux rangées de ralliement, et les deux rangées jouables du bord :
    // ce sont elles que le débordement rendait inatteignables.
    for (final (nom, row) in [
      ('la zone de ralliement du bas', -1),
      ('la rangée du bas', 0),
      ('la rangée du haut', kRows - 1),
      ('la zone de ralliement du haut', kRows),
    ]) {
      // Une colonne centrale : les zones de ralliement n'existent que là.
      final point =
          cadre.topLeft +
          Offset(
            geometrie.colToX(3) + geometrie.cellSize / 2,
            geometrie.rowToY(row) + geometrie.cellSize / 2,
          );
      final resultat = HitTestResult();
      WidgetsBinding.instance.hitTestInView(
        resultat,
        point,
        tester.view.viewId,
      );
      expect(
        resultat.path.any((e) => e.target == ecoute),
        isTrue,
        reason:
            '$nom : le doigt n atteint pas le plateau à $point — '
            'le plateau y dessine, mais quelque chose d autre y répond',
      );
    }
  });

  testWidgets('et plus rien n est écrit par-dessus le plateau', (tester) async {
    await ouvrir(tester);
    final plateau = tester.getRect(find.byType(GameBoardView));
    for (final element in find.byType(Text).evaluate()) {
      final texte = element.widget as Text;
      final data = texte.data;
      if (data == null || data.isEmpty) continue;
      final cadre = tester.getRect(find.byWidget(texte));
      expect(
        cadre.overlaps(plateau),
        isFalse,
        reason:
            '« $data » chevauche le plateau : il sera mangé, et il mangera '
            'le tactile de ce qu il recouvre',
      );
    }
  });
}
