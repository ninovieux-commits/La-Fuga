/// Le mode pré-coup, à l'écran.
///
/// Nino : « il faut une nouvelle touche à côté de <>. On ne peut y accéder que
/// lorsque c'est à l'adversaire de jouer, on choisit le coup de l'adversaire
/// puis le nôtre […] et l'adversaire voit un popup "(pseudo) avait prejoué son
/// coup, c'est encore à vous. [Ok] [menu]". »
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/game/premove.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/corr_game_screen.dart';
import 'package:lafuga/ui/screens/premove_screen.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:lafuga/ui/widgets/bandeau_prises.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:lafuga/ui/widgets/game_top_bar.dart';
import 'package:lafuga/ui/widgets/move_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Ce que le faux serveur a reçu, route par route.
  late List<({String path, Map<String, dynamic> body})> envoyes;
  late OnlineClient client;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    clearReplayCache();
    setScaleSize(const Size(400, 800));
    envoyes = [];
    client = OnlineClient(
      api: ApiClient(
        client: MockClient((r) async {
          envoyes.add((
            path: r.url.path,
            body: Map<String, dynamic>.from(
              jsonDecode(r.body) as Map<String, dynamic>,
            ),
          ));
          return http.Response(
            jsonEncode({'ok': true, 'games': const []}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
  });

  CorrGame partie({
    required bool monTour,
    String moves = 'Fa3-Sol4',
    Map<String, dynamic>? premove,
    bool premoveAdverse = false,
  }) => CorrGame.fromJson({
    'id': 'g1',
    'statut': 'en_cours',
    'adversaire': 'celia',
    'ma_couleur': 'Noir',
    'turn': monTour ? 'Noir' : 'Blanc',
    'my_turn': monTour,
    'moves_text': moves,
    'objectif': 'partie',
    if (premove != null) 'premove': premove,
    if (premoveAdverse) 'premove_adverse': true,
    if (premoveAdverse) 'premove_par': 'celia',
  });

  Future<void> ouvrir(WidgetTester tester, CorrGame g) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CorrGameScreen(
          game: g,
          service: CorrespondenceService(client),
          myPseudo: 'nino',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('La boule, dans le bandeau du haut', () {
    GameTopBar barre(WidgetTester tester) =>
        tester.widget<GameTopBar>(find.byType(GameTopBar));

    /// La boule de cristal, qui réunit « Analyser » et « Pré-coups ».
    final Finder laBoule = find.byTooltip('Analyser ou préparer ses coups ?');

    Future<void> ouvrirLaBoule(WidgetTester tester) async {
      await tester.tap(laBoule);
      await tester.pumpAndSettle();
    }

    FugaButton touche(WidgetTester tester, String texte) =>
        tester.widget<FugaButton>(find.widgetWithText(FugaButton, texte));

    testWidgets(
      'elle ouvre les pré-coups quand c est à l adversaire de jouer',
      (tester) async {
        await ouvrir(tester, partie(monTour: false));
        expect(barre(tester).onPremove, isNotNull);
        await ouvrirLaBoule(tester);
        expect(touche(tester, 'Pré-coups').onPressed, isNotNull);
      },
    );

    testWidgets('et pâlit la touche quand c est à nous, en disant pourquoi', (
      tester,
    ) async {
      await ouvrir(tester, partie(monTour: true, moves: 'Fa3-Sol4\nFa6-Sol5'));
      expect(
        barre(tester).onPremove,
        isNull,
        reason: 'préjouer quand on a le trait ne prépare rien',
      );
      await ouvrirLaBoule(tester);
      expect(
        touche(tester, 'Pré-coups').onPressed,
        isNull,
        reason: 'la touche est là, mais éteinte',
      );
      expect(
        find.textContaining('les pré-coups attendent'),
        findsOneWidget,
        reason: 'une touche pâle sans raison écrite laisse chercher',
      );
    });

    testWidgets('la boule ne bouge pas d un tour à l autre', (tester) async {
      // Nino : « quand le bouton pré-coups disparaît car c'est mon tour de
      // jouer, les autres boutons se décalent vers la gauche. Chaque bouton
      // sur les écrans de jeux, analyse ect doivent être fixés, ne jamais
      // changer de place. » La boule est là dans les deux cas : c'est à
      // l'intérieur du popup que « Pré-coups » pâlit.
      await ouvrir(tester, partie(monTour: false));
      final attend = tester.getRect(laBoule);
      await ouvrir(tester, partie(monTour: true, moves: 'Fa3-Sol4\nFa6-Sol5'));
      expect(
        tester.getRect(laBoule),
        attend,
        reason: 'la boule a changé de place en passant à notre tour',
      );
    });

    testWidgets('rien ne s installe au centre du bandeau', (tester) async {
      // L'appareil photo selfie est percé là, et passe devant tout ce qu'on y
      // pose. Nino : « il faudrait éviter qu'il y ait de bouton au centre de
      // ce bandeau. »
      await ouvrir(tester, partie(monTour: false));
      final bandeau = tester.getRect(find.byType(GameTopBar));
      final trou = Rect.fromCenter(
        center: bandeau.center,
        width: S(kTrouCamera),
        height: bandeau.height,
      );
      for (final cible
          in find
              .descendant(
                of: find.byType(GameTopBar),
                matching: find.byType(InkWell),
              )
              .evaluate()) {
        final r = tester.getRect(find.byWidget(cible.widget));
        expect(
          r.overlaps(trou),
          isFalse,
          reason: 'une touche empiète sur le trou de l appareil photo',
        );
      }
    });

    testWidgets('le bandeau des coups n a plus à la porter', (tester) async {
      await ouvrir(tester, partie(monTour: false));
      expect(
        find.descendant(
          of: find.byType(MoveStrip),
          matching: find.text('Pré-coups'),
        ),
        findsNothing,
      );
    });
  });

  group('Ce qu on vient d armer ne se perd pas', () {
    testWidgets('rouvrir la touche retrouve les variantes', (tester) async {
      // Armer un plan ne change NI les coups NI le statut : la partie n est
      // donc pas relue, et `game.premove` reste celui d avant. Sans le plan
      // gardé sur place, l écran de composition repartait vide.
      await ouvrir(tester, partie(monTour: false));
      tester.widget<GameTopBar>(find.byType(GameTopBar)).onPremove!();
      await tester.pumpAndSettle();

      final vue = tester.widget<GameBoardView>(find.byType(GameBoardView));
      vue.onTapCell(const Cell(2, 1));
      await tester.pump();
      vue.onTapCell(const Cell(2, 2));
      await tester.pump();
      vue.onTapCell(const Cell(2, 2));
      await tester.pumpAndSettle();
      vue.onTapCell(const Cell(0, 6));
      await tester.pump();
      vue.onTapCell(const Cell(0, 5));
      await tester.pump();
      vue.onTapCell(const Cell(0, 5));
      await tester.pumpAndSettle();

      Future<void> appuyer(Finder f) async {
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      await appuyer(find.widgetWithText(FugaButton, 'Garder la variante'));
      await appuyer(find.widgetWithText(FugaButton, 'Armer'));
      expect(find.byType(PremoveScreen), findsNothing);

      // On rouvre, sans que le serveur ait eu l occasion de nous relire.
      tester.widget<GameTopBar>(find.byType(GameTopBar)).onPremove!();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('1 / 6'),
        findsOneWidget,
        reason: 'la variante armée a disparu en rouvrant la touche',
      );
    });
  });

  group('Composer une variante', () {
    /// L'écran de composition, sur la position d'après un coup blanc.
    Future<void> composer(WidgetTester tester, {PremovePlan? plan}) async {
      final board = Board.initial();
      await tester.pumpWidget(
        MaterialApp(
          home: PremoveScreen(
            game: partie(monTour: false, premove: plan?.toJson()),
            service: CorrespondenceService(client),
            board: board,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('le matériel mangé borde le plateau', (tester) async {
      // Nino : « dans tous les modes comprenant un plateau de jeu et des
      // pièces pouvant être mangées ». On prépare un coup au milieu d'une
      // partie : ce qui a déjà été pris en fait partie.
      await composer(tester);
      final bande = tester.widget<BandeauPrises>(find.byType(BandeauPrises));
      expect(
        bande.prisesHaut,
        isNot(same(bande.prisesBas)),
        reason: 'une ligne par camp, l une sur l autre au-dessus du plateau',
      );
    });

    /// Joue un coup au doigt : prendre, poser, revalider.
    Future<void> jouer(WidgetTester tester, Cell de, Cell vers) async {
      final vue = tester.widget<GameBoardView>(find.byType(GameBoardView));
      vue.onTapCell(de);
      await tester.pump();
      vue.onTapCell(vers);
      await tester.pump();
      vue.onTapCell(vers);
      await tester.pumpAndSettle();
    }

    Finder touche(String texte) => find.widgetWithText(FugaButton, texte);

    /// Appuie sur une touche en la ramenant d'abord à l'écran : la page défile,
    /// et un appui sur un bouton hors cadre ne touche rien du tout.
    Future<void> appuyer(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    testWidgets('on commence par SON coup, et « Garder » attend le nôtre', (
      tester,
    ) async {
      await composer(tester);
      expect(
        find.textContaining('Le coup de'),
        findsOneWidget,
        reason: 'c est son coup qu on entre d abord',
      );
      expect(
        tester.widget<FugaButton>(touche('Garder la variante')).onPressed,
        isNull,
        reason: 'une variante sans réponse ne prépare rien',
      );

      // Les Blancs ont le trait : c'est le coup de l'adversaire.
      await jouer(tester, const Cell(2, 1), const Cell(2, 2));
      expect(find.text('Votre réponse'), findsOneWidget);
      expect(
        tester.widget<FugaButton>(touche('Garder la variante')).onPressed,
        isNull,
        reason: 'il manque encore NOTRE coup',
      );

      await jouer(tester, const Cell(0, 6), const Cell(0, 5));
      expect(
        tester.widget<FugaButton>(touche('Garder la variante')).onPressed,
        isNotNull,
      );
    });

    testWidgets('« Défaire » retire un demi-coup, pas deux', (tester) async {
      await composer(tester);
      await jouer(tester, const Cell(2, 1), const Cell(2, 2));
      await jouer(tester, const Cell(0, 6), const Cell(0, 5));
      expect(find.text('Mi2-Mi3'), findsOneWidget);
      expect(find.text('Do7-Do6'), findsOneWidget);

      await appuyer(tester, touche('Défaire'));
      expect(find.text('Do7-Do6'), findsNothing);
      expect(
        find.text('Mi2-Mi3'),
        findsOneWidget,
        reason: 'défaire notre coup a emporté le sien',
      );
      expect(find.text('Votre réponse'), findsOneWidget);
    });

    testWidgets('une variante gardée rejoint la liste, et le plateau repart', (
      tester,
    ) async {
      await composer(tester);
      await jouer(tester, const Cell(2, 1), const Cell(2, 2));
      await jouer(tester, const Cell(0, 6), const Cell(0, 5));
      await appuyer(tester, touche('Garder la variante'));

      expect(find.textContaining('Variantes préparées'), findsOneWidget);
      expect(find.textContaining('1 / 6'), findsOneWidget);
      expect(
        find.textContaining('Le coup de'),
        findsOneWidget,
        reason: 'le plateau doit repartir de la position de la partie',
      );
      final vue = tester.widget<GameBoardView>(find.byType(GameBoardView));
      expect(
        vue.board.positionKey(Camp.blanc),
        Board.initial().positionKey(Camp.blanc),
      );
    });

    /// Déjà préparé : si les Blancs jouent Mi2-Mi3, on répond Do7-Do6.
    PremovePlan unPlan() => const PremovePlan(
      base: 1,
    ).avec(const PremoveVariante(['Mi2-Mi3', 'Do7-Do6']))!;

    /// Compose la MÊME entrée que `unPlan`, avec une AUTRE réponse.
    Future<void> contredire(WidgetTester tester) async {
      await jouer(tester, const Cell(2, 1), const Cell(2, 2));
      await jouer(tester, const Cell(2, 6), const Cell(2, 5));
    }

    // Nino : « Ça doit nous dire immédiatement lorsque deux variantes se
    // contredisent en mode pré-coups. »
    testWidgets('la contradiction se dit IMMÉDIATEMENT, sans rien demander', (
      tester,
    ) async {
      await composer(tester, plan: unPlan());

      // Son coup : la ligne ne fait encore que suivre la variante préparée.
      await jouer(tester, const Cell(2, 1), const Cell(2, 2));
      expect(
        find.textContaining('contredit'),
        findsNothing,
        reason: 'rien ne se contredit tant qu on n a pas répondu autrement',
      );

      // Notre réponse, différente de celle qui est préparée.
      await jouer(tester, const Cell(2, 6), const Cell(2, 5));
      expect(
        find.textContaining('contredit'),
        findsOneWidget,
        reason: 'on doit le savoir avant même de garder la variante',
      );
    });

    testWidgets(
      '« Annuler » laisse tout en place, variante en cours comprise',
      (tester) async {
        await composer(tester, plan: unPlan());
        await contredire(tester);
        await appuyer(tester, touche('Garder la variante'));

        expect(
          find.text('Cette variante en contredit une déjà présente.'),
          findsOneWidget,
          reason: 'le popup de Nino, mot pour mot',
        );
        await appuyer(tester, touche('Annuler'));

        expect(find.textContaining('1 / 6'), findsOneWidget);
        expect(
          find.text('Mi7-Mi6'),
          findsOneWidget,
          reason: 'la réponse qu on venait de composer est toujours là',
        );
      },
    );

    testWidgets('« Remplacer » chasse la variante contredite', (tester) async {
      await composer(tester, plan: unPlan());
      await contredire(tester);
      await appuyer(tester, touche('Garder la variante'));
      await appuyer(tester, touche('Remplacer'));

      expect(
        find.textContaining('1 / 6'),
        findsOneWidget,
        reason: 'une remplace l autre : toujours une seule variante',
      );
      expect(
        find.text('Mi7-Mi6'),
        findsOneWidget,
        reason: 'la nouvelle réponse a pris la place',
      );
      expect(
        find.text('Do7-Do6'),
        findsNothing,
        reason: 'l ancienne réponse est partie avec sa variante',
      );
      expect(
        find.textContaining('contredit'),
        findsNothing,
        reason: 'plus rien ne se contredit',
      );
    });

    testWidgets('« Armer » envoie le plan au serveur', (tester) async {
      await composer(tester);
      await jouer(tester, const Cell(2, 1), const Cell(2, 2));
      await jouer(tester, const Cell(0, 6), const Cell(0, 5));
      await appuyer(tester, touche('Garder la variante'));
      await appuyer(tester, touche('Armer'));

      final envoi = envoyes.where((e) => e.path == '/corr_premove').toList();
      expect(envoi.length, 1, reason: 'le plan n est pas parti');
      final plan = envoi.single.body['plan'] as Map<String, dynamic>;
      expect((plan['variantes'] as List).length, 1);
      expect(((plan['variantes'] as List).first as Map)['coups'], [
        'Mi2-Mi3',
        'Do7-Do6',
      ]);
      expect(
        plan.containsKey('base'),
        isTrue,
        reason: 'le plan dit de quelle position il parle',
      );
    });

    testWidgets('sans aucune variante, on efface ce qui était préparé', (
      tester,
    ) async {
      await composer(
        tester,
        plan: const PremovePlan(
          base: 1,
        ).avec(const PremoveVariante(['Mi2-Mi3', 'Do7-Do6'])),
      );
      await appuyer(tester, find.byIcon(Icons.close));
      expect(find.textContaining('0 / 6'), findsOneWidget);

      await appuyer(tester, touche('Ne rien préjouer'));
      final envoi = envoyes.where((e) => e.path == '/corr_premove').single;
      expect(
        (envoi.body['plan'] as Map)['variantes'] as List,
        isEmpty,
        reason: 'un plan vide est ce qui annule',
      );
    });
  });

  group('Repartir sans armer prévient', () {
    // Nino : « quand on est dans les pré-coups et qu'on revient sur la partie
    // sans avoir armé, ce serait bien qu'un message nous prévienne qu'on va
    // perdre nos lignes non armées. » Garder une variante ne parle qu'à cet
    // écran : seul « Armer » la porte au serveur.

    /// L'écran de composition, posé SUR une page : c'est en la retrouvant
    /// qu'on saura qu'on est reparti.
    Future<void> composer(WidgetTester tester, {PremovePlan? plan}) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('LA PARTIE'))),
        ),
      );
      final navigateur = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigateur.push(
          MaterialPageRoute<void>(
            builder: (_) => PremoveScreen(
              game: partie(monTour: false, premove: plan?.toJson()),
              service: CorrespondenceService(client),
              board: Board.initial(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> jouer(WidgetTester tester, Cell de, Cell vers) async {
      final vue = tester.widget<GameBoardView>(find.byType(GameBoardView));
      vue.onTapCell(de);
      await tester.pump();
      vue.onTapCell(vers);
      await tester.pump();
      vue.onTapCell(vers);
      await tester.pumpAndSettle();
    }

    Future<void> appuyer(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    /// La touche « << » du bandeau, qui ramène à la partie.
    final Finder retour = find.byTooltip('Retour');

    testWidgets('une variante gardée mais pas armée retient', (tester) async {
      await composer(tester);
      await jouer(tester, const Cell(2, 1), const Cell(2, 2));
      await jouer(tester, const Cell(0, 6), const Cell(0, 5));
      await appuyer(
        tester,
        find.widgetWithText(FugaButton, 'Garder la variante'),
      );

      await appuyer(tester, retour);
      expect(find.textContaining('Repartir sans armer'), findsOneWidget);
      expect(find.textContaining('seront perdues'), findsOneWidget);

      // « Non » : on reste, et la variante est toujours là.
      await appuyer(tester, find.widgetWithText(FugaButton, 'Non'));
      expect(find.byType(PremoveScreen), findsOneWidget);
      expect(find.textContaining('1 / 6'), findsOneWidget);

      // « Oui » : on repart, et on retrouve la partie.
      await appuyer(tester, retour);
      await appuyer(tester, find.widgetWithText(FugaButton, 'Oui'));
      expect(find.byType(PremoveScreen), findsNothing);
      expect(find.text('LA PARTIE'), findsOneWidget);
    });

    testWidgets('une variante seulement COMMENCÉE retient aussi', (
      tester,
    ) async {
      // Elle n'est pas gardée, donc pas dans le plan — mais elle se perdrait
      // tout autant.
      await composer(tester);
      await jouer(tester, const Cell(2, 1), const Cell(2, 2));

      await appuyer(tester, retour);
      expect(find.textContaining('Repartir sans armer'), findsOneWidget);
    });

    testWidgets('retirer une variante déjà armée retient', (tester) async {
      await composer(
        tester,
        plan: const PremovePlan(
          base: 1,
        ).avec(const PremoveVariante(['Mi2-Mi3', 'Do7-Do6'])),
      );
      await appuyer(tester, find.byIcon(Icons.close));

      await appuyer(tester, retour);
      expect(
        find.textContaining('Repartir sans armer'),
        findsOneWidget,
        reason: 'effacer sans armer laisse le plan armé intact chez le serveur',
      );
    });

    testWidgets('et rien ne retient quand rien n a bougé', (tester) async {
      await composer(
        tester,
        plan: const PremovePlan(
          base: 1,
        ).avec(const PremoveVariante(['Mi2-Mi3', 'Do7-Do6'])),
      );
      await appuyer(tester, retour);
      expect(
        find.textContaining('Repartir sans armer'),
        findsNothing,
        reason: 'le plan est celui du serveur : il n y a rien à perdre',
      );
      expect(find.text('LA PARTIE'), findsOneWidget);
    });
  });

  group('Le popup de celui qui reçoit le pré-coup', () {
    testWidgets('il nomme l adversaire et dit que c est encore à nous', (
      tester,
    ) async {
      await ouvrir(
        tester,
        partie(
          monTour: true,
          moves: 'Fa3-Sol4\nFa6-Sol5\nSol2-Fa3',
          premoveAdverse: true,
        ),
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.textContaining('celia'),
        findsWidgets,
        reason: 'le popup doit nommer qui avait préjoué',
      );
      expect(find.textContaining('avait préjoué son coup'), findsOneWidget);
      expect(find.textContaining('encore à vous'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Ok'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Menu'), findsOneWidget);
    });

    testWidgets('[Ok] le referme et prévient le serveur, pour de bon', (
      tester,
    ) async {
      await ouvrir(
        tester,
        partie(monTour: true, moves: 'Fa3-Sol4', premoveAdverse: true),
      );
      await tester.tap(find.widgetWithText(TextButton, 'Ok'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        envoyes.where((e) => e.path == '/corr_premove_vu').length,
        1,
        reason: 'sans cela le popup reviendrait à chaque actualisation',
      );
    });

    testWidgets('pas de popup quand l adversaire n avait rien préjoué', (
      tester,
    ) async {
      await ouvrir(tester, partie(monTour: true, moves: 'Fa3-Sol4'));
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
