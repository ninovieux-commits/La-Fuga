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
      // Sarabande : 60 à la minute, donc une seconde pile par coup.
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
}
