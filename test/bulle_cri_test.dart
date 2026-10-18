/// La bulle de cri : forme, déclenchement, et les deux endroits où elle sert.
///
/// Nino : « lorsqu'un message se finit par "!" ou "!?", ça fait des bulles
/// avec des pics comme ça, que ce soit dans la boîte de chat ou ingame. »
/// Puis : « creux marqués mais avec pics plus larges, on enlève le truc qui
/// est censé servir de queue. »
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/bulle_cri.dart';
import 'package:lafuga/ui/widgets/bulles_en_jeu.dart';
import 'package:lafuga/ui/widgets/message_bubble.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Trouve la bulle hérissée, où qu'elle soit dans l'arbre.
final Finder lesPics = find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is PeintreBulleCri,
);

Future<void> pose(WidgetTester tester, Widget enfant) async {
  tester.view.physicalSize = const Size(393, 851);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: enfant)),
    ),
  );
  await tester.pumpAndSettle();
}

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

  // -------------------------------------------------------------------------
  // Ce qui déclenche le cri
  // -------------------------------------------------------------------------

  test('« ! » et ses variantes crient, « ? » seul ne crie pas', () {
    for (final cri in [
      'Et paf !',
      'Et paf!',
      'Quoi !?',
      'Quoi ?!',
      'Non !!!',
      '!',
      'Et paf !   ', // les espaces de fin ne comptent pas
      // « Le seul truc qu'il doit pouvoir y avoir derrière et que ça marche
      // toujours sont des espaces ou des emojis. »
      'Bien joué ! 🎉',
      'Bien joué !🎉🎉🎉',
      'Quoi !? 😱',
      'Bravo ! 👍🏽', // un émoji et sa teinte de peau
      'Bravo ! 👨‍👩‍👧', // une suite cousue par des liants
      'Bravo ! 🇫🇷', // un drapeau, deux indicateurs
      'Bravo !  🎉  ',
    ]) {
      expect(estUnCri(cri), isTrue, reason: '« $cri » devrait crier');
    }
    for (final calme in [
      'Et paf.',
      'Et paf',
      'Quoi ?',
      'Quoi ??',
      '',
      '   ',
      'Et paf ! Puis non.', // le « ! » n'est pas à la fin
      'Et paf ! 🎉 puis non', // ni là : l'émoji n'est pas le dernier mot
      '?',
      '🎉', // un émoji seul n'est pas un cri
      'J en ai 3', // un chiffre n'est pas un émoji, même en fin de phrase
      'Bien joué 🎉', // sans « ! », rien ne crie
    ]) {
      expect(estUnCri(calme), isFalse, reason: '« $calme » ne devrait pas');
    }
  });

  // -------------------------------------------------------------------------
  // La forme
  // -------------------------------------------------------------------------

  group('le contour', () {
    final base = RRect.fromRectAndRadius(
      const Rect.fromLTWH(40, 40, 220, 70),
      const Radius.circular(18),
    );
    final chemin = cheminBulleCri(base, haut: 16, court: 8, pas: 38, creux: 5);

    test('aucun pic ne dépasse la marge réservée', () {
      // C'est l'invariant qui compte : le peintre réserve kPicHaut tout
      // autour, et un pic plus long que cette marge sortirait de la boîte —
      // donc serait rogné par la liste des messages.
      final bords = chemin.getBounds();
      final r = base.outerRect;
      final sorties = {
        'gauche': r.left - bords.left,
        'haut': r.top - bords.top,
        'droite': bords.right - r.right,
        'bas': bords.bottom - r.bottom,
      };
      for (final cote in sorties.entries) {
        expect(
          cote.value,
          inInclusiveRange(8 - 1, 16 + 1),
          reason: 'le côté ${cote.key} sort de ${cote.value}',
        );
      }
      // Et la marge sert : au moins un côté porte un grand pic. Un petit côté
      // peut n'en recevoir que des courts — c'est la longueur du contour qui
      // décide, pas le côté.
      expect(sorties.values.reduce((a, b) => a > b ? a : b), closeTo(16, 1.5));
    });

    test('les creux mordent sous le contour, pas seulement dessus', () {
      // Juste SOUS le bord haut de la bulle d'origine : si les creux
      // existent, une partie de cette ligne est hors de la forme.
      final y = base.outerRect.top + 5 - 1;
      var dedans = 0;
      var dehors = 0;
      for (
        var x = base.outerRect.left + 30;
        x < base.outerRect.right - 30;
        x += 2
      ) {
        chemin.contains(Offset(x, y)) ? dedans++ : dehors++;
      }
      expect(dehors, greaterThan(0), reason: 'aucun creux ne mord');
      expect(dedans, greaterThan(0), reason: 'le bord entier a été mangé');
    });

    test('le cœur de la bulle reste plein', () {
      expect(chemin.contains(base.outerRect.center), isTrue);
    });

    test('les pics alternent deux tailles', () {
      // Sur la ligne qui passe au-dessus du bord d'un creux de 8, seuls les
      // GRANDS pics sont encore là : il y en a donc moins que de pics.
      final haut = base.outerRect.top;
      int traverse(double y) {
        var changements = 0;
        var avant = false;
        for (var x = base.outerRect.left; x < base.outerRect.right; x += 0.5) {
          final ici = chemin.contains(Offset(x, y));
          if (ici != avant) changements++;
          avant = ici;
        }
        return changements;
      }

      final tous = traverse(haut - 6); // au-dessus des petits pics
      final grands = traverse(haut - 12); // au-dessus des grands seulement
      expect(grands, greaterThan(0), reason: 'aucun grand pic');
      expect(
        grands,
        lessThan(tous),
        reason: 'tous les pics ont la même taille',
      );
    });

    test('un contour fermé, donc peignable', () async {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawPath(chemin, Paint()..color = const Color(0xFF0080FF));
      final img = await rec.endRecording().toImage(300, 150);
      final d = await img.toByteData();
      var peints = 0;
      for (var i = 3; i < d!.lengthInBytes; i += 4) {
        if (d.getUint8(i) > 0) peints++;
      }
      expect(peints, greaterThan(10000), reason: 'la forme est vide');
    });
  });

  // -------------------------------------------------------------------------
  // Dans la boîte de chat
  // -------------------------------------------------------------------------

  testWidgets('un message qui finit par « ! » prend les pics', (tester) async {
    await pose(
      tester,
      MessageBubble(
        texte: 'Et paf !',
        deMoi: false,
        palette: paletteOf('original'),
      ),
    );
    expect(lesPics, findsOneWidget);
  });

  testWidgets('un message ordinaire garde sa bulle ronde', (tester) async {
    await pose(
      tester,
      MessageBubble(
        texte: 'Et paf.',
        deMoi: false,
        palette: paletteOf('original'),
      ),
    );
    expect(lesPics, findsNothing);
  });

  testWidgets('le texte garde son air : la bulle grandit du creux', (
    tester,
  ) async {
    Future<Size> mesure(String texte) async {
      await pose(
        tester,
        MessageBubble(
          texte: texte,
          deMoi: false,
          palette: paletteOf('original'),
        ),
      );
      return tester.getSize(find.byType(MessageBubble));
    }

    // Même longueur de texte — la police des tests donne à tous les signes la
    // même avance, donc l'écart mesuré ne vient que de la forme.
    final calme = await mesure('Et paf .');
    final cri = await mesure('Et paf !');
    final marge = (S(kPicHaut) + S(kPicCreux)) * 2;
    expect(cri.width - calme.width, closeTo(marge, 1));
    expect(cri.height - calme.height, closeTo(marge, 1));
  });

  testWidgets('un envoi échoué crie quand même', (tester) async {
    await pose(
      tester,
      MessageBubble(
        texte: 'Et paf !',
        deMoi: true,
        echoue: true,
        palette: paletteOf('original'),
      ),
    );
    expect(lesPics, findsOneWidget);
    final peintre =
        tester.widget<CustomPaint>(lesPics).painter! as PeintreBulleCri;
    expect(peintre.fond, const Color.fromRGBO(120, 40, 40, 1));
  });

  testWidgets('un émoji seul reste nu', (tester) async {
    await pose(
      tester,
      MessageBubble(texte: '😀', deMoi: false, palette: paletteOf('original')),
    );
    expect(lesPics, findsNothing);
  });

  // -------------------------------------------------------------------------
  // Sur le plateau
  // -------------------------------------------------------------------------

  testWidgets('le cri crie aussi dans le bandeau de la partie', (tester) async {
    final flux = StreamController<BulleEnJeu>.broadcast();
    addTearDown(flux.close);
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 393,
            height: 851 * 12 / 104,
            child: BullesEnJeu(
              flux: flux.stream,
              palette: paletteOf('original'),
            ),
          ),
        ),
      ),
    );
    flux.add((texte: 'Et paf !', deMoi: false));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(lesPics, findsOneWidget);

    flux.add((texte: 'Bien joué.', deMoi: true));
    await tester.pump();
    await tester.pumpAndSettle();
    // Le premier crie toujours, le second non : un seul hérissé sur deux.
    expect(lesPics, findsOneWidget);
    expect(find.byType(MessageBubble), findsNWidgets(2));
  });
}
