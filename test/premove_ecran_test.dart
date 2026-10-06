/// Le mode pré-coup, à l'écran.
///
/// Nino : « il faut une nouvelle touche à côté de <>. On ne peut y accéder que
/// lorsque c'est à l'adversaire de jouer, on choisit le coup de l'adversaire
/// puis le nôtre […] et l'adversaire voit un popup "(pseudo) avait prejoué son
/// coup, c'est encore à vous. [Ok] [menu]". »
library;

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
import 'package:lafuga/ui/widgets/game_board_view.dart';
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

  group('La touche, à côté des flèches', () {
    testWidgets('elle est là quand c est à l adversaire de jouer', (
      tester,
    ) async {
      await ouvrir(tester, partie(monTour: false));
      expect(
        tester.widget<MoveStrip>(find.byType(MoveStrip)).onPremove,
        isNotNull,
      );
    });

    testWidgets('et pas quand c est à nous : il n y a rien à attendre', (
      tester,
    ) async {
      await ouvrir(tester, partie(monTour: true, moves: 'Fa3-Sol4\nFa6-Sol5'));
      expect(
        tester.widget<MoveStrip>(find.byType(MoveStrip)).onPremove,
        isNull,
        reason: 'préjouer quand on a le trait ne prépare rien',
      );
    });

    testWidgets('elle montre le nombre de variantes armées', (tester) async {
      await ouvrir(
        tester,
        partie(
          monTour: false,
          premove: {
            'base': 1,
            'variantes': [
              {
                'coups': ['Fa6-Sol5', 'Sol2-Fa3'],
              },
              {
                'coups': ['Si7-Si6', 'Re2-Re3'],
              },
            ],
          },
        ),
      );
      expect(tester.widget<MoveStrip>(find.byType(MoveStrip)).premoveCount, 2);
      expect(
        find.descendant(of: find.byType(MoveStrip), matching: find.text('2')),
        findsOneWidget,
        reason: 'on doit voir sans l ouvrir qu une réponse attend',
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

    testWidgets('une variante qui en contredit une autre est refusée, et dit '
        'pourquoi', (tester) async {
      // Déjà armé : si les Blancs jouent Mi2-Mi3, on répond Do7-Do6.
      await composer(
        tester,
        plan: const PremovePlan(
          base: 1,
        ).avec(const PremoveVariante(['Mi2-Mi3', 'Do7-Do6'])),
      );
      // On compose la même entrée, avec une AUTRE réponse.
      await jouer(tester, const Cell(2, 1), const Cell(2, 2));
      await jouer(tester, const Cell(2, 6), const Cell(2, 5));
      await appuyer(tester, touche('Garder la variante'));

      expect(
        find.textContaining('contredit'),
        findsOneWidget,
        reason: 'rien ne doit se contredire, et il faut le dire',
      );
      expect(
        find.textContaining('1 / 6'),
        findsOneWidget,
        reason: 'la variante refusée a quand même été rangée',
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
        ((envoi.body['plan'] as Map)['variantes'] as List),
        isEmpty,
        reason: 'un plan vide est ce qui annule',
      );
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
