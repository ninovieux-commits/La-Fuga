/// Les touches des écrans de jeu ne changent jamais de place.
///
/// Nino : « là tout de suite quand le bouton pré-coups disparaît car c'est
/// mon tour de jouer, les autres boutons se décalent vers la gauche. Chaque
/// bouton sur les écrans de jeux, analyse ect doivent être fixés, ne jamais
/// changer de place. Ce qui veut dire, par exemple, dans le bandeau large du
/// bas, que le bouton pour annuler le coup doit être celui qui est le plus à
/// gauche, autrement il est obligé de décaler le bouton de message rapide. »
///
/// ## Comment on tient la promesse
///
/// Deux recettes, et pas une seule :
///
///  * **Rien n'apparaît ni ne disparaît.** La boule de cristal est là dès
///    qu'« Analyser » ou les pré-coups existent, et c'est à l'intérieur de
///    son popup que la touche pâlit. Une touche du bandeau qui allait et
///    venait déplaçait toutes ses voisines.
///  * **Ce qui va et vient se met EN TÊTE**, derrière un `Expanded`. Le ↶
///    naît et meurt au fil du coup qu'on compose : il est donc le plus à
///    gauche de son groupe, et c'est la bande des prises qui se resserre
///    pour lui.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/game_top_bar.dart';
import 'package:lafuga/ui/widgets/player_panel.dart';
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
  });
  tearDown(resetScale);

  /// Deux places sont les MÊMES au demi-pixel près : la largeur d'un
  /// `Expanded` se calcule par soustraction, et un dixième de pixel d'écart
  /// ne déplace rien à l'œil. C'est le pouce de Nino qu'on protège, pas la
  /// virgule flottante.
  void memePlace(Rect obtenu, Rect attendu, String raison) {
    for (final (nom, a, b) in [
      ('gauche', obtenu.left, attendu.left),
      ('haut', obtenu.top, attendu.top),
      ('largeur', obtenu.width, attendu.width),
      ('hauteur', obtenu.height, attendu.height),
    ]) {
      expect(a, moreOrLessEquals(b, epsilon: 0.5), reason: '$raison ($nom)');
    }
  }

  /// Pose un widget à la taille d'un téléphone.
  Future<void> pose(WidgetTester tester, Widget enfant) async {
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    setScaleSize(const Size(393, 851));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: enfant)));
    await tester.pumpAndSettle();
  }

  group('Le bandeau large du bas', () {
    /// Le panneau d'un joueur, avec ou sans la touche d'annulation.
    Widget panneau({required bool annulable}) => SizedBox(
      // L'épaisseur que `GameLayout` lui donne : 12 parts sur 104. Sans
      // elle, le panneau prend toute la page et ses touches carrées, qui
      // suivent sa hauteur, débordent de la rangée.
      height: 851 * 12 / 104,
      child: PlayerPanel(
        name: 'nino',
        clock: '15:00',
        palette: paletteOf('foret'),
        isWhite: true,
        isTurn: true,
        captures: const [Piece.noirSoldat],
        onUndo: annulable ? () {} : null,
        onMessageRapide: () {},
        onResign: () {},
        onDraw: () {},
      ),
    );

    testWidgets('le message rapide et le drapeau ne bougent pas quand le ↶ '
        'paraît', (tester) async {
      await pose(tester, panneau(annulable: false));
      Rect place(String tooltip) => tester.getRect(find.byTooltip(tooltip));
      final message = place(T('Message rapide'));
      final drapeau = place(T('Abandonner ou proposer la nulle ?'));
      expect(
        find.byTooltip(T('Annuler')),
        findsNothing,
        reason: 'sans coup en cours, il n y a rien à annuler',
      );

      await pose(tester, panneau(annulable: true));
      expect(find.byTooltip(T('Annuler')), findsOneWidget);
      memePlace(
        place(T('Message rapide')),
        message,
        'le ↶ a poussé le message rapide : il doit naître à sa gauche',
      );
      memePlace(
        place(T('Abandonner ou proposer la nulle ?')),
        drapeau,
        'le ↶ a poussé le drapeau',
      );
    });

    testWidgets('et le ↶ est le plus à gauche du groupe', (tester) async {
      await pose(tester, panneau(annulable: true));
      expect(
        tester.getRect(find.byTooltip(T('Annuler'))).right,
        lessThanOrEqualTo(
          tester.getRect(find.byTooltip(T('Message rapide'))).left,
        ),
      );
    });
  });

  group('Le bandeau fin du haut', () {
    /// Le bandeau d'une partie de correspondance : l'analyse est toujours
    /// offerte, les pré-coups seulement quand c'est à l'adversaire de jouer.
    Widget bandeau({required bool prejouable}) => SizedBox(
      height: 851 * 7 / 104,
      child: GameTopBar(
        palette: paletteOf('foret'),
        color: Colors.grey,
        onFlip: () {},
        onPause: () {},
        onChat: () {},
        onAnalyse: () {},
        onPremove: prejouable ? () {} : null,
      ),
    );

    testWidgets('la boule reste là, et tout reste en place', (tester) async {
      await pose(tester, bandeau(prejouable: true));
      final boule = find.byTooltip(T('Analyser ou préparer ses coups ?'));
      final placeBoule = tester.getRect(boule);
      final placeChat = tester.getRect(find.text(T('Chat')));

      await pose(tester, bandeau(prejouable: false));
      expect(
        boule,
        findsOneWidget,
        reason: 'la boule porte aussi « Analyser » : elle ne s en va pas',
      );
      memePlace(tester.getRect(boule), placeBoule, 'la boule a bougé');
      memePlace(
        tester.getRect(find.text(T('Chat'))),
        placeChat,
        'le voisinage de la boule a bougé avec elle',
      );
    });

    testWidgets('et le centre reste libre pour l appareil photo', (
      tester,
    ) async {
      // L'objectif selfie est percé au milieu de la barre d'état, et passe
      // devant tout ce qu'on y pose.
      await pose(tester, bandeau(prejouable: true));
      final cadre = tester.getRect(find.byType(GameTopBar));
      final trou = Rect.fromCenter(
        center: cadre.center,
        width: S(kTrouCamera),
        height: cadre.height,
      );
      final touches = find
          .descendant(
            of: find.byType(GameTopBar),
            matching: find.byType(InkWell),
          )
          .evaluate();
      expect(touches, isNotEmpty, reason: 'le bandeau n a plus de touches ?');
      for (final touche in touches) {
        expect(
          tester.getRect(find.byWidget(touche.widget)).overlaps(trou),
          isFalse,
          reason: 'une touche empiète sur le trou de l appareil photo',
        );
      }
    });
  });
}
