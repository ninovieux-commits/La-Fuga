/// La lecture automatique d'une partie de l'historique.
///
/// Nino : « un bouton (lecture automatique). Là en bas du plateau au lieu des
/// infos habituelles (on garde que les pièces capturées) on met un curseur
/// […] de 0.5 à 5 sec, avec un cran toutes les 0.5 sec. Juste en dessous de ce
/// curseur un bouton revenir au début et un bouton play/pause. »
///
/// Il y a eu ici un troisième réglage, « choisir une rythmique » : huit danses
/// avec leurs tempos, leurs accents et leurs notes inégales. Essayé sur un vrai
/// téléphone, cela ne tenait pas à l'oreille — une partie n'est pas une
/// mélodie. « Enlève les rythmiques finalement, laisse juste le curseur de
/// temps. »
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/game/vitesse_lecture.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/replay_screen.dart';
import 'package:lafuga/ui/widgets/auto_play_bar.dart';
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

  Future<void> ouvrir(WidgetTester tester, {FauxSons? sons}) async {
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ReplayScreen(nmc: _nmc, sounds: sons),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// La lecture automatique s'ouvre par « Plus » : Nino a retiré la touche
  /// « play » du bandeau et rangé les quatre gestes du lecteur derrière une
  /// seule touche.
  Future<void> lancerLaLecture(WidgetTester tester) async {
    await tester.tap(find.text('Plus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lire la partie'));
    await tester.pumpAndSettle();
  }

  /// Et elle se referme par la même touche, qui dit alors « Arrêter ».
  Future<void> arreterLaLecture(WidgetTester tester) async {
    await tester.tap(find.text('Plus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arrêter la lecture'));
    await tester.pumpAndSettle();
  }

  Future<void> ouvrirAuto(WidgetTester tester, {FauxSons? sons}) async {
    await ouvrir(tester, sons: sons);
    await lancerLaLecture(tester);
  }

  AutoPlayBar barre(WidgetTester tester) =>
      tester.widget<AutoPlayBar>(find.byType(AutoPlayBar));

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

      await lancerLaLecture(tester);

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

    testWidgets('le curseur, puis les deux touches en dessous', (tester) async {
      await ouvrirAuto(tester);
      final curseur = tester.getCenter(find.byType(Slider));
      final debut = tester.getCenter(find.textContaining('Début'));
      expect(debut.dy, greaterThan(curseur.dy), reason: 'sous le curseur');
      expect(
        find.textContaining('rythmique'),
        findsNothing,
        reason: 'les danses ont été retirées',
      );
    });

    testWidgets('et on peut les refermer', (tester) async {
      await ouvrirAuto(tester);
      await arreterLaLecture(tester);
      expect(find.byType(AutoPlayBar), findsNothing);
      expect(find.byType(PlayerPanel), findsNWidgets(2));
    });
  });

  group('Le curseur', () {
    testWidgets('il va de 0,5 à 5 par demi-secondes, et il est actif', (
      tester,
    ) async {
      await ouvrirAuto(tester);
      final s = tester.widget<Slider>(find.byType(Slider));
      expect(s.min, kVitesseMin);
      expect(s.max, kVitesseMax);
      expect(
        s.divisions,
        kVitesseCrans - 1,
        reason: 'dix crans de 0,5 à 5,0 font neuf intervalles',
      );
      expect(
        s.onChanged,
        isNotNull,
        reason: 'plus rien ne peut l éteindre : c est le seul réglage',
      );
    });

    testWidgets('il part à une seconde, et affiche ce qu il vaut', (
      tester,
    ) async {
      await ouvrirAuto(tester);
      expect(tester.widget<Slider>(find.byType(Slider)).value, kVitesseDefaut);
      expect(find.text('1.0 s'), findsOneWidget);

      barre(tester).onTempo(2.5);
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 2.5);
      expect(find.text('2.5 s'), findsOneWidget);
    });
  });

  group('Ça défile, à la cadence du curseur', () {
    testWidgets('un coup par intervalle, et pas avant', (tester) async {
      await ouvrirAuto(tester);
      barre(tester).onTempo(2.0);
      await tester.pumpAndSettle();
      barre(tester).onDebut();
      await tester.pumpAndSettle();
      final depart = coupRegarde(tester);

      barre(tester).onPlayPause();
      await tester.pump();

      // Juste avant l'échéance : rien n'a bougé.
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

    testWidgets('les intervalles sont ÉGAUX, du premier au dernier', (
      tester,
    ) async {
      // Un seul réglage, une seule cadence : rien ne doit boiter. Que des
      // `pump` exacts, jamais `pumpAndSettle` en cours de route — celui-ci
      // avance l'horloge de toute la durée des animations.
      await ouvrirAuto(tester);
      barre(tester).onTempo(1.0);
      await tester.pumpAndSettle();
      barre(tester).onDebut();
      await tester.pumpAndSettle();
      final depart = coupRegarde(tester);

      // On compte en temps ABSOLU depuis le départ. Pomper « 900 puis 150 »
      // à chaque tour ferait avancer l'horloge de 1 050 ms pour un intervalle
      // de 1 000 : le décalage s'accumule et finit par dépasser l'échéance.
      var ecoule = 0;
      Future<void> jusqua(int ms) async {
        await tester.pump(Duration(milliseconds: ms - ecoule));
        ecoule = ms;
      }

      barre(tester).onPlayPause();
      for (var n = 1; n <= 4; n++) {
        await jusqua(n * 1000 - 100);
        expect(
          coupRegarde(tester),
          depart + n - 1,
          reason: 'le coup $n n est pas encore dû',
        );
        await jusqua(n * 1000 + 100);
        expect(coupRegarde(tester), depart + n, reason: 'le coup $n est dû');
      }
      await tester.pumpAndSettle();
    });

    testWidgets('la pause arrête tout', (tester) async {
      await ouvrirAuto(tester);
      barre(tester).onTempo(0.5);
      await tester.pumpAndSettle();
      barre(tester).onPlayPause();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      final apres = coupRegarde(tester);

      barre(tester).onPlayPause();
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
      barre(tester).onTempo(0.5);
      await tester.pumpAndSettle();
      barre(tester).onPlayPause();
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
      expect(coupRegarde(tester), greaterThan(0));

      barre(tester).onDebut();
      await tester.pumpAndSettle();
      expect(
        coupRegarde(tester),
        lessThanOrEqualTo(0),
        reason: '« Début » n a pas ramené au premier coup',
      );
    });

    testWidgets('arrivé au bout, ça s arrête', (tester) async {
      await ouvrirAuto(tester);
      barre(tester).onTempo(0.5);
      await tester.pumpAndSettle();
      barre(tester).onPlayPause();
      // Largement de quoi dépasser les six coups.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pumpAndSettle();
      expect(
        barre(tester).enLecture,
        isFalse,
        reason: 'le lecteur doit s arrêter au dernier coup, pas reboucler',
      );
    });
  });

  group('Chaque coup joue son son', () {
    testWidgets('un coup, un envoi, et rien de plus', (tester) async {
      // Le son part coup par coup, comme partout ailleurs dans l'application.
      // Le groupement par mesure n'existait que pour tenir la cadence serrée
      // d'une danse ; sans elles, les écarts font une demi-seconde au moins.
      final sons = FauxSons();
      await ouvrirAuto(tester, sons: sons);
      barre(tester).onTempo(0.5);
      await tester.pumpAndSettle();
      sons.joues.clear();

      barre(tester).onPlayPause();
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 550));
      }
      await tester.pumpAndSettle();

      expect(sons.joues.length, 3, reason: 'un son par coup joué');
      expect(
        sons.joues,
        everyElement(isNotEmpty),
        reason: 'chaque coup a bien une notation à jouer',
      );
    });
  });
}
