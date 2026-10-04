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
/// | ↶ ½ X         | 2 côtés | côté humain, sans ½ | aucun |
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

      expect(find.text('< >'), findsOneWidget);
      expect(find.byTooltip('Pause'), findsOneWidget);
      expect(find.text('<<'), findsNothing);
      expect(find.text('Retour au menu'), findsNothing);
      expect(find.text('Rapide'), findsNothing);
      expect(find.text('Profond'), findsNothing);
      expect(find.text('Deep Grey'), findsNothing);
      expect(find.text('Analyser'), findsNothing);
      expect(find.text('Chat'), findsNothing);
    });

    testWidgets('les deux joueurs ont ↶ ½ X', (tester) async {
      await open(tester);

      expect(find.byTooltip('Proposer nulle'), findsNWidgets(2));
      expect(find.byTooltip('Abandonner'), findsNWidgets(2));
    });

    testWidgets('le X du haut fait abandonner le joueur du haut', (
      tester,
    ) async {
      await open(tester);

      // Les Blancs sont en bas, donc « Joueur 2 » (les Noirs) est en haut.
      // Kivy fait abandonner le camp DONT on touche la croix, même si c'est
      // l'autre qui a le trait.
      await tester.tap(find.byTooltip('Abandonner').first);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Joueur 2 confirme abandonner'),
        findsOneWidget,
      );
    });
  });

  group('Contre Deep Grey', () {
    testWidgets('le mode de réflexion se change, et lui seul', (tester) async {
      await open(tester, aiCamp: Camp.noir);

      expect(find.text('Rapide'), findsOneWidget);
      expect(find.text('Analyser'), findsNothing);
      expect(find.text('Chat'), findsNothing);
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
        find.byTooltip('Proposer nulle'),
        findsNothing,
        reason: 'on ne négocie pas de nulle avec Deep Grey',
      );
      expect(
        find.byTooltip('Abandonner'),
        findsOneWidget,
        reason: 'seul le joueur humain abandonne',
      );
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

      expect(find.text('<<'), findsOneWidget);
      expect(find.byTooltip('Pause'), findsNothing);
      expect(find.text('Deep Grey'), findsOneWidget);
      expect(find.text('Analyser'), findsNothing, reason: 'on y est déjà');
      expect(find.text('Rapide'), findsNothing);
    });

    testWidgets('aucun geste de partie', (tester) async {
      await open(tester, analysis: true);

      expect(find.byTooltip('Proposer nulle'), findsNothing);
      expect(find.byTooltip('Abandonner'), findsNothing);
      expect(find.byTooltip('Annuler'), findsNothing);
    });

    testWidgets('venue d une correspondance, Deep Grey est interdit', (
      tester,
    ) async {
      await open(tester, analysis: true, analysisFromCorr: true);

      expect(
        find.text('Deep Grey'),
        findsNothing,
        reason: "l'IA soufflerait le coup d'une partie en cours",
      );
      expect(find.text('<<'), findsOneWidget);
    });
  });
}
