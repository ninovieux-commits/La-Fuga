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
      // ELLE NE DISPARAÎT PLUS : sans coup en cours elle s'éteint, comme
      // les autres touches hors d'usage. Nino : « le bouton annulation de
      // coup ne doit plus disparaître lorsqu'il n'est pas cliquable. »
      expect(find.byTooltip(T('Annuler')), findsOneWidget);
      final eteinte = place(T('Annuler'));

      await pose(tester, panneau(annulable: true));
      expect(find.byTooltip(T('Annuler')), findsOneWidget);
      memePlace(
        place(T('Annuler')),
        eteinte,
        'le ↶ n a pas bougé en redevenant cliquable',
      );
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
      final placeChat = tester.getRect(find.byTooltip(T('Chat')));

      await pose(tester, bandeau(prejouable: false));
      expect(
        boule,
        findsOneWidget,
        reason: 'la boule porte aussi « Analyser » : elle ne s en va pas',
      );
      memePlace(tester.getRect(boule), placeBoule, 'la boule a bougé');
      memePlace(
        tester.getRect(find.byTooltip(T('Chat'))),
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
    /// TOUTES les touches à dessin de l'écran, et pas une seule : le bandeau
    /// en porte plusieurs depuis que le retournement et le chat sont dessinés
    /// eux aussi.
    void mesure(WidgetTester tester) {
      final dessins = find.byType(PictoTouche);
      expect(dessins, findsWidgets);
      for (final e in dessins.evaluate()) {
        final lui = find.byWidget(e.widget);
        final dessin = tester.getSize(lui);
        final touche = tester.getSize(
          find.ancestor(of: lui, matching: find.byType(AspectRatio)).first,
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
              'le dessin occupe '
              '${(dessin.width / touche.width * 100).round()} % de la '
              'touche : il en avale la forme, et on ne voit plus le carré',
        );
      }
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

  group('Le bandeau tient, dans tous les modes', () {
    // Nino : « les modifications dont je te parle depuis tout à l'heure
    // doivent être effectives dans tous les modes de jeux pouvant être
    // concernés. » Le bandeau est le même partout, mais ce sont ses touches
    // qui changent — et c'est leur nombre qui pousse vers le centre. On passe
    // donc tous les modes, tels que les écrans les composent, et on vérifie
    // les deux choses qui peuvent casser : le trou de l'appareil photo, et le
    // débordement.
    //
    // On ne mélange PAS toutes les touches à la fois : aucun écran ne les
    // montre toutes, et un bandeau impossible ne prouve rien — il ferait
    // seulement tomber le test le jour où l'on ajoute une touche quelque
    // part.
    GameTopBar barre({
      bool chat = false,
      bool finie = false,
      bool boule = false,
      bool precoups = false,
      String pause = '| |',
      bool autoPlay = false,
      bool copyNmc = false,
      bool copyFug = false,
      bool deepGrey = false,
      bool modeIa = false,
    }) => GameTopBar(
      palette: paletteOf('foret'),
      color: Colors.grey,
      onFlip: () {},
      pauseLabel: pause,
      onPause: () {},
      onChat: chat ? () {} : null,
      onMenu: finie ? () {} : null,
      onAnalyse: boule ? () {} : null,
      onPremove: precoups ? () {} : null,
      raisonPremove: boule && precoups ? 'Jouez votre coup' : null,
      onAutoPlay: autoPlay ? () {} : null,
      onCopyNmc: copyNmc ? () {} : null,
      onCopyFug: copyFug ? () {} : null,
      onDeepGrey: deepGrey ? () {} : null,
      onToggleAiMode: modeIa ? () {} : null,
      aiDeepMode: modeIa ? true : null,
    );

    final modes = <String, GameTopBar>{
      'partie locale': barre(),
      'partie locale finie': barre(finie: true),
      'contre Deep Grey': barre(modeIa: true),
      'analyse': barre(pause: '<<', copyFug: true, deepGrey: true),
      'partie en ligne': barre(chat: true),
      'partie en ligne finie': barre(chat: true, finie: true),
      'correspondance': barre(chat: true, boule: true, precoups: true),
      'correspondance, à moi de jouer': barre(chat: true, boule: true),
      'correspondance finie': barre(chat: true, boule: true, finie: true),
      'relecture': barre(
        pause: '<<',
        autoPlay: true,
        copyNmc: true,
        boule: true,
        deepGrey: true,
      ),
      'pré-coups, composeur, défi': barre(pause: '<<'),
    };

    /// Les deux formes extrêmes du marché : c'est la forme qui fait diverger
    /// les proportions, pas la taille. Un 21:9 est le pire cas du bandeau —
    /// ses touches suivent la HAUTEUR de l'écran et sa rangée la largeur.
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

          final debordements = <String>[];
          final precedent = FlutterError.onError;
          FlutterError.onError = (d) {
            if (d.exceptionAsString().contains('overflow')) {
              debordements.add(d.exceptionAsString());
            } else {
              precedent?.call(d);
            }
          };
          addTearDown(() => FlutterError.onError = precedent);

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
          // On rend la main à Flutter AVANT d'affirmer : un `expect` qui
          // tombe alors que le guetteur est encore en place fait échouer le
          // test sur une assertion du binding, et on ne lit plus la cause.
          FlutterError.onError = precedent;

          expect(
            debordements,
            isEmpty,
            reason:
                'le bandeau déborde : ses touches carrées suivent la hauteur '
                'et la rangée la largeur — il suffit d une touche de plus',
          );

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
