/// Un message reçu pendant la partie passe dans le bandeau de l'adversaire.
///
/// Nino : « quand on reçoit un message pendant qu'on est sur la partie
/// concernant l'adversaire en question, le message s'affiche dans une bulle
/// […] Le message doit rester afficher pendant 5 secondes et si un deuxième
/// message est envoyé alors que le [premier] est toujours afficher, ça défile.
/// Il ne faut pas que ça déborde sur le plateau ni sur les touches du haut.
/// L'espace que je prend sur mon dessin est l'espace maximal utilisable sur
/// l'écran de jeu. »
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/bulles_en_jeu.dart';
import 'package:lafuga/ui/widgets/game_layout.dart';
import 'package:lafuga/ui/widgets/message_bubble.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<String> flux;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
    flux = StreamController<String>.broadcast();
  });
  tearDown(() {
    flux.close();
    resetScale();
  });

  /// La bulle seule, dans une boîte de la hauteur d'un bandeau de joueur.
  ///
  /// Douze parts sur cent quatre, comme dans `GameLayout`.
  Future<void> seule(WidgetTester tester) async {
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
    await tester.pumpAndSettle();
  }

  /// La fenêtre réellement peinte : au-delà, c'est rogné.
  ///
  /// C'est la vue qui défile, et son `clipBehavior` est ce qui découpe. Un
  /// `ClipRect` posé autour tomberait au même pixel — mesuré — donc le
  /// chercher ne prouverait rien : il faut regarder le découpage lui-même.
  Rect lucarne(WidgetTester tester) {
    final vue = tester.widget<SingleChildScrollView>(
      find.descendant(
        of: find.byType(BullesEnJeu),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(
      vue.clipBehavior,
      isNot(Clip.none),
      reason: 'sans découpage, un long message sortirait du bandeau',
    );
    return tester.getRect(find.byType(SingleChildScrollView));
  }

  group('La bulle paraît, puis s efface', () {
    testWidgets('rien ne s affiche tant qu aucun message n arrive', (
      tester,
    ) async {
      await seule(tester);
      expect(find.byType(MessageBubble), findsNothing);
    });

    testWidgets('un message paraît, et tient CINQ secondes', (tester) async {
      await seule(tester);
      flux.add('Salut');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Salut'), findsOneWidget);

      // Encore là à quatre secondes et demie.
      await tester.pump(const Duration(milliseconds: 4200));
      expect(
        find.text('Salut'),
        findsOneWidget,
        reason: 'il doit rester cinq secondes pleines',
      );

      // Parti après cinq.
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      expect(find.text('Salut'), findsNothing);
    });

    testWidgets('elle a la couleur et l écriture d un message REÇU', (
      tester,
    ) async {
      await seule(tester);
      flux.add('Salut');
      await tester.pumpAndSettle();

      final bulle = tester.widget<MessageBubble>(find.byType(MessageBubble));
      expect(bulle.deMoi, isFalse, reason: 'c est un message reçu');
      expect(bulle.palette, paletteOf('original'));
      expect(
        bulle.selectionnable,
        isFalse,
        reason: 'elle s efface en cinq secondes : rien à y sélectionner',
      );
    });

    testWidgets('un message vide ne fait rien paraître', (tester) async {
      await seule(tester);
      flux.add('   ');
      await tester.pumpAndSettle();
      expect(find.byType(MessageBubble), findsNothing);
    });
  });

  group('Deux messages : ça défile', () {
    testWidgets('le second rejoint le premier, sans le chasser', (
      tester,
    ) async {
      await seule(tester);
      flux.add('Premier');
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      flux.add('Second');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Premier'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
    });

    testWidgets('chacun vit CINQ secondes depuis SON arrivée', (tester) async {
      // Le piège serait de tout effacer d'un coup : le second disparaîtrait
      // deux secondes trop tôt, parce que le premier a fini.
      await seule(tester);
      flux.add('Premier');
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      flux.add('Second');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Premier'), findsOneWidget);

      // À 5,3 s le premier s'en va ; le second est arrivé à 3 s, il reste.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('Premier'), findsNothing);
      expect(
        find.text('Second'),
        findsOneWidget,
        reason: 'le second a sa propre échéance',
      );

      // Et il part à 8,3 s, cinq secondes après SON arrivée.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('Second'), findsNothing);
    });

    testWidgets('la vue défile, et montre le DERNIER arrivé', (tester) async {
      await seule(tester);
      for (final t in ['Un', 'Deux', 'Trois', 'Quatre']) {
        flux.add(t);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.pumpAndSettle();

      final vue = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(vue.controller, isNotNull);
      expect(
        vue.controller!.position.maxScrollExtent,
        greaterThan(0),
        reason: 'quatre bulles ne tiennent pas dans un bandeau : ça défile',
      );

      final fenetre = lucarne(tester);
      final dernier = tester.getRect(find.text('Quatre'));
      expect(
        dernier.top,
        greaterThanOrEqualTo(fenetre.top - 0.5),
        reason: 'le dernier message doit être sous les yeux, en entier',
      );
      expect(dernier.bottom, lessThanOrEqualTo(fenetre.bottom + 0.5));
    });
  });

  group('Ça ne déborde pas', () {
    testWidgets('la fenêtre peinte tient dans le bandeau', (tester) async {
      // La garantie ne tient pas à la bonne volonté des messages : ce qui est
      // peint est rogné à cette fenêtre, et elle est dans le bandeau.
      await seule(tester);
      flux.add('Salut');
      await tester.pumpAndSettle();

      final boite = tester.getRect(find.byType(BullesEnJeu));
      final fenetre = lucarne(tester);
      expect(fenetre.top, greaterThanOrEqualTo(boite.top - 0.5));
      expect(
        fenetre.bottom,
        lessThanOrEqualTo(boite.bottom + 0.5),
        reason: 'rien ne doit dépasser vers le plateau',
      );
      expect(fenetre.left, greaterThanOrEqualTo(boite.left - 0.5));
      expect(fenetre.right, lessThanOrEqualTo(boite.right + 0.5));
    });

    testWidgets('un message très long s ouvre sur son DÉBUT', (tester) async {
      // Glisser jusqu'en bas de la liste ferait entrer un long message par sa
      // fin, ses premiers mots déjà sortis par le haut.
      await seule(tester);
      flux.add(
        'Un message interminable qui raconte toute la partie coup par coup '
        'et qui ne devrait jamais sortir du bandeau de l adversaire, ni vers '
        'le plateau, ni vers les touches du haut, quoi qu il arrive.',
      );
      await tester.pumpAndSettle();

      final fenetre = lucarne(tester);
      final bulle = tester.getRect(find.byType(MessageBubble));
      expect(
        bulle.top,
        greaterThanOrEqualTo(fenetre.top - 0.5),
        reason: 'le début du message doit être visible',
      );
      expect(
        bulle.height,
        greaterThan(fenetre.height),
        reason: 'ce message est plus haut que le bandeau : il faut défiler',
      );
      // Large, il reste tout de même entre les bords.
      expect(bulle.left, greaterThanOrEqualTo(fenetre.left - 0.5));
      expect(bulle.right, lessThanOrEqualTo(fenetre.right + 0.5));
    });

    testWidgets('la photo garde sa place à gauche', (tester) async {
      // Sur le dessin de Nino, la bulle commence APRÈS la photo.
      await seule(tester);
      flux.add('Salut');
      await tester.pumpAndSettle();

      final boite = tester.getRect(find.byType(BullesEnJeu));
      final bulle = tester.getRect(find.byType(MessageBubble));
      expect(
        bulle.left - boite.left,
        greaterThan(boite.height * 0.8),
        reason: 'la photo occupe un carré de la hauteur du bandeau',
      );
    });

    testWidgets('dans la mise en page, elle reste DANS le bandeau', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameLayout(
              topBar: const ColoredBox(color: Colors.amber),
              topPanel: const ColoredBox(color: Colors.blueGrey),
              topOverlay: BullesEnJeu(
                flux: flux.stream,
                palette: paletteOf('original'),
              ),
              board: const ColoredBox(color: Colors.brown),
              bottomPanel: const ColoredBox(color: Colors.blueGrey),
              moveStrip: const ColoredBox(color: Colors.grey),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      flux.add(
        'Un message interminable qui raconte toute la partie coup par coup '
        'et qui ne devrait jamais sortir du bandeau de l adversaire.',
      );
      await tester.pumpAndSettle();

      // Le bandeau du haut, et la bulle posée dedans.
      final panneau = tester.getRect(find.byType(BullesEnJeu));
      final fenetre = lucarne(tester);
      final plateau = tester.getRect(find.byType(ColoredBox).at(2));
      expect(fenetre.bottom, lessThanOrEqualTo(panneau.bottom + 0.5));
      expect(fenetre.top, greaterThanOrEqualTo(panneau.top - 0.5));
      expect(
        fenetre.bottom,
        lessThanOrEqualTo(plateau.top + 0.5),
        reason: 'ça ne doit pas déborder sur le plateau',
      );
    });
  });
}
