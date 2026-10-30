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
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/game/vitesse_lecture.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/replay_screen.dart';
import 'package:lafuga/ui/widgets/auto_play_bar.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:lafuga/ui/widgets/move_strip.dart';
import 'package:lafuga/ui/widgets/player_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'son_coup_adverse_test.dart' show FauxSons;

/// Les demi-coups de `_nmc`.
const int _nombreDeCoups = 6;

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

  /// La lecture automatique s'ouvre par la touche « + » : Nino a retiré la
  /// touche « play » du bandeau et rangé les quatre gestes du lecteur derrière
  /// une seule touche, qui porte maintenant un gros « + ».
  Future<void> lancerLaLecture(WidgetTester tester) async {
    await tester.tap(find.text('+'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lire la partie'));
    await tester.pumpAndSettle();
  }

  /// Et elle se referme par la même touche, qui dit alors « Arrêter ».
  Future<void> arreterLaLecture(WidgetTester tester) async {
    await tester.tap(find.text('+'));
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

    testWidgets('les touches près du plateau, le curseur sous elles', (
      tester,
    ) async {
      // LE BANDEAU DU BAS EST UN MIROIR, comme dans une partie : la rangée
      // qui touche le plateau porte les prises et les touches, et c'est au
      // chrono — absent en lecture — que le curseur prend sa place.
      await ouvrirAuto(tester);
      final curseur = tester.getCenter(find.byType(Slider));
      // La touche ne porte plus de mot : c'est le signe dessiné qui la
      // désigne.
      final debut = tester.getCenter(find.byType(GlypheDebut));
      expect(debut.dy, lessThan(curseur.dy), reason: 'au-dessus du curseur');
      expect(
        find.textContaining('rythmique'),
        findsNothing,
        reason: 'les danses ont été retirées',
      );
    });

    testWidgets('tout tient à l écran : rien ne défile, rien ne recouvre', (
      tester,
    ) async {
      // Nino : « le bandeau fin du bas ne doit pas défiler avec le reste de
      // la page, il doit être statique » et « si on fait bien les choses,
      // peut-être que tout peut rentrer sur l'écran et qu'il n'y aura plus
      // besoin de défilement. Ce serait l'idéal. » Les commandes tenant
      // maintenant dans le bandeau du joueur du bas, l'écran retrouve ses
      // 7 + 12 + 66 + 12 + 7 : le plateau ne déborde plus sur personne.
      await ouvrirAuto(tester);
      final plateau = find.byType(GameBoardView);
      final place = tester.getRect(plateau);

      final recouvrement = (place.width * kExtRows / kCols - place.height) / 2;
      expect(
        recouvrement,
        lessThan(1),
        reason: 'le plateau tient dans la place qu on lui donne',
      );

      // Les deux bandeaux larges sont là, et le plateau est entre eux.
      final haut = tester.getRect(find.byType(PlayerPanel));
      final bas = tester.getRect(find.byType(AutoPlayBar));
      expect(haut.bottom, lessThanOrEqualTo(place.top + 1));
      expect(bas.top, greaterThanOrEqualTo(place.bottom - 1));

      // Le bandeau fin des coups ferme l'écran, et il ne bouge pas d'un pouce.
      final coups = tester.getRect(find.byType(MoveStrip));
      expect(coups.top, greaterThanOrEqualTo(bas.bottom - 1));
      await tester.drag(plateau, const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(MoveStrip)), coups);
      expect(tester.getRect(plateau), place);
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

    // Nino, après ses essais : « le temps de lecture par défaut doit être
    // 2 sec, car c'est le réglage idéal selon mes tests. »
    testWidgets('il part à DEUX secondes, et affiche ce qu il vaut', (
      tester,
    ) async {
      await ouvrirAuto(tester);
      expect(kVitesseDefaut, 2.0);
      expect(tester.widget<Slider>(find.byType(Slider)).value, kVitesseDefaut);
      expect(find.text('2.0 s'), findsOneWidget);

      barre(tester).onTempo(2.5);
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 2.5);
      expect(find.text('2.5 s'), findsOneWidget);
    });
  });

  group('Ça défile, à la cadence du curseur', () {
    // Nino : « les coups dans le bandeau fin du bas doivent défiler avec la
    // partie. » Le bandeau ne se recalait qu'au présent : une partie lue
    // défilait sur le plateau pendant que le bandeau restait sur ses premiers
    // coups.
    testWidgets('le bandeau des coups suit le coup lu', (tester) async {
      await ouvrirAuto(tester);
      // Au premier coup : la liste est tout à gauche.
      barre(tester).onDebut();
      await tester.pumpAndSettle();
      final liste = find.descendant(
        of: find.byType(MoveStrip),
        matching: find.byType(Scrollable),
      );
      expect(tester.widget<Scrollable>(liste).controller!.offset, 0);

      // On va au dernier coup : le bandeau l'a amené à l'écran.
      for (var i = 0; i < 5; i++) {
        barre(tester).onPlayPause();
        barre(tester).onPlayPause();
      }
      tester
          .widget<MoveStrip>(find.byType(MoveStrip))
          .onSelect(_nombreDeCoups - 1);
      await tester.pumpAndSettle();

      expect(
        tester.widget<Scrollable>(liste).controller!.offset,
        greaterThan(0),
        reason: 'le dernier coup est loin : le bandeau a dû défiler',
      );
    });

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
