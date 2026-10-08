/// La lecture automatique d'une partie de l'historique.
///
/// Nino : « un bouton (lecture automatique). Là en bas du plateau au lieu des
/// infos habituelles (on garde que les pièces capturées) on met un curseur
/// […] de 0.5 à 5 sec, avec un cran toutes les 0.5 sec. Juste en dessous de ce
/// curseur un bouton revenir au début et un bouton play/pause. Encore en
/// dessous, un bouton (choisir une rythmique) […] On ne peut plus régler la
/// vitesse si l'on a choisi une rythmique. »
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/game/rythmique.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/replay_screen.dart';
import 'package:lafuga/ui/widgets/auto_play_bar.dart';
import 'package:lafuga/ui/widgets/game_top_bar.dart';
import 'package:lafuga/ui/widgets/move_strip.dart';
import 'package:lafuga/ui/widgets/player_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'son_coup_adverse_test.dart' show FauxSons;

/// Six coups, assez pour voir défiler.
const String _nmc =
    '[Date "2026-10-06"]\n'
    '[Joueur1 "nino"]\n'
    '[Joueur2 "celia"]\n'
    '[Blanc "nino"]\n'
    '[Cadence "zen"]\n\n'
    '1.Do2-Do3/Do7-Do6\n'
    '2.Ré2-Ré3/Ré7-Ré6\n'
    '3.Mi2-Mi3/Mi7-Mi6';

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
    await tester.pumpWidget(const MaterialApp(home: ReplayScreen(nmc: _nmc)));
    await tester.pumpAndSettle();
  }

  Future<void> ouvrirAuto(WidgetTester tester) async {
    await ouvrir(tester);
    tester.widget<GameTopBar>(find.byType(GameTopBar)).onAutoPlay!();
    await tester.pumpAndSettle();
  }

  /// Le coup regardé, lu dans le bandeau.
  int coupRegarde(WidgetTester tester) =>
      tester.widget<MoveStrip>(find.byType(MoveStrip)).activeIndex ?? -1;

  group('Ouvrir la lecture automatique', () {
    testWidgets('les commandes remplacent les infos du joueur du bas', (
      tester,
    ) async {
      await ouvrir(tester);
      expect(find.byType(AutoPlayBar), findsNothing);
      expect(find.byType(PlayerPanel), findsNWidgets(2));

      tester.widget<GameTopBar>(find.byType(GameTopBar)).onAutoPlay!();
      await tester.pumpAndSettle();

      expect(find.byType(AutoPlayBar), findsOneWidget);
      expect(
        find.byType(PlayerPanel),
        findsOneWidget,
        reason: 'seul le panneau du HAUT reste',
      );
      expect(
        find.byType(CapturesStrip),
        findsWidgets,
        reason: 'on garde les pièces capturées',
      );
    });

    testWidgets('les trois commandes sont là, dans cet ordre', (tester) async {
      await ouvrirAuto(tester);
      final curseur = tester.getCenter(find.byType(Slider));
      final debut = tester.getCenter(find.textContaining('Début'));
      final rythme = tester.getCenter(find.text('Choisir une rythmique'));
      expect(debut.dy, greaterThan(curseur.dy), reason: 'sous le curseur');
      expect(rythme.dy, greaterThan(debut.dy), reason: 'encore en dessous');
    });

    testWidgets('et on peut les refermer', (tester) async {
      await ouvrirAuto(tester);
      tester.widget<GameTopBar>(find.byType(GameTopBar)).onAutoPlay!();
      await tester.pumpAndSettle();
      expect(find.byType(AutoPlayBar), findsNothing);
      expect(find.byType(PlayerPanel), findsNWidgets(2));
    });
  });

  group('Le curseur', () {
    testWidgets('il va de 0,5 à 5 par demi-secondes', (tester) async {
      await ouvrirAuto(tester);
      final s = tester.widget<Slider>(find.byType(Slider));
      expect(s.min, 0.5);
      expect(s.max, 5.0);
      expect(
        s.divisions,
        9,
        reason: 'dix crans de 0,5 à 5,0 font neuf intervalles',
      );
      expect(s.onChanged, isNotNull);
    });

    testWidgets('une rythmique choisie l éteint', (tester) async {
      await ouvrirAuto(tester);
      tester
          .widget<AutoPlayBar>(find.byType(AutoPlayBar))
          .onRythmique(Rythmique.sarabande);
      await tester.pumpAndSettle();

      expect(
        tester.widget<Slider>(find.byType(Slider)).onChanged,
        isNull,
        reason: 'on ne règle plus la vitesse quand une rythmique est choisie',
      );
      expect(find.textContaining('Sarabande 3/2'), findsWidgets);
    });

    testWidgets('revenir à la main le rallume', (tester) async {
      await ouvrirAuto(tester);
      final barre = tester.widget<AutoPlayBar>(find.byType(AutoPlayBar));
      barre.onRythmique(Rythmique.gigue);
      await tester.pumpAndSettle();
      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onRythmique(null);
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
      expect(find.text('Choisir une rythmique'), findsOneWidget);
    });
  });

  group('Ça défile, à la bonne cadence', () {
    testWidgets('un coup par temps, et pas avant', (tester) async {
      await ouvrirAuto(tester);
      final barre = tester.widget<AutoPlayBar>(find.byType(AutoPlayBar));
      barre.onTempo(2.0);
      await tester.pumpAndSettle();
      barre.onDebut();
      await tester.pumpAndSettle();
      final depart = coupRegarde(tester);

      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onPlayPause();
      await tester.pump();

      // Juste avant le temps : rien n'a bougé.
      await tester.pump(const Duration(milliseconds: 1900));
      expect(
        coupRegarde(tester),
        depart,
        reason: 'un coup est parti avant son temps',
      );

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(coupRegarde(tester), depart + 1);
    });

    testWidgets('la pause arrête tout', (tester) async {
      await ouvrirAuto(tester);
      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onTempo(0.5);
      await tester.pumpAndSettle();
      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onPlayPause();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      final apres = coupRegarde(tester);

      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onPlayPause();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(
        coupRegarde(tester),
        apres,
        reason: 'ça continue de défiler après la pause',
      );
    });

    testWidgets('« Début » ramène au premier coup', (tester) async {
      await ouvrirAuto(tester);
      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onTempo(0.5);
      await tester.pumpAndSettle();
      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onPlayPause();
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
      expect(coupRegarde(tester), greaterThan(0));

      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onDebut();
      await tester.pumpAndSettle();
      expect(
        coupRegarde(tester),
        lessThanOrEqualTo(0),
        reason: '« Début » n a pas ramené au premier coup',
      );
    });

    testWidgets('une rythmique impose SA cadence', (tester) async {
      await ouvrirAuto(tester);
      // Sarabande : 60 à la minute, donc une seconde pile par temps.
      tester
          .widget<AutoPlayBar>(find.byType(AutoPlayBar))
          .onRythmique(Rythmique.sarabande);
      await tester.pumpAndSettle();
      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onDebut();
      await tester.pumpAndSettle();
      final depart = coupRegarde(tester);

      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onPlayPause();
      await tester.pump(const Duration(milliseconds: 900));
      expect(
        coupRegarde(tester),
        depart,
        reason: 'la sarabande a joué avant sa seconde',
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(coupRegarde(tester), depart + 1);
    });

    testWidgets('la VALSE pose ses trois notes SUR LES TROIS TEMPS', (
      tester,
    ) async {
      // « Oui fais ça, trois notes sur les trois temps. » Le oum-pa-pa : les
      // écarts sont ÉGAUX, et c'est l'accent qui fait le « taaam ». À 170, le
      // temps vaut 353 ms : les coups tombent à 353, 706, 1059, 1412 ms.
      //
      // Que des `pump` exacts, jamais `pumpAndSettle` en cours de route :
      // celui-ci avance l'horloge de toute la durée des animations.
      await ouvrirAuto(tester);
      tester
          .widget<AutoPlayBar>(find.byType(AutoPlayBar))
          .onRythmique(Rythmique.valse);
      await tester.pumpAndSettle();
      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onDebut();
      await tester.pumpAndSettle();
      final depart = coupRegarde(tester);

      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onPlayPause();
      // Quatre coups, quatre fois le MÊME écart : trois notes par mesure, et
      // la mesure suivante enchaîne sur le même pas.
      for (var n = 1; n <= 4; n++) {
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          coupRegarde(tester),
          depart + n - 1,
          reason: 'le coup $n n est pas encore dû',
        );
        await tester.pump(const Duration(milliseconds: 103));
        expect(
          coupRegarde(tester),
          depart + n,
          reason: 'le coup $n tombe sur son temps',
        );
      }
      await tester.pumpAndSettle();
    });

    testWidgets('la sarabande BOITE dans l AUTRE sens : court, puis long', (
      tester,
    ) async {
      // Elle appuie et ALLONGE son deuxième temps — l'inverse de la valse. À
      // 60 à la blanche, le temps vaut une seconde : coups à 1 s, 3 s, 4 s…
      await ouvrirAuto(tester);
      tester
          .widget<AutoPlayBar>(find.byType(AutoPlayBar))
          .onRythmique(Rythmique.sarabande);
      await tester.pumpAndSettle();
      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onDebut();
      await tester.pumpAndSettle();
      final depart = coupRegarde(tester);

      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onPlayPause();
      await tester.pump(const Duration(milliseconds: 900));
      expect(coupRegarde(tester), depart);
      await tester.pump(const Duration(milliseconds: 200)); // 1100 ms
      expect(coupRegarde(tester), depart + 1);
      // Deuxième écart : DEUX temps. Une seconde de plus ne suffit pas.
      await tester.pump(const Duration(milliseconds: 800)); // 1900 ms
      expect(
        coupRegarde(tester),
        depart + 1,
        reason: 'le deuxième temps est tenu : deux secondes, pas une',
      );
      await tester.pump(const Duration(milliseconds: 1200)); // 3100 ms
      expect(coupRegarde(tester), depart + 2);
      await tester.pumpAndSettle();
    });

    testWidgets('la gigue galope sur ses croches', (tester) async {
      // Deux croches, une croche. À 80 noires pointées, la croche vaut 250 ms :
      // les coups tombent à 500 ms, 750 ms, 1250 ms…
      await ouvrirAuto(tester);
      tester
          .widget<AutoPlayBar>(find.byType(AutoPlayBar))
          .onRythmique(Rythmique.gigue);
      await tester.pumpAndSettle();
      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onDebut();
      await tester.pumpAndSettle();
      final depart = coupRegarde(tester);

      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onPlayPause();
      await tester.pump(const Duration(milliseconds: 400));
      expect(coupRegarde(tester), depart, reason: 'la note de deux croches');
      await tester.pump(const Duration(milliseconds: 150)); // 550 ms
      expect(coupRegarde(tester), depart + 1);
      // La croche seule : moitié moins d'attente.
      await tester.pump(const Duration(milliseconds: 150)); // 700 ms
      expect(coupRegarde(tester), depart + 1);
      await tester.pump(const Duration(milliseconds: 100)); // 800 ms
      expect(coupRegarde(tester), depart + 2);
      await tester.pumpAndSettle();
    });

    testWidgets('arrivé au bout, ça s arrête', (tester) async {
      await ouvrirAuto(tester);
      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onTempo(0.5);
      await tester.pumpAndSettle();
      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onPlayPause();
      // Largement de quoi dépasser les six coups.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pumpAndSettle();
      expect(
        tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).enLecture,
        isFalse,
        reason: 'le lecteur doit s arrêter au dernier coup, pas reboucler',
      );
    });
  });

  group('Une mesure part en UN SEUL son', () {
    /// Ouvre la lecture automatique avec un lecteur de sons espion.
    Future<FauxSons> ouvrirAvecSons(WidgetTester tester) async {
      final sons = FauxSons();
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ReplayScreen(nmc: _nmc, sounds: sons),
        ),
      );
      await tester.pumpAndSettle();
      tester.widget<GameTopBar>(find.byType(GameTopBar)).onAutoPlay!();
      await tester.pumpAndSettle();
      return sons;
    }

    Future<FauxSons> jouer(WidgetTester tester, Rythmique? danse) async {
      final sons = await ouvrirAvecSons(tester);
      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onRythmique(danse);
      await tester.pumpAndSettle();
      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onDebut();
      await tester.pumpAndSettle();
      sons.envois.clear();
      sons.joues.clear();
      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onPlayPause();
      return sons;
    }

    testWidgets('trois coups de valse, UN envoi : la cadence est gravée', (
      tester,
    ) async {
      // Le défaut que Nino a entendu : « les coups joués finissent par aller
      // plus vite que les sons et les distancent. » Un envoi par coup coûte un
      // démarrage de lecteur audio, et à trois coups par seconde le retard
      // s'accumule. Une mesure entière part donc d'un bloc, chaque note à son
      // retard en échantillons : elle ne peut plus dériver.
      final sons = await jouer(tester, Rythmique.valse);
      // La mesure dure 1,06 s ; on s'arrête avant la suivante.
      await tester.pump(const Duration(milliseconds: 1000));

      expect(
        sons.envois.length,
        1,
        reason: 'UN envoi pour les trois coups de la mesure',
      );
      expect(
        sons.joues,
        isEmpty,
        reason: 'aucun coup ne doit envoyer son son tout seul',
      );

      final cues = sons.envois.single;
      expect(cues.length, 3, reason: 'les trois notes de la mesure');
      // Les retards : un temps d'écart entre chaque. À 170, le temps vaut
      // 353 ms.
      final temps = Rythmique.valse.parTemps;
      expect(cues[0].delay, Duration.zero);
      expect(cues[1].delay, temps, reason: 'sur le deuxième temps');
      expect(cues[2].delay, temps * 2, reason: 'sur le troisième');
      await tester.pumpAndSettle();
    });

    testWidgets('et chaque note de la mesure porte son accent', (tester) async {
      final sons = await jouer(tester, Rythmique.valse);
      await tester.pump(const Duration(milliseconds: 1000));

      final cues = sons.envois.single;
      expect(cues[0].gain, 1.0, reason: 'le premier temps, à pleine voix');
      expect(cues[1].gain, lessThan(1.0), reason: 'le deuxième, retenu');
      expect(cues[2].gain, lessThan(1.0), reason: 'le troisième, retenu');
      await tester.pumpAndSettle();
    });

    testWidgets('la mesure suivante part à son tour, et réaccentue', (
      tester,
    ) async {
      final sons = await jouer(tester, Rythmique.valse);
      await tester.pump(const Duration(milliseconds: 1700));

      expect(sons.envois.length, 2, reason: 'une mesure, puis la suivante');
      expect(sons.envois[1].first.gain, 1.0);
      await tester.pumpAndSettle();
    });

    testWidgets('la sarabande appuie son DEUXIÈME temps', (tester) async {
      final sons = await jouer(tester, Rythmique.sarabande);
      await tester.pump(const Duration(milliseconds: 1500));

      final cues = sons.envois.first;
      expect(cues.length, 2);
      expect(
        cues[0].gain,
        lessThan(cues[1].gain),
        reason: 'c est le deuxième temps qui porte l accent',
      );
      expect(cues[1].gain, 1.0);
      await tester.pumpAndSettle();
    });

    testWidgets('à la main, un coup = un envoi, et pas d accent', (
      tester,
    ) async {
      // Hors d'une danse les écarts font une demi-seconde au moins : rien ne
      // presse, et le comportement d'avant ne bouge pas d'un octet.
      final sons = await ouvrirAvecSons(tester);
      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onTempo(0.5);
      await tester.pumpAndSettle();
      sons.envois.clear();
      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar)).onPlayPause();
      await tester.pump(const Duration(milliseconds: 1600));

      expect(sons.envois.length, 3, reason: 'un envoi par coup');
      for (final envoi in sons.envois) {
        for (final cue in envoi) {
          expect(cue.gain, 1.0, reason: 'aucun coup plus fort qu un autre');
          expect(cue.delay, Duration.zero);
        }
      }
      await tester.pumpAndSettle();
    });
  });
}
