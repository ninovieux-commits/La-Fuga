/// L'ÉDITEUR : le cadre bleu, la palette, le curseur et la gomme.
///
/// Nino, après l'avoir essayé : « le mode modification ne me convient pas.
/// Il ne doit pas y avoir un bouton déplacer. Ça doit plutôt marcher avec
/// des mouvements de doigt […] on ajoute un texte ou un tampon, celui-ci
/// apparaît dans un cadre bleu. Le cadre bleu est un cadre de sélection qui
/// permet de déplacer, agrandir ou rétrécir, pivoter. »
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/editeur_image_screen.dart';
import 'package:lafuga/ui/widgets/palette_couleurs.dart';
import 'package:lafuga/ui/widgets/tampon_partie.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un PNG d'un pixel : l'éditeur a besoin d'une image qui se décode.
final Uint8List kPixel = Uint8List.fromList([
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, //
  0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, //
  0, 0, 0, 13, 73, 68, 65, 84, 120, 218, 99, 252, 207, 192, 240, 31, 0, //
  5, 0, 1, 255, 171, 206, 54, 137, 0, 0, 0, 0, 73, 69, 78, 68, 174, //
  66, 96, 130,
]);

/// Les traits que le peintre a en main : c'est ce que le doigt a laissé.
///
/// On cherche LE peintre des traits, et non le premier `CustomPaint` venu :
/// une touche, une infobulle ou un bandeau en posent d'autres, et viser le
/// premier faisait regarder ailleurs.
List<TraitDessine> traits(WidgetTester tester) {
  final peinture = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .firstWhere((c) => c.painter is PeintreDesTraits);
  return (peinture.painter! as PeintreDesTraits).traits;
}

/// La surface d'édition : l'image elle-même, et la boîte où le doigt agit.
Finder get surface => find.byType(Image);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
      'theme': 'foret',
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
  });
  tearDown(resetScale);

  /// L'éditeur, ouvert et prêt.
  ///
  /// IL FAUT LAISSER L'IMAGE SE MESURER : la surface prend la forme de la
  /// photo, et cette forme vient d'un décodage qui ne se fait pas dans le
  /// temps arrêté d'un test. Sans ce `runAsync`, l'écran en reste à sa roue
  /// d'attente et rien n'est à l'écran.
  Future<void> ouvrir(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EditeurImageScreen(image: kPixel, moi: 'Nino', lui: 'celia'),
      ),
    );
    // ON ATTEND QUE L'IMAGE SOIT MESURÉE, sans parier sur une durée. Un
    // délai fixe de cinquante millisecondes suffisait sur une machine au
    // repos et pas sur une machine chargée : l'éditeur en restait à sa roue
    // d'attente, la barre d'outils n'existait pas encore, et le test tombait
    // une fois sur vingt — au milieu de la suite complète, jamais seul.
    //
    // UNE SECONDE N'A PAS SUFFI NON PLUS : la suite tourne maintenant à
    // plus de dix-sept cents essais, et la machine est d'autant plus
    // chargée. Le budget passe à quatre secondes. Il ne coûte rien quand
    // tout va bien — la boucle s'arrête dès que la roue disparaît.
    for (var i = 0; i < 200; i++) {
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: "l'image n'a pas fini de se mesurer",
    );
  }

  group('La barre', () {
    // Nino : « il ne doit pas y avoir un bouton déplacer. »
    testWidgets('plus de « déplacer », mais une gomme', (tester) async {
      await ouvrir(tester);

      expect(find.byTooltip('Déplacer'), findsNothing);
      expect(find.byTooltip('Gomme'), findsOneWidget);
      expect(find.byTooltip('Dessin'), findsOneWidget);
      expect(find.byTooltip('Texte'), findsOneWidget);
      expect(find.byTooltip('Tampon'), findsOneWidget);
      expect(find.byTooltip('Défaire'), findsOneWidget);
    });

    // Nino : « il doit y avoir un seul bouton couleur qui donne accès à une
    // palette complète. »
    testWidgets('une seule touche de couleur', (tester) async {
      await ouvrir(tester);
      expect(find.byTooltip('Couleur'), findsOneWidget);
    });

    // Nino : « le mode dessin doit donner un curseur pour gérer l'épaisseur
    // des prochains traits. »
    testWidgets('un curseur d épaisseur', (tester) async {
      await ouvrir(tester);
      expect(find.byType(Slider), findsOneWidget);
    });

    // Nino : « le fond du mode modification doit être noir […] ajoute aussi
    // un cadre blanc autour de l'image en modification. »
    testWidgets('fond noir et cadre blanc', (tester) async {
      await ouvrir(tester);

      final page = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(page.backgroundColor, Colors.black);

      final cadres = tester.widgetList<Container>(find.byType(Container));
      expect(
        cadres.any((c) {
          final d = c.decoration;
          return d is BoxDecoration &&
              d.border?.top.color == Colors.white &&
              d.color == null;
        }),
        isTrue,
        reason: 'l image doit être bordée de blanc',
      );
    });
  });

  group('Le doigt', () {
    testWidgets('il dessine, et la gomme ne reprend que ça', (tester) async {
      await ouvrir(tester);
      final centre = tester.getCenter(surface);

      // UN TRAIT.
      await tester.dragFrom(centre, const Offset(0, 40));
      await tester.pump();
      expect(traits(tester).length, 1);

      // UN TEXTE, qui ne doit pas s'effacer à la gomme.
      await tester.tap(find.byTooltip('Texte'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Polly');
      await tester.tap(find.text('Poser'));
      await tester.pumpAndSettle();
      expect(find.text('Polly'), findsOneWidget);

      // LA GOMME, sur le trait.
      await tester.tap(find.byTooltip('Gomme'));
      await tester.pump();
      await tester.dragFrom(centre, const Offset(0, 40));
      await tester.pump();

      expect(traits(tester), isEmpty, reason: 'le trait est repris');
      expect(
        find.text('Polly'),
        findsOneWidget,
        reason: 'la gomme ne marche que sur ce qui est dessiné',
      );
    });

    testWidgets('« défaire » reprend la dernière pose, dans l ordre', (
      tester,
    ) async {
      await ouvrir(tester);
      final centre = tester.getCenter(surface);

      await tester.tap(find.byTooltip('Tampon'));
      await tester.pump();
      expect(find.byType(TamponPartie), findsOneWidget);

      await tester.dragFrom(centre, const Offset(0, 40));
      await tester.pump();
      expect(traits(tester).length, 1);

      // Le trait est venu APRÈS le tampon : c'est lui qui s'en va d'abord.
      await tester.tap(find.byTooltip('Défaire'));
      await tester.pump();
      expect(traits(tester), isEmpty);
      expect(find.byType(TamponPartie), findsOneWidget);

      await tester.tap(find.byTooltip('Défaire'));
      await tester.pump();
      expect(find.byType(TamponPartie), findsNothing);
    });
  });

  group('La palette', () {
    test('trente couleurs, toutes différentes', () {
      expect(kPaletteComplete.length, 30);
      expect(
        kPaletteComplete.map((c) => c.toARGB32()).toSet().length,
        30,
        reason: 'deux pastilles identiques seraient un piège pour le doigt',
      );
    });

    testWidgets('elle rend la couleur touchée', (tester) async {
      Color? rendue;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    rendue = await choisirUneCouleur(
                      context,
                      actuelle: Colors.white,
                    );
                  },
                  child: const Text('ouvrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      // La première pastille, en haut à gauche de la grille.
      await tester.tap(
        find
            .descendant(
              of: find.byKey(cleDesCarreaux),
              matching: find.byType(Container),
            )
            .first,
      );
      await tester.pumpAndSettle();

      expect(rendue, isNotNull);
    });
  });

  group('Les nuances', () {
    // Nino : « la palette doit pouvoir passer de carreaux à nuance avec un
    // bouton. »
    testWidgets('une touche passe des carreaux au dégradé, et revient', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => unawaited(
                    choisirUneCouleur(context, actuelle: Colors.white),
                  ),
                  child: const Text('ouvrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      expect(find.byKey(cleDesCarreaux), findsOneWidget);
      expect(find.byType(Nuancier), findsNothing);

      await tester.tap(find.text('Nuances'));
      await tester.pumpAndSettle();
      expect(find.byType(Nuancier), findsOneWidget);
      expect(find.byKey(cleDesCarreaux), findsNothing);
      expect(find.text('Choisir'), findsOneWidget);

      await tester.tap(find.text('Carreaux'));
      await tester.pumpAndSettle();
      expect(find.byKey(cleDesCarreaux), findsOneWidget);
      expect(find.byType(Nuancier), findsNothing);
    });

    // Nino : « le truc de nuances doit faire la même taille que celui de
    // carreaux, comme ça il sera plus simple d'utilisation. »
    testWidgets('le dégradé occupe la boîte des carreaux', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => unawaited(
                    choisirUneCouleur(context, actuelle: Colors.white),
                  ),
                  child: const Text('ouvrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      final carreaux = tester.getSize(find.byKey(cleDesCarreaux));

      await tester.tap(find.text('Nuances'));
      await tester.pumpAndSettle();
      final nuances = tester.getSize(find.byKey(cleDuNuancier));

      expect(nuances.width, moreOrLessEquals(carreaux.width, epsilon: 0.5));
      expect(nuances.height, moreOrLessEquals(carreaux.height, epsilon: 0.5));
    });

    // Nino : « range-les de façon logique et rajoute en bas une ligne dans
    // laquelle il y a les couleurs du thème de l'utilisateur. »
    test('rangée par colonnes de teinte, du pâle au sombre', () {
      expect(kRangeesDeLaPalette.length, 5, reason: '4 degrés, puis les gris');
      for (final rangee in kRangeesDeLaPalette) {
        expect(rangee.length, kPastillesParRangee);
      }
      // Une colonne garde sa teinte du haut en bas.
      for (var colonne = 0; colonne < kPastillesParRangee; colonne++) {
        final teintes = {
          for (var ligne = 0; ligne < kDegresDeLaPalette.length; ligne++)
            HSVColor.fromColor(kRangeesDeLaPalette[ligne][colonne]).hue.round(),
        };
        expect(
          teintes.length,
          1,
          reason: 'la colonne $colonne doit tenir une seule teinte',
        );
      }
      // Et elle s\'assombrit en descendant.
      for (var colonne = 0; colonne < kPastillesParRangee; colonne++) {
        final clartes = [
          for (var ligne = 1; ligne < kDegresDeLaPalette.length; ligne++)
            kRangeesDeLaPalette[ligne][colonne].computeLuminance(),
        ];
        for (var i = 1; i < clartes.length; i++) {
          expect(clartes[i], lessThan(clartes[i - 1]));
        }
      }
    });

    test('la dernière rangée est celle du thème', () {
      final theme = paletteOf('foret');
      final rangee = rangeeDuTheme(theme);
      expect(rangee.length, kPastillesParRangee);
      expect(rangee, contains(theme.clair));
      expect(rangee, contains(theme.fonce));
    });

    testWidgets('elle paraît, nommée, sous les gris', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => unawaited(
                    choisirUneCouleur(context, actuelle: Colors.white),
                  ),
                  child: const Text('ouvrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      expect(find.text('Mon thème'), findsOneWidget);
      Offset ouEst(Color c) => tester.getCenter(
        find.byWidgetPredicate(
          (w) => w is Container && (w.decoration as BoxDecoration?)?.color == c,
        ),
      );
      expect(
        ouEst(paletteOf('foret').fonce).dy,
        greaterThan(ouEst(Colors.black).dy),
        reason: 'la rangée du thème est sous les gris',
      );
    });

    // Nino a montré le sélecteur qu'il voulait : « pour la nuance, recrée ça
    // plutôt. » Un carré par teinte, et la teinte à part.
    test('le carré : la saturation en largeur, la lumière en hauteur', () {
      // À droite, en haut : la teinte pure.
      expect(
        Nuancier.couleurEn(0, const Offset(1, 0)).toColor().toARGB32(),
        const Color(0xFFFF0000).toARGB32(),
      );
      // À gauche, en haut : le blanc.
      expect(
        Nuancier.couleurEn(200, const Offset(0, 0)).toColor().toARGB32(),
        Colors.white.toARGB32(),
      );
      // Tout en bas : le noir, quelle que soit la teinte.
      expect(
        Nuancier.couleurEn(120, const Offset(0.7, 1)).toColor().toARGB32(),
        Colors.black.toARGB32(),
      );
    });

    test('et la cible retrouve sa place', () {
      for (final c in [
        const Color(0xFFFF0000),
        const Color(0xFF00A0FF),
        Colors.white,
        Colors.black,
      ]) {
        final hsv = HSVColor.fromColor(c);
        final place = Nuancier.placeDe(hsv);
        expect(
          Nuancier.couleurEn(hsv.hue, place).toColor().toARGB32(),
          c.toARGB32(),
          reason: 'la couleur en main doit retomber sur elle-même',
        );
      }
    });

    test('le code hexadécimal se lit et s écrit', () {
      expect(codeHexa(const Color(0xFF106D1F)), '#106D1F');
      expect(couleurDuCode('#106D1F')?.toARGB32(), 0xFF106D1F);
      // Sans dièse, en minuscules : c'est ce qu'on recopie d'ailleurs.
      expect(couleurDuCode('106d1f')?.toARGB32(), 0xFF106D1F);
      // Incomplet ou faux : on ne touche à rien.
      expect(couleurDuCode('#106D1'), isNull);
      expect(couleurDuCode('pas une couleur'), isNull);
    });
  });

  group('La gomme', () {
    TraitDessine trait(List<Offset> points) {
      final t = TraitDessine(Colors.red, 0.01);
      t.points.addAll(points);
      return t;
    }

    // Nino : « elle doit fonctionner comme une gomme — là elle supprime la
    // totalité d'un trait qu'elle touche — c'est-à-dire effacer uniquement
    // là où elle passe. »
    test('gommé par le milieu, un trait en fait deux', () {
      final t = trait([for (var i = 0; i <= 10; i++) Offset(i / 10, 0.5)]);

      final restes = t.moins(const Offset(0.5, 0.5), 0.12);

      expect(restes.length, 2, reason: 'le trou laisse deux morceaux');
      expect(restes.first.points.every((p) => p.dx < 0.4), isTrue);
      expect(restes.last.points.every((p) => p.dx > 0.6), isTrue);
      // Et ce qui reste garde la couleur et l'épaisseur d'origine.
      expect(restes.first.couleur, t.couleur);
      expect(restes.first.epaisseur, t.epaisseur);
    });

    test('gommé au bout, il raccourcit', () {
      final t = trait([for (var i = 0; i <= 10; i++) Offset(i / 10, 0.5)]);
      final restes = t.moins(const Offset(0, 0.5), 0.25);
      expect(restes.length, 1);
      expect(restes.single.points.first.dx, greaterThan(0.25));
    });

    test('gommé en entier, il ne reste rien', () {
      final t = trait([const Offset(0.5, 0.5), const Offset(0.52, 0.5)]);
      expect(t.moins(const Offset(0.5, 0.5), 0.2), isEmpty);
    });

    test('et ce qu elle ne touche pas ne bouge pas', () {
      final t = trait([const Offset(0.1, 0.1), const Offset(0.2, 0.1)]);
      expect(t.toucheA(const Offset(0.9, 0.9), 0.05), isFalse);
      expect(t.moins(const Offset(0.9, 0.9), 0.05).single.points.length, 2);
    });
  });

  group('Le cadre de sélection', () {
    /// L'angle sous lequel le tampon est dessiné.
    ///
    /// On vise la transformation qui ENTOURE le tampon : la première de
    /// l'écran est celle du zoom, et elle ne tourne jamais.
    double penche(WidgetTester tester) {
      final t = tester.widget<Transform>(
        find
            .ancestor(
              of: find.byType(TamponPartie),
              matching: find.byType(Transform),
            )
            .first,
      );
      return t.transform.storage[1];
    }

    // Nino : « il doit y avoir une poignée de rotation juste après l'angle
    // haut/droite des cadres de sélection. »
    testWidgets('la poignée de rotation tourne l objet', (tester) async {
      await ouvrir(tester);
      await tester.tap(find.byTooltip('Tampon'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.rotate_right), findsOneWidget);
      final avant = penche(tester);

      await tester.drag(find.byIcon(Icons.rotate_right), const Offset(0, 60));
      await tester.pump();

      expect(
        penche(tester),
        isNot(avant),
        reason: 'la poignée doit faire pivoter le cadre',
      );
    });

    // Nino : « le bouton d'inversion noir/blanc ne doit pas être dans le
    // bandeau d'outils, il doit apparaître à droite du cadre lorsque le
    // tampon est sélectionné. »
    testWidgets('la touche des ronds suit la sélection, pas la barre', (
      tester,
    ) async {
      await ouvrir(tester);
      expect(find.byTooltip('Inverser les ronds'), findsNothing);

      await tester.tap(find.byTooltip('Tampon'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Inverser les ronds'), findsOneWidget);

      // Elle est à DROITE du cadre, pas dans le bandeau du bas.
      final touche = tester.getCenter(find.byTooltip('Inverser les ronds'));
      final cadre = tester.getRect(find.byType(TamponPartie));
      expect(touche.dx, greaterThan(cadre.right));
      expect(touche.dy, lessThan(tester.getRect(surface).bottom));

      // Désélectionné, elle s'en va.
      final boite = tester.getRect(surface);
      await tester.tapAt(Offset(boite.left + 4, boite.top + 4));
      await tester.pump();
      expect(find.byTooltip('Inverser les ronds'), findsNothing);
    });
  });

  double zoomActuel(WidgetTester tester) =>
      tester.widget<Transform>(find.byKey(cleDuZoom)).transform.storage[0];

  /// Deux doigts qui s'écartent (ou se rapprochent) sur la surface.
  ///
  /// [depart] est l'écart initial entre les doigts : pour un pincement
  /// vers l'intérieur il doit être assez grand pour qu'ils ne se croisent
  /// pas — deux doigts qui se croisent s'écartent de nouveau, et le test
  /// mesurerait l'inverse de ce qu'il croit.
  Future<void> pince(
    WidgetTester tester,
    double ecart, {
    double depart = 20,
  }) async {
    final centre = tester.getCenter(surface);
    final g1 = await tester.startGesture(centre - Offset(depart, 0));
    final g2 = await tester.startGesture(centre + Offset(depart, 0));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await g1.moveBy(Offset(-ecart / 6, 0));
      await g2.moveBy(Offset(ecart / 6, 0));
      await tester.pump();
    }
    await g1.up();
    await g2.up();
    await tester.pump();
  }

  group('Le zoom', () {
    // Nino : « lorsqu'on fait cette action alors que rien n'est sélectionné,
    // ça doit zoomer/dézoomer l'image. »
    testWidgets('deux doigts grossissent l image', (tester) async {
      await ouvrir(tester);
      expect(zoomActuel(tester), 1);

      await pince(tester, 200);
      expect(zoomActuel(tester), greaterThan(1));
    });

    // Nino : « on ne doit pas pouvoir dézoomer lorsque l'image est déjà
    // entière. »
    testWidgets('et on ne descend jamais sous l image entière', (tester) async {
      await ouvrir(tester);
      await pince(tester, -80, depart: 100);
      expect(zoomActuel(tester), 1);
    });

    // Nino : « elle doit pouvoir se zoomer jusqu'à 4 fois mais lentement
    // pour la précision. »
    testWidgets('jusqu à quatre fois, pas plus', (tester) async {
      await ouvrir(tester);
      for (var i = 0; i < 12; i++) {
        await pince(tester, 400);
      }
      expect(zoomActuel(tester), kZoomMax);
    });
  });

  group('Les prises du cadre', () {
    /// La hauteur des lettres du tampon : c'est elle que le pincement
    /// change.
    double tailleDuTampon(WidgetTester tester) =>
        tester.widget<TamponPartie>(find.byType(TamponPartie)).taille;

    Future<void> poseUnTampon(WidgetTester tester) async {
      await ouvrir(tester);
      await tester.tap(find.byTooltip('Tampon'));
      await tester.pumpAndSettle();
    }

    // Nino : « l'action de pincée à deux doigts doit agir sur l'objet
    // sélectionné même si on le fait ailleurs sur l'écran. Il ne doit faire
    // zoomer l'image uniquement si aucun objet n'est sélectionné. »
    testWidgets('deux doigts loin de l objet le grandissent quand même', (
      tester,
    ) async {
      await poseUnTampon(tester);
      final avant = tailleDuTampon(tester);
      final zoomAvant = zoomActuel(tester);

      // Le centre de la surface : le tampon, lui, est posé tout en bas.
      await pince(tester, 200);

      expect(tailleDuTampon(tester), greaterThan(avant));
      expect(
        zoomActuel(tester),
        zoomAvant,
        reason: 'l image ne doit pas bouger tant qu un objet est choisi',
      );
    });

    testWidgets('sans rien de choisi, les deux doigts reviennent à l image', (
      tester,
    ) async {
      await poseUnTampon(tester);
      final taille = tailleDuTampon(tester);

      // Un appui dans un coin range le cadre.
      final boite = tester.getRect(surface);
      await tester.tapAt(Offset(boite.left + 4, boite.top + 4));
      await tester.pump();

      await pince(tester, 200);
      expect(zoomActuel(tester), greaterThan(1));
      expect(tailleDuTampon(tester), taille, reason: 'l objet n a pas bougé');
    });

    // Nino : « la poignée de rotation doit finalement aller à l'angle du
    // bas. Comme ça à l'angle du haut tu mets une croix. »
    testWidgets('la croix est en haut, la rotation en bas, du même côté', (
      tester,
    ) async {
      await poseUnTampon(tester);
      final croix = tester.getCenter(find.byIcon(Icons.close));
      final rotation = tester.getCenter(find.byIcon(Icons.rotate_right));

      expect(
        rotation.dy,
        greaterThan(croix.dy),
        reason: 'la rotation est sous la croix',
      );
      expect(
        (rotation.dx - croix.dx).abs(),
        lessThan(1),
        reason: 'les deux sont du même côté',
      );
    });

    // Nino : « une croix qui supprime l'objet sélectionné. »
    testWidgets('la croix jette l objet choisi', (tester) async {
      await poseUnTampon(tester);
      expect(find.byType(TamponPartie), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(find.byType(TamponPartie), findsNothing);
    });

    testWidgets('mais un doigt qui glisse depuis la croix ne jette rien', (
      tester,
    ) async {
      // Un coin se touche par mégarde, et ce qu'on jette ne se récupère pas.
      await poseUnTampon(tester);
      await tester.drag(find.byIcon(Icons.close), const Offset(50, 50));
      await tester.pump();
      expect(find.byType(TamponPartie), findsOneWidget);
    });

    // Nino : « la rotation doit avoir des "aimants" tous les 45 degrés (par
    // exemple quand on est à 85 degrés ça nous fixe tout seul à 90 en
    // faisant apparaître une ligne droite le long de l'écran). »
    testWidgets('la rotation s aimante tous les 45 degrés', (tester) async {
      /// La transformation qui porte le tampon : celle de sa rotation.
      Finder laRotation() => find
          .ancestor(
            of: find.byType(TamponPartie),
            matching: find.byType(Transform),
          )
          .first;

      double angle(WidgetTester t) {
        final m = t.widget<Transform>(laRotation()).transform.storage;
        return math.atan2(m[1], m[0]);
      }

      Finder laLigne() => find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is PeintreDAimant,
      );

      await poseUnTampon(tester);
      final centre = tester.getCenter(laRotation());
      final poignee = tester.getCenter(find.byIcon(Icons.rotate_right));
      final bras = poignee - centre;
      final depart = bras.direction;
      final rayon = bras.distance;

      /// Pose le doigt à [vise] radians de sa position de départ, vu du
      /// centre de l'objet.
      Future<void> tourneDe(TestGesture g, double vise) async {
        final d = depart + vise;
        await g.moveTo(centre + Offset(math.cos(d), math.sin(d)) * rayon);
        await tester.pump();
      }

      final doigt = await tester.startGesture(poignee);
      await tester.pump();

      // LOIN D'UN CRAN : l'angle est celui du doigt, et rien ne s'affiche.
      await tourneDe(doigt, 20 * math.pi / 180);
      expect(
        angle(tester),
        moreOrLessEquals(20 * math.pi / 180, epsilon: 0.01),
        reason: 'à vingt degrés, l aimant ne doit pas tirer',
      );
      expect(laLigne(), findsNothing);

      // PRÈS D'UN CRAN : on s'y colle, et la ligne le dit.
      await tourneDe(doigt, 43 * math.pi / 180);
      expect(
        angle(tester),
        moreOrLessEquals(math.pi / 4, epsilon: 0.001),
        reason: 'quarante-trois degrés doivent tomber sur quarante-cinq',
      );
      expect(laLigne(), findsOneWidget);

      // ET LA LIGNE S'EN VA AVEC LE DOIGT.
      await doigt.up();
      await tester.pump();
      expect(angle(tester), moreOrLessEquals(math.pi / 4, epsilon: 0.001));
      expect(laLigne(), findsNothing);
    });
  });

  group('Le tampon choisi montre ce qui se corrige', () {
    /// Les cadres de champ : les boîtes arrondies et cernées qui entourent
    /// la date et les deux noms.
    int champs(WidgetTester tester) => tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(TamponPartie),
            matching: find.byType(Container),
          ),
        )
        .where((c) {
          final d = c.decoration;
          return d is BoxDecoration &&
              d.border != null &&
              d.borderRadius != null;
        })
        .length;

    // Nino : « lorsqu'un tampon est sélectionné, les données modifiables
    // doivent apparaître dans des genres de barre de recherche pour qu'on
    // comprenne que c'est modifiable. »
    testWidgets('trois champs quand il est choisi, aucun sinon', (
      tester,
    ) async {
      await ouvrir(tester);
      await tester.tap(find.byTooltip('Tampon'));
      await tester.pumpAndSettle();

      expect(
        champs(tester),
        3,
        reason: 'la date et les deux noms, chacun dans son champ',
      );

      // Rangé, le tampon redevient ce qu'il sera sur l'image envoyée.
      final boite = tester.getRect(surface);
      await tester.tapAt(Offset(boite.left + 4, boite.top + 4));
      await tester.pump();

      expect(champs(tester), 0);
    });

    // Nino : « les points noirs et blancs ne doivent pas être inclus. » Le
    // champ dit « ceci se corrige » ; le rond, lui, s'échange ailleurs.
    testWidgets('le rond du camp reste hors du champ', (tester) async {
      await ouvrir(tester);
      await tester.tap(find.byTooltip('Tampon'));
      await tester.pumpAndSettle();

      final encadres = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(TamponPartie),
              matching: find.byType(Container),
            ),
          )
          .where((c) {
            final d = c.decoration;
            return d is BoxDecoration &&
                d.border != null &&
                d.borderRadius != null;
          });
      expect(encadres, hasLength(3));
      for (final champ in encadres) {
        expect(
          champ.child,
          isA<Text>(),
          reason: 'un champ ne contient que son mot',
        );
      }
    });
  });

  group("L'objet posé", () {
    testWidgets('un texte arrive sélectionné, dans son cadre bleu', (
      tester,
    ) async {
      await ouvrir(tester);
      await tester.tap(find.byTooltip('Texte'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Polly');
      await tester.tap(find.text('Poser'));
      await tester.pumpAndSettle();

      final cadres = tester.widgetList<Container>(find.byType(Container));
      expect(
        cadres.any((c) {
          final d = c.decoration;
          return d is BoxDecoration && d.border?.top.color == kBleuSelection;
        }),
        isTrue,
        reason: 'il doit apparaître dans un cadre bleu',
      );
    });

    testWidgets('un appui à côté range le cadre', (tester) async {
      await ouvrir(tester);
      await tester.tap(find.byTooltip('Tampon'));
      await tester.pumpAndSettle();

      bool cadreBleu() =>
          tester.widgetList<Container>(find.byType(Container)).any((c) {
            final d = c.decoration;
            return d is BoxDecoration && d.border?.top.color == kBleuSelection;
          });

      expect(cadreBleu(), isTrue);

      // Un appui dans un coin de l'image, loin du tampon.
      final boite = tester.getRect(surface);
      await tester.tapAt(Offset(boite.left + 4, boite.top + 4));
      await tester.pump();

      expect(cadreBleu(), isFalse);
    });
  });
}
