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
import 'package:lafuga/ui/widgets/picto_touche.dart';
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

  group('La boule prend la place d « Analyser », dans tous les modes', () {
    testWidgets('sans pré-coups, elle ouvre l analyse tout droit', (
      tester,
    ) async {
      // Nino : « dans les modes de jeu sans pré-coups, le bouton analyse est
      // alors simplement remplacé par la boule de cristal. » Une relecture,
      // une analyse : il n y a rien à choisir, donc pas de popup.
      var analyses = 0;
      await pose(
        tester,
        SizedBox(
          height: 851 * 7 / 104,
          child: GameTopBar(
            palette: paletteOf('foret'),
            color: Colors.grey,
            onFlip: () {},
            pauseLabel: '<<',
            onPause: () {},
            onAnalyse: () => analyses++,
          ),
        ),
      );
      await tester.tap(find.byTooltip(T('Analyser')));
      await tester.pumpAndSettle();
      expect(analyses, 1, reason: 'la boule doit mener droit à l analyse');
      expect(
        find.text(T('Pré-coups')),
        findsNothing,
        reason: 'un popup pour une seule touche vivante est un geste pour rien',
      );
    });

    testWidgets('avec les pré-coups, elle demande lequel des deux', (
      tester,
    ) async {
      var analyses = 0;
      await pose(
        tester,
        SizedBox(
          height: 851 * 7 / 104,
          child: GameTopBar(
            palette: paletteOf('foret'),
            color: Colors.grey,
            onFlip: () {},
            onPause: () {},
            onAnalyse: () => analyses++,
            onPremove: () {},
            raisonPremove: 'Jouez votre coup',
          ),
        ),
      );
      await tester.tap(find.byTooltip(T('Analyser ou préparer ses coups ?')));
      await tester.pumpAndSettle();
      expect(analyses, 0, reason: 'on choisit d abord');
      expect(find.text(T('Pré-coups')), findsOneWidget);
      expect(find.text(T('Analyser')), findsOneWidget);
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
        // La correspondance offre les pré-coups, et dit donc toujours
        // pourquoi quand ils sont fermés.
        raisonPremove: 'Jouez votre coup',
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
  });

  group('Les touches à dessin restent des carrés', () {
    // Nino : « la touche doit avoir la même forme carrée que les autres !
    // Ainsi que la touche drapeau de tout à l'heure d'ailleurs. » Un
    // pictogramme est cadré sur son sujet : posé avec la marge d'un texte il
    // remplit la touche et en avale la forme — la boule, ronde, faisait lire
    // un disque. Il prend donc la part d'une lettre, et pas plus.
    void mesure(WidgetTester tester) {
      final dessin = tester.getSize(find.byType(PictoTouche));
      final touche = tester.getSize(
        find.ancestor(
          of: find.byType(PictoTouche),
          matching: find.byType(AspectRatio),
        ),
      );
      expect(
        touche.width,
        moreOrLessEquals(touche.height, epsilon: 0.5),
        reason: 'la touche elle-même doit être carrée',
      );
      expect(
        dessin.width / touche.width,
        moreOrLessEquals(kPartPicto, epsilon: 0.02),
        reason:
            'le dessin occupe ${(dessin.width / touche.width * 100).round()} % '
            'de la touche : il en avale la forme, et on ne voit plus le carré',
      );
    }

    testWidgets('la boule, dans le bandeau fin', (tester) async {
      await pose(
        tester,
        SizedBox(
          height: 851 * 7 / 104,
          child: GameTopBar(
            palette: paletteOf('foret'),
            color: Colors.grey,
            onFlip: () {},
            onPause: () {},
            onAnalyse: () {},
          ),
        ),
      );
      mesure(tester);
    });

    testWidgets('le drapeau, dans le bandeau large', (tester) async {
      await pose(
        tester,
        SizedBox(
          height: 851 * 12 / 104,
          child: PlayerPanel(
            name: 'nino',
            clock: '15:00',
            palette: paletteOf('foret'),
            isWhite: true,
            isTurn: true,
            captures: const [],
            onResign: () {},
            onDraw: () {},
          ),
        ),
      );
      mesure(tester);
    });
  });

  group('Le centre reste libre pour l appareil photo, dans tous les modes', () {
    // L'objectif selfie est percé au milieu de la barre d'état et passe devant
    // tout ce qu'on y pose. Nino : « les modifications dont je te parle depuis
    // tout à l'heure doivent être effectives dans tous les modes de jeux
    // pouvant être concernés. » Le bandeau est le même partout, mais ce sont
    // ses touches qui changent — et c'est leur nombre qui pousse vers le
    // centre. On passe donc tous les modes, tels que les écrans les composent.
    final modes = <String, GameTopBar>{
      'partie locale': GameTopBar(
        palette: paletteOf('foret'),
        color: Colors.grey,
        onFlip: () {},
        onPause: () {},
        onMenu: () {},
      ),
      'analyse': GameTopBar(
        palette: paletteOf('foret'),
        color: Colors.grey,
        onFlip: () {},
        pauseLabel: '<<',
        onPause: () {},
        onCopyFug: () {},
        onDeepGrey: () {},
        onToggleAiMode: () {},
        aiDeepMode: true,
      ),
      'partie en ligne': GameTopBar(
        palette: paletteOf('foret'),
        color: Colors.grey,
        onFlip: () {},
        onPause: () {},
        onChat: () {},
        onMenu: () {},
      ),
      'correspondance': GameTopBar(
        palette: paletteOf('foret'),
        color: Colors.grey,
        onFlip: () {},
        onPause: () {},
        onChat: () {},
        onAnalyse: () {},
        onPremove: () {},
        raisonPremove: 'Jouez votre coup',
        onMenu: () {},
      ),
      'relecture': GameTopBar(
        palette: paletteOf('foret'),
        color: Colors.grey,
        onFlip: () {},
        pauseLabel: '<<',
        onPause: () {},
        onAutoPlay: () {},
        onCopyNmc: () {},
        onAnalyse: () {},
        onDeepGrey: () {},
      ),
      'pré-coups, composeur, défi': GameTopBar(
        palette: paletteOf('foret'),
        color: Colors.grey,
        onFlip: () {},
        pauseLabel: '<<',
        onPause: () {},
      ),
    };

    /// Les deux formes extrêmes du marché : c'est la forme qui fait diverger
    /// les proportions, pas la taille.
    const formes = {
      '16:9 le plus trapu': Size(375, 667),
      '21:9 le plus élancé': Size(411, 960),
    };

    for (final mode in modes.entries) {
      for (final forme in formes.entries) {
        testWidgets('${mode.key} — ${forme.key}', (tester) async {
          tester.view.physicalSize = forme.value;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          setScaleSize(forme.value);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  height: forme.value.height * 7 / 104,
                  child: mode.value,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

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
          expect(
            touches,
            isNotEmpty,
            reason: 'le bandeau n a plus de touches ?',
          );
          for (final touche in touches) {
            expect(
              tester.getRect(find.byWidget(touche.widget)).overlaps(trou),
              isFalse,
              reason: 'une touche empiète sur le trou de l appareil photo',
            );
          }
        });
      }
    }
  });
}
