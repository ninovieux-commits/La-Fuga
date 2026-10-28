/// Ce que l'écran de jeu propose, mode par mode.
///
/// Kivy n'a qu'un écran de jeu ; ce sont `_update_action_buttons` et
/// `_update_side_buttons` qui décident, selon le mode, quelles touches
/// apparaissent. Ce test fige la table entière — c'est là que se cachaient
/// les options « présentes ici, absentes là ».
///
/// | touche        | local | vs IA | analyse |
/// |---------------|-------|-------|---------|
/// | `< >`         |   ✔   |   ✔   |    ✔    |
/// | pause         | `\| \|` | `\| \|` |  `<<`   |
/// | Retour menu   | à la fin | à la fin |  ✗   |
/// | Rapide/Profond|   ✗   |   ✔   |    ✗    |
/// | Deep Grey     |   ✗   |   ✗   |    ✔    |
/// | Analyser      |   ✗   |   ✗   |    ✗    |
/// | Chat          |   ✗   |   ✗   |    ✗    |
/// | ↶ ⚑           | 2 côtés | côté humain, sans ½ | aucun |
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/clock.dart';
import 'package:lafuga/game/game_archive.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/ai_memory.dart';
import 'package:lafuga/state/local_games.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/ui/widgets/bandeau_prises.dart';
import 'package:lafuga/ui/widgets/game_layout.dart';
import 'package:lafuga/ui/widgets/player_panel.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:lafuga/ui/screens/game_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prefs d'une appli déjà lancée une fois : ni choix de langue, ni tuto —
/// ils n'apparaissent qu'au tout premier démarrage.
const Map<String, Object> _launched = {'lang_chosen': true, 'tuto_seen': true};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues(_launched);
    await Settings.load();
    await Translations.load('fr');
    tmp = Directory.systemTemp.createTempSync('lafuga_modes');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> open(
    WidgetTester tester, {
    Camp? aiCamp,
    bool analysis = false,
    bool analysisFromCorr = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          cadence: Cadence.zen,
          aiCamp: aiCamp,
          analysis: analysis,
          analysisFromCorr: analysisFromCorr,
          archive: GameArchive(local: LocalGamesStore(directory: tmp)),
          memory: AiMemory(directory: tmp),
        ),
      ),
    );
    await tester.pump();
  }

  group('Partie locale', () {
    testWidgets('bandeau : retourner et pause, rien de plus', (tester) async {
      await open(tester);

      expect(find.byTooltip(T('Retourner le plateau')), findsOneWidget);
      expect(find.byTooltip('Pause'), findsOneWidget);
      // Le « << » est devenu une flèche : on le cherche par son nom.
      expect(find.byTooltip('Retour'), findsNothing);
      expect(find.text('Retour au menu'), findsNothing);
      expect(find.text('Rapide'), findsNothing);
      expect(find.text('Profond'), findsNothing);
      expect(find.text('Deep Grey'), findsNothing);
      expect(find.text('Analyser'), findsNothing);
      expect(find.byTooltip(T('Chat')), findsNothing);
    });

    testWidgets('les deux joueurs ont ↶ et le drapeau', (tester) async {
      await open(tester);

      // Le ½ et le X ont quitté le bandeau : un drapeau par joueur les
      // remplace, et c'est son popup qui porte les deux gestes.
      expect(
        find.byTooltip('Abandonner ou proposer la nulle ?'),
        findsNWidgets(2),
      );
      expect(find.text('½'), findsNothing);
      expect(find.text('X'), findsNothing);
    });

    testWidgets('le X du haut fait abandonner le joueur du haut', (
      tester,
    ) async {
      await open(tester);

      // Les Blancs sont en bas, donc « Joueur 2 » (les Noirs) est en haut.
      // Kivy fait abandonner le camp DONT on touche la croix, même si c'est
      // l'autre qui a le trait.
      await tester.tap(
        find.byTooltip('Abandonner ou proposer la nulle ?').first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FugaButton, 'Abandonner'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Joueur 2 confirme abandonner'),
        findsOneWidget,
        reason: 'la confirmation nomme qui abandonne, comme avant',
      );
    });
  });

  group('Contre Deep Grey', () {
    testWidgets('le mode de réflexion se change, et lui seul', (tester) async {
      await open(tester, aiCamp: Camp.noir);

      expect(find.text('Rapide'), findsOneWidget);
      expect(find.text('Analyser'), findsNothing);
      expect(find.byTooltip(T('Chat')), findsNothing);
      expect(
        find.text('Deep Grey'),
        findsOneWidget,
        reason: 'le nom du joueur',
      );

      await tester.tap(find.text('Rapide'));
      await tester.pump();
      expect(find.text('Profond'), findsOneWidget);
    });

    testWidgets('pas de nulle, et rien du côté de l IA', (tester) async {
      await open(tester, aiCamp: Camp.noir);

      expect(
        find.byTooltip('Abandonner ou proposer la nulle ?'),
        findsOneWidget,
        reason: 'seul le joueur humain a un drapeau',
      );
      await tester.tap(find.byTooltip('Abandonner ou proposer la nulle ?'));
      await tester.pumpAndSettle();
      expect(
        find.text('Proposer nulle'),
        findsNothing,
        reason: 'on ne négocie pas de nulle avec Deep Grey',
      );
      expect(find.text('Abandonner'), findsWidgets);
    });
  });

  group('Deep Grey ouvre la partie', () {
    testWidgets('quand il a les Blancs, il joue sans qu on touche à rien', (
      tester,
    ) async {
      // L'IA tient les Blancs : c'est donc à elle de commencer.
      await open(tester, aiCamp: Camp.blanc);
      await tester.pump();

      expect(
        find.byType(CircularProgressIndicator),
        findsOneWidget,
        reason: 'Deep Grey réfléchit au premier coup',
      );
    });

    testWidgets('quand il a les Noirs, il attend', (tester) async {
      await open(tester, aiCamp: Camp.noir);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('il prend son temps avant de poser son coup', (tester) async {
      // Nino : « il faut que Deep Grey attende une seconde avant de jouer à
      // chaque fois que c'est à lui ». Une position simple est trouvée en
      // quelques millisecondes, et le coup apparaissait au moment même où on
      // relâchait le doigt — on ne voyait pas qui avait joué quoi.
      //
      // On ALLONGE la pause pour l'épreuve : à une seconde, la réflexion
      // elle-même dure déjà plus longtemps sur certaines machines, et le
      // test passait aussi bien avec que sans l'attente. Il ne prouvait
      // rien. À quatre secondes, le temps de calcul ne peut plus se faire
      // passer pour la pause.
      //
      // `runAsync` est indispensable : la recherche tourne dans un isolate,
      // et l'horloge truquée des tests ne la fait pas avancer.
      const pause = Duration(seconds: 4);
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            cadence: Cadence.zen,
            aiCamp: Camp.blanc,
            aiPause: pause,
            archive: GameArchive(local: LocalGamesStore(directory: tmp)),
            memory: AiMemory(directory: tmp),
          ),
        ),
      );
      await tester.pump();

      String plateau() => tester
          .widget<GameBoardView>(find.byType(GameBoardView))
          .board
          .render();
      final depart = plateau();

      // Deux horloges, et il faut les faire avancer toutes les deux :
      // `runAsync` donne du temps RÉEL à l'isolate, et `pump(durée)` avance
      // l'horloge truquée — la seule que l'attente de Deep Grey consulte.
      // C'est donc celle-là qu'on mesure.
      const pas = Duration(milliseconds: 150);
      var ecoule = Duration.zero;
      Duration? joueA;
      for (var i = 0; i < 60 && joueA == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump(pas);
        ecoule += pas;
        if (plateau() != depart) joueA = ecoule;
      }

      expect(joueA, isNotNull, reason: 'il n a jamais joué');
      expect(
        joueA!.inMilliseconds,
        greaterThan(pause.inMilliseconds - 500),
        reason:
            'il a joué au bout de ${joueA.inMilliseconds} ms, '
            'donc sans attendre',
      );
    });
  });

  group('Analyse', () {
    testWidgets('la pause devient un retour, Deep Grey apparaît', (
      tester,
    ) async {
      await open(tester, analysis: true);

      expect(find.byTooltip('Retour'), findsOneWidget);
      expect(find.byTooltip('Pause'), findsNothing);
      expect(find.text('Deep Grey'), findsOneWidget);
      expect(find.text('Analyser'), findsNothing, reason: 'on y est déjà');
      expect(find.text('Rapide'), findsNothing);
    });

    testWidgets('aucun geste de partie', (tester) async {
      await open(tester, analysis: true);

      expect(find.byTooltip('Proposer nulle'), findsNothing);
      expect(find.byTooltip('Abandonner ou proposer la nulle ?'), findsNothing);
      // L'annulation, elle, EST un geste d'analyse : on y défait ce qu'on
      // vient d'essayer. Elle est là, éteinte tant qu'il n'y a rien à
      // défaire.
      expect(find.byTooltip('Annuler'), findsOneWidget);
    });

    testWidgets('la touche d annuler est en BAS, comme en partie', (
      tester,
    ) async {
      // Nino : « le bouton d'annulation de coup en analyse doit être
      // identique et au même endroit qu'en partie. » Elle était au bout de
      // la bande des prises, en haut de l'écran.
      await open(tester, analysis: true);
      final vue = tester.widget<GameBoardView>(find.byType(GameBoardView));

      expect(
        tester.widget<BandeauPrises>(find.byType(BandeauPrises)).avecAnnuler,
        isFalse,
        reason: 'elle ne vit plus dans la bande des prises',
      );
      // Elle ne disparaît plus : elle attend, éteinte, sous le plateau.
      expect(find.byTooltip(T('Annuler')), findsOneWidget);

      // On commence un coup : la touche s'allume, et sous le plateau.
      vue.onTapCell(const Cell(2, 1));
      await tester.pumpAndSettle();
      vue.onTapCell(const Cell(2, 2));
      await tester.pumpAndSettle();

      final touche = find.byTooltip(T('Annuler'));
      expect(touche, findsOneWidget);
      expect(
        find.byType(ToucheAction),
        findsOneWidget,
        reason: 'le MÊME widget qu en partie, pas un dessin qui lui ressemble',
      );
      final place = tester.getRect(touche);
      final plateau = tester.getRect(find.byType(GameBoardView));
      expect(
        place.top,
        greaterThanOrEqualTo(plateau.bottom - 1),
        reason: 'sous le plateau, comme la rangée d actions d une partie',
      );
      expect(
        place.center.dx,
        greaterThan(tester.getSize(find.byType(GameLayout)).width / 2),
        reason: 'à droite, comme en partie',
      );
    });

    testWidgets('venue d une correspondance, Deep Grey est là aussi', (
      tester,
    ) async {
      // Il était interdit ici — il souffle le coup à jouer. Nino : « ce
      // bouton deepgrey doit aussi être là lorsqu'on accède à l'analyse
      // depuis une partie par correspondance. » C'est son jeu, et il joue
      // contre des gens qu'il connaît.
      await open(tester, analysis: true, analysisFromCorr: true);

      expect(find.text('Deep Grey'), findsOneWidget);
      expect(find.byTooltip('Retour'), findsOneWidget);
    });
  });
}
