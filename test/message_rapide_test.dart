/// Un message écrit depuis le plateau, sans le quitter des yeux.
///
/// Nino : « j'aimerai l'ajout d'un bouton […] un bouton texte rapide avec un
/// dessin de bulle dessus. Lorsqu'on clique sur ce bouton, le clavier sort et
/// on peut écrire un message rapide sans quitter le plateau des yeux. On
/// clique sur envoyer et le message part dans la boîte de chat. Bien sûr il
/// apparaît du coup sur la partie quelques secondes comme n'importe quel
/// autre message. Il est écrit d'un autre endroit mais doit être traité de la
/// même manière. »
///
/// « Traité de la même manière » est la phrase qui compte : ces tests
/// vérifient que le message part par le MÊME envoi que la boîte de messages,
/// et qu'il paraît dans la MÊME bande que les messages reçus.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/clock.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/ui/screens/corr_game_screen.dart';
import 'package:lafuga/ui/screens/online_game_screen.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/bulles_en_jeu.dart';
import 'package:lafuga/ui/widgets/message_bubble.dart';
import 'package:lafuga/ui/widgets/message_rapide.dart';
import 'package:lafuga/ui/widgets/player_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_game_test.dart' show FakeSocket, makeGame;

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

  Future<void> montre(WidgetTester tester, Widget enfant) async {
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

  Widget panneau({VoidCallback? ecrire, VoidCallback? abandonner}) => SizedBox(
    height: 120,
    width: 393,
    child: PlayerPanel(
      name: 'nino',
      clock: '∞',
      palette: paletteOf('original'),
      isWhite: true,
      isTurn: true,
      captures: const [],
      onMessageRapide: ecrire,
      onResign: abandonner,
    ),
  );

  group('La touche à bulle', () {
    testWidgets('elle est là, sur MON bandeau', (tester) async {
      await montre(tester, panneau(ecrire: () {}));
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    });

    testWidgets('et pas sur celui de l adversaire', (tester) async {
      // On n'écrit pas à sa propre place : le bandeau d'en face ne la reçoit
      // pas, comme il ne reçoit ni le ½ ni le X.
      await montre(tester, panneau());
      expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
    });

    testWidgets('elle est À GAUCHE des autres gestes', (tester) async {
      // Nino l'a dessinée là, à gauche du ½ : la place libre de la rangée,
      // et la plus éloignée de l'abandon.
      await montre(tester, panneau(ecrire: () {}, abandonner: () {}));
      final bulle = tester.getRect(find.byIcon(Icons.chat_bubble_outline));
      expect(bulle.right, lessThan(tester.getRect(find.text('X')).left));
    });

    testWidgets('la toucher appelle le composeur', (tester) async {
      var ouvert = 0;
      await montre(tester, panneau(ecrire: () => ouvert++));
      await tester.tap(find.byIcon(Icons.chat_bubble_outline));
      await tester.pumpAndSettle();
      expect(ouvert, 1);
    });
  });

  group('Le composeur', () {
    /// Ouvre le composeur et rend ce qu'il a fini par donner.
    Future<String?> composer(
      WidgetTester tester, {
      required Future<void> Function(WidgetTester) gestes,
    }) async {
      String? rendu;
      var ferme = false;
      await montre(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              rendu = await ouvrirMessageRapide(
                context,
                palette: paletteOf('original'),
              );
              ferme = true;
            },
            child: const Text('ouvrir'),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      await gestes(tester);
      await tester.pumpAndSettle();
      expect(ferme, isTrue, reason: 'le composeur devait se refermer');
      return rendu;
    }

    testWidgets('le champ prend le clavier tout seul', (tester) async {
      // « Le clavier sort » : la touche a déjà été pressée, en demander une
      // seconde pour écrire serait une de trop.
      await montre(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                ouvrirMessageRapide(context, palette: paletteOf('original')),
            child: const Text('ouvrir'),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      final champ = tester.widget<TextField>(find.byType(TextField));
      expect(champ.autofocus, isTrue);
      expect(
        champ.textInputAction,
        TextInputAction.send,
        reason: 'la touche du clavier doit envoyer, pas sauter une ligne',
      );
    });

    testWidgets('« Envoyer » rend le texte écrit', (tester) async {
      final rendu = await composer(
        tester,
        gestes: (t) async {
          await t.enterText(find.byType(TextField), 'bien joué');
          await t.tap(find.text(T('Envoyer')));
        },
      );
      expect(rendu, 'bien joué');
    });

    testWidgets('la touche d envoi du CLAVIER fait la même chose', (
      tester,
    ) async {
      final rendu = await composer(
        tester,
        gestes: (t) async {
          await t.enterText(find.byType(TextField), 'bien joué');
          await t.testTextInput.receiveAction(TextInputAction.send);
        },
      );
      expect(rendu, 'bien joué');
    });

    testWidgets('le texte est élagué', (tester) async {
      final rendu = await composer(
        tester,
        gestes: (t) async {
          await t.enterText(find.byType(TextField), '   bien joué   ');
          await t.tap(find.text(T('Envoyer')));
        },
      );
      expect(rendu, 'bien joué');
    });

    testWidgets('un champ vide ne ferme même pas la feuille', (tester) async {
      // Le doigt a glissé : on ne renvoie pas l'utilisateur au plateau pour
      // rien, et on n'envoie surtout pas un message vide.
      await montre(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                ouvrirMessageRapide(context, palette: paletteOf('original')),
            child: const Text('ouvrir'),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text(T('Envoyer')));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('Et il paraît sur la partie', () {
    late StreamController<String> recus;
    late StreamController<String> miens;

    setUp(() {
      recus = StreamController<String>.broadcast();
      miens = StreamController<String>.broadcast();
    });
    tearDown(() {
      recus.close();
      miens.close();
    });

    Future<void> bande(WidgetTester tester) => montre(
      tester,
      SizedBox(
        width: 393,
        height: 851 * 12 / 104,
        child: BullesEnJeu(
          flux: recus.stream,
          miens: miens.stream,
          palette: paletteOf('original'),
        ),
      ),
    );

    testWidgets('mon message passe dans la MÊME bande', (tester) async {
      await bande(tester);
      miens.add('bien joué');
      await tester.pumpAndSettle();
      expect(find.text('bien joué'), findsOneWidget);
    });

    testWidgets('à MA couleur, et à droite', (tester) async {
      await bande(tester);
      miens.add('bien joué');
      await tester.pumpAndSettle();

      final bulle = tester.widget<MessageBubble>(find.byType(MessageBubble));
      expect(bulle.deMoi, isTrue, reason: 'c est moi qui l ai écrit');
      expect(coteDeLaBulle(tester), Alignment.centerRight);
    });

    testWidgets('le reçu reste à gauche, et à sa couleur', (tester) async {
      await bande(tester);
      recus.add('salut');
      await tester.pumpAndSettle();

      expect(
        tester.widget<MessageBubble>(find.byType(MessageBubble)).deMoi,
        isFalse,
      );
      expect(coteDeLaBulle(tester), Alignment.centerLeft);
    });

    testWidgets('et il s efface au bout du même temps', (tester) async {
      // « Traité de la même manière » : même durée, même minuteur.
      await bande(tester);
      miens.add('bien joué');
      await tester.pump();
      await tester.pump(kBulleEnJeuDuree - const Duration(milliseconds: 500));
      expect(find.text('bien joué'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.text('bien joué'), findsNothing);
    });

    testWidgets('les deux sens cohabitent, dans l ordre d arrivée', (
      tester,
    ) async {
      await bande(tester);
      recus.add('salut');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      miens.add('bien joué');
      await tester.pumpAndSettle();

      expect(find.text('salut'), findsOneWidget);
      expect(find.text('bien joué'), findsOneWidget);
      expect(
        tester.getRect(find.text('bien joué')).top,
        greaterThan(tester.getRect(find.text('salut')).top),
        reason: 'le dernier arrivé est en dessous, comme toujours',
      );
    });
  });

  group('De bout en bout, depuis une vraie partie', () {
    // « Il est écrit d'un autre endroit mais doit être traité de la même
    // manière. » La phrase qui compte : le message doit partir par le MÊME
    // envoi que la boîte de messages, vers le MÊME destinataire.

    late List<({String path, Map<String, dynamic> corps})> appels;

    setUp(() async {
      appels = [];
      final online = OnlineService(
        client: OnlineClient(
          api: ApiClient(
            client: MockClient((req) async {
              appels.add((
                path: req.url.path,
                corps: Map<String, dynamic>.from(jsonDecode(req.body) as Map),
              ));
              return http.Response(
                jsonEncode({'ok': true, 'token': 't', 'pseudo': 'nino'}),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
          ),
        ),
      );
      await online.client.login('nino', 'mdp');
      final precedent = OnlineService.instance;
      OnlineService.instance = online;
      addTearDown(() => OnlineService.instance = precedent);
    });

    Future<void> partie(WidgetTester tester) async {
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: OnlineGameScreen(
            game: makeGame(
              socket: FakeSocket(),
              myCamp: Camp.blanc,
              cadence: Cadence.quinze,
            ),
            myPseudo: 'nino',
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('écrit depuis le plateau, le message PART au chat', (
      tester,
    ) async {
      await partie(tester);
      await tester.tap(find.byIcon(Icons.chat_bubble_outline));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bien joué');
      await tester.tap(find.text(T('Envoyer')));
      await tester.pumpAndSettle();

      final envoi = appels.where((a) => a.path == '/send_message').toList();
      expect(envoi.length, 1, reason: 'un envoi, et un seul');
      expect(
        envoi.single.corps['pseudo'],
        'Adversaire',
        reason: 'à l adversaire de CETTE partie',
      );
      expect(envoi.single.corps['text'], 'bien joué');
    });

    testWidgets('et il paraît aussitôt dans la bande', (tester) async {
      await partie(tester);
      await tester.tap(find.byIcon(Icons.chat_bubble_outline));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bien joué');
      await tester.tap(find.text(T('Envoyer')));
      await tester.pumpAndSettle();

      expect(find.text('bien joué'), findsOneWidget);
      expect(
        tester.widget<MessageBubble>(find.byType(MessageBubble)).deMoi,
        isTrue,
      );
    });

    testWidgets('renoncer n envoie rien', (tester) async {
      await partie(tester);
      await tester.tap(find.byIcon(Icons.chat_bubble_outline));
      await tester.pumpAndSettle();
      // On referme la feuille sans rien écrire.
      await tester.tapAt(const Offset(196, 40));
      await tester.pumpAndSettle();

      expect(appels.where((a) => a.path == '/send_message'), isEmpty);
      expect(find.byType(MessageBubble), findsNothing);
    });
  });

  group('En CORRESPONDANCE aussi', () {
    // Nino : « je le veux aussi en correspondance. » Une partie de
    // correspondance se joue sur plusieurs jours — raison de plus pour
    // pouvoir dire un mot sans ouvrir la conversation.

    late List<({String path, Map<String, dynamic> corps})> appels;
    late OnlineClient client;

    Map<String, dynamic> partieJson() => const {
      'id': 'g1',
      'statut': 'en_cours',
      'adversaire': 'Ana',
      'adversaire_melo': 1600,
      'ma_couleur': 'Blanc',
      'turn': 'Blanc',
      'my_turn': true,
      'mon_score': 0,
      'score_adverse': 0,
      'objectif': 'partie',
      'moves_text': '',
      'is_defieur': false,
    };

    setUp(() async {
      appels = [];
      client = OnlineClient(
        api: ApiClient(
          client: MockClient((req) async {
            appels.add((
              path: req.url.path,
              corps: Map<String, dynamic>.from(jsonDecode(req.body) as Map),
            ));
            return http.Response(
              jsonEncode({'ok': true, 'token': 't', 'pseudo': 'nino'}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );
      final online = OnlineService(client: client);
      await online.client.login('nino', 'mdp');
      final precedent = OnlineService.instance;
      OnlineService.instance = online;
      addTearDown(() => OnlineService.instance = precedent);
    });

    Future<void> ouvre(WidgetTester tester, {bool visiteur = false}) async {
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: CorrGameScreen(
            game: CorrGame.fromJson(partieJson()),
            service: CorrespondenceService(client),
            myPseudo: 'nino',
            visiteur: visiteur,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('la touche est là, et le message part', (tester) async {
      await ouvre(tester);
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chat_bubble_outline));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'à toi de jouer');
      await tester.tap(find.text(T('Envoyer')));
      await tester.pumpAndSettle();

      final envoi = appels.where((a) => a.path == '/send_message').toList();
      expect(envoi.length, 1);
      expect(envoi.single.corps['pseudo'], 'Ana');
      expect(envoi.single.corps['text'], 'à toi de jouer');
      expect(find.text('à toi de jouer'), findsOneWidget);
    });

    testWidgets('mais JAMAIS en visiteur', (tester) async {
      // « Ne peut pas intervenir ni voir la boîte de message » : on regarde
      // jouer deux autres personnes, on ne s invite pas dans leur
      // conversation.
      await ouvre(tester, visiteur: true);
      expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
    });
  });
}

/// De quel CÔTÉ la bulle est rangée.
///
/// On ne prend pas le premier `Align` venu : la montée d'une bulle neuve en
/// pose un autre au-dessus, pour sa hauteur. Celui qu'on cherche est celui
/// qui range à gauche ou à droite, et on le nomme ainsi.
Alignment coteDeLaBulle(WidgetTester tester) => tester
    .widgetList<Align>(
      find.ancestor(
        of: find.byType(MessageBubble),
        matching: find.byType(Align),
      ),
    )
    .map((a) => a.alignment)
    .whereType<Alignment>()
    .firstWhere((a) => a == Alignment.centerLeft || a == Alignment.centerRight);
