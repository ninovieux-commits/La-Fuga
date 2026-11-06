/// LE MÉLO D'UNE PARTIE : affiché juste, et jamais perdu.
///
/// Nino, capture de fin de partie à l'appui : « la mise à jour du mélo
/// s'affiche mal et est faillible. [...] Il faut que les mélos gagnés et
/// perdus durant une partie soient spécifiés dans l'historique, à côté des
/// noms des joueurs. »
///
/// Deux choses, donc : la ligne du popup, qui restait figée sur « Mise à
/// jour du mélo… » alors que le bandeau affichait déjà « +12 » ; et la
/// variation, qui ne survivait nulle part à la fin de la partie.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/clock.dart';
import 'package:lafuga/game/game_archive.dart';
import 'package:lafuga/game/nmc.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/local_games.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/net/socket_client.dart';
import 'package:lafuga/ui/screens/history_screen.dart';
import 'package:lafuga/ui/screens/online_game_screen.dart';
import 'package:lafuga/ui/widgets/end_dialogs.dart';
import 'package:lafuga/ui/widgets/fuga_header.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_game_test.dart' show FakeSocket, makeGame;

const Map<String, Object> _launched = {'lang_chosen': true, 'tuto_seen': true};

/// Un compte qui note ce qu'on lui demande d'enregistrer.
class _CompteEspion implements AccountGames {
  final List<Map<String, dynamic>> envois = [];

  @override
  bool get isLoggedIn => true;

  @override
  Future<void> saveGame(Map<String, dynamic> data) async => envois.add(data);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(_launched);
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
  });
  tearDown(resetScale);

  group('Le .nmc garde le mélo et sa variation', () {
    test('ils font l aller-retour, signe compris', () {
      const meta = NmcMeta(
        date: '2026-11-06 12:00',
        player1: 'nino',
        player2: 'celia',
        blanc: 'nino',
        objectif: 'partie',
        cadence: '5min',
        result: '1-0',
        method: 'fugue',
        points: '2',
        melo1: 1512,
        melo2: 1488,
        variation1: 12,
        variation2: -12,
      );
      final texte = buildNmc(meta, const ['Do1-Do2']);
      // Le classement SANS signe, la variation AVEC : c'est ce qui les
      // distingue dans le fichier.
      expect(texte, contains('[Melo1 "1512"]'));
      expect(texte, contains('[Melo2 "1488"]'));
      expect(texte, contains('[Variation1 "+12"]'));
      expect(texte, contains('[Variation2 "-12"]'));

      final relu = parseNmc(texte).meta;
      expect(relu.melo1, 1512);
      expect(relu.melo2, 1488);
      expect(relu.variation1, 12);
      expect(relu.variation2, -12);
    });

    test('un vieux fichier où Melo1 portait la variation se relit', () {
      // Le champ a porté la variation le temps d'une version. Le signe les
      // sépare : un classement ne s'écrit jamais « +12 ».
      const ancien =
          '[Date "2026-11-05 10:00"]\n'
          '[Joueur1 "nino"]\n'
          '[Joueur2 "celia"]\n'
          '[Blanc "nino"]\n'
          '[Melo1 "+12"]\n'
          '[Melo2 "-12"]\n'
          '\n'
          '1.Do1-Do2';
      final relu = parseNmc(ancien).meta;
      expect(relu.variation1, 12, reason: 'c était une variation');
      expect(relu.variation2, -12);
      expect(relu.melo1, isNull, reason: 'le classement n y était pas');
      expect(relu.melo2, isNull);
    });

    test('sans variation, le fichier n en parle pas', () {
      const meta = NmcMeta(
        date: '2026-11-06 12:00',
        player1: 'nino',
        player2: 'celia',
        blanc: 'nino',
        objectif: 'partie',
        cadence: 'zen',
        result: '½-½',
        method: 'nulle',
        points: '0',
      );
      final texte = buildNmc(meta, const ['Do1-Do2']);
      expect(texte, isNot(contains('Melo')));
      expect(texte, isNot(contains('Variation')));
      expect(parseNmc(texte).meta.melo1, isNull);
      expect(parseNmc(texte).meta.variation1, isNull);
    });

    test('une variation nulle s écrit « +0 », et se relit', () {
      const meta = NmcMeta(
        date: '2026-11-06 12:00',
        player1: 'nino',
        player2: 'celia',
        blanc: 'nino',
        objectif: 'partie',
        cadence: 'zen',
        result: '½-½',
        method: 'nulle',
        points: '0',
        variation1: 0,
      );
      expect(buildNmc(meta, const []), contains('[Variation1 "+0"]'));
      expect(parseNmc(buildNmc(meta, const [])).meta.variation1, 0);
    });
  });

  group('L archive range le mélo du bon côté', () {
    test('en Blanc, il est le premier', () {
      final a = buildOpponentArchive(
        myPseudo: 'nino',
        opponent: 'celia',
        myCamp: Camp.blanc,
        winner: Camp.blanc,
        method: 'fugue',
        history: const ['Do1-Do2'],
        onlineGameId: 'g1',
        myMelo: 1512,
        myMeloDelta: 12,
      );
      expect(a.meta.player1, 'nino');
      expect(a.meta.melo1, 1512);
      expect(a.meta.variation1, 12);
      expect(a.meta.melo2, isNull, reason: 'celui de l adversaire est inconnu');
      expect(a.meta.variation2, isNull);
    });

    test('en Noir, il est le second', () {
      final a = buildOpponentArchive(
        myPseudo: 'nino',
        opponent: 'celia',
        myCamp: Camp.noir,
        winner: Camp.noir,
        method: 'fugue',
        history: const ['Do1-Do2'],
        onlineGameId: 'g1',
        myMelo: 1492,
        myMeloDelta: -8,
      );
      expect(a.meta.player2, 'nino');
      expect(a.meta.melo2, 1492);
      expect(a.meta.variation2, -8);
      expect(a.meta.melo1, isNull);
      expect(a.meta.variation1, isNull);
    });

    test('les deux partent au serveur quand on les a', () async {
      final compte = _CompteEspion();
      final tmp = Directory.systemTemp.createTempSync('lafuga_melo');
      addTearDown(() => tmp.deleteSync(recursive: true));
      await GameArchive(
        account: compte,
        local: LocalGamesStore(directory: tmp),
      ).store(
        buildOpponentArchive(
          myPseudo: 'nino',
          opponent: 'celia',
          myCamp: Camp.blanc,
          winner: Camp.blanc,
          method: 'fugue',
          history: const ['Do1-Do2'],
          onlineGameId: 'g1',
          myMelo: 1512,
          myMeloDelta: 12,
          opponentMelo: 1488,
          opponentMeloDelta: -12,
        ),
      );
      expect(compte.envois.single['melo1'], 1512);
      expect(compte.envois.single['melo2'], 1488);
      expect(compte.envois.single['variation1'], 12);
      expect(compte.envois.single['variation2'], -12);
      expect(
        compte.envois.single['nmc_text'],
        contains('[Variation1 "+12"]'),
        reason: 'le fichier les porte aussi, pas seulement les champs',
      );
    });

    test('sans variation, rien n est envoyé de plus', () async {
      final compte = _CompteEspion();
      final tmp = Directory.systemTemp.createTempSync('lafuga_melo');
      addTearDown(() => tmp.deleteSync(recursive: true));
      await GameArchive(
        account: compte,
        local: LocalGamesStore(directory: tmp),
      ).store(
        buildOpponentArchive(
          myPseudo: 'nino',
          opponent: 'celia',
          myCamp: Camp.blanc,
          winner: null,
          method: 'nulle',
          history: const ['Do1-Do2'],
          onlineGameId: 'g1',
        ),
      );
      expect(compte.envois.single.containsKey('melo1'), isFalse);
      expect(compte.envois.single.containsKey('variation1'), isFalse);
    });
  });

  group('La ligne du popup de fin', () {
    testWidgets('elle se met à jour quand le mélo arrive', (tester) async {
      // Le défaut exact : le texte était figé à l'ouverture, or le mélo
      // arrive APRÈS la fin de la partie.
      final ligne = ValueNotifier<String?>(T('Mise à jour du mélo…'));
      addTearDown(ligne.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFinishDialog(
                context,
                palette: paletteOf('original'),
                title: 'Fugue',
                body: '1 / 1',
                winner: 'nino',
                meloLine: ligne,
                onMenu: () {},
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      expect(find.text('Mise à jour du mélo…'), findsOneWidget);

      ligne.value = 'Mélo : 1549  (+12)';
      await tester.pumpAndSettle();
      expect(find.text('Mise à jour du mélo…'), findsNothing);
      expect(find.text('Mélo : 1549  (+12)'), findsOneWidget);
    });

    testWidgets('sans ligne, le popup n en montre aucune', (tester) async {
      final ligne = ValueNotifier<String?>(null);
      addTearDown(ligne.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFinishDialog(
                context,
                palette: paletteOf('original'),
                title: 'Fugue',
                body: '1 / 1',
                meloLine: ligne,
                onMenu: () {},
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Mélo'), findsNothing);
    });
  });

  group('L écran de partie, de bout en bout', () {
    testWidgets('le popup suit le mélo, et l historique le garde', (
      tester,
    ) async {
      final compte = _CompteEspion();
      final tmp = Directory.systemTemp.createTempSync('lafuga_ecran_melo');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final socket = FakeSocket();
      final partie = makeGame(socket: socket, cadence: Cadence.quinze);

      await tester.pumpWidget(
        MaterialApp(
          home: OnlineGameScreen(
            game: partie,
            myPseudo: 'nino',
            archive: GameArchive(
              account: compte,
              local: LocalGamesStore(directory: tmp),
            ),
          ),
        ),
      );
      await tester.pump();

      // La partie se termine : le popup s'ouvre, et le mélo n'est pas encore
      // là — c'est l'instant exact de la capture de Nino.
      socket.emit(FugaEvents.partieTerminee, {
        'methode': 'fugue',
        'loser_color': 'Noir',
      });
      await tester.pumpAndSettle();
      expect(find.text(T('Mise à jour du mélo…')), findsOneWidget);
      expect(compte.envois, hasLength(1), reason: 'rangée tout de suite');
      expect(compte.envois.single.containsKey('melo1'), isFalse);

      // Le serveur annonce les DEUX mélos : le mien et celui d'en face.
      socket.emit(FugaEvents.meloMaj, {
        'mon_melo': 1549,
        'delta': 12,
        'son_melo': 1488,
        'son_delta': -12,
      });
      await tester.pumpAndSettle();

      expect(find.text(T('Mise à jour du mélo…')), findsNothing);
      expect(find.textContaining('1549'), findsWidgets);
      expect(find.textContaining('+12'), findsWidgets);

      // Et la partie est rangée une seconde fois, AVEC la variation, sous le
      // même identifiant : le serveur la remplace, il ne la double pas.
      expect(compte.envois, hasLength(2));
      expect(compte.envois.last['melo1'], 1549, reason: 'le classement');
      expect(compte.envois.last['variation1'], 12, reason: 'et sa variation');
      expect(compte.envois.last['game_uid'], compte.envois.first['game_uid']);
      expect(compte.envois.last['melo2'], 1488, reason: 'celui d en face');
      expect(compte.envois.last['variation2'], -12);
      expect(compte.envois.last['nmc_text'], contains('[Melo1 "1549"]'));
      expect(compte.envois.last['nmc_text'], contains('[Variation1 "+12"]'));
      expect(compte.envois.last['nmc_text'], contains('[Melo2 "1488"]'));

      // Une troisième annonce ne réécrit rien.
      socket.emit(FugaEvents.meloMaj, {'mon_melo': 1549, 'delta': 12});
      await tester.pumpAndSettle();
      expect(compte.envois, hasLength(2));
    });

    testWidgets('un serveur qui ne dit que mon mélo laisse l autre vide', (
      tester,
    ) async {
      // Les champs `son_melo` et `son_delta` sont arrivés avec l'historique.
      // Un serveur d'avant ne les envoie pas : la place de l'adversaire
      // reste vide, et rien ne se devine.
      final compte = _CompteEspion();
      final tmp = Directory.systemTemp.createTempSync('lafuga_vieux');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final socket = FakeSocket();
      final partie = makeGame(socket: socket, cadence: Cadence.quinze);

      await tester.pumpWidget(
        MaterialApp(
          home: OnlineGameScreen(
            game: partie,
            myPseudo: 'nino',
            archive: GameArchive(
              account: compte,
              local: LocalGamesStore(directory: tmp),
            ),
          ),
        ),
      );
      await tester.pump();
      socket.emit(FugaEvents.partieTerminee, {
        'methode': 'fugue',
        'loser_color': 'Noir',
      });
      await tester.pumpAndSettle();
      socket.emit(FugaEvents.meloMaj, {'mon_melo': 1549, 'delta': 12});
      await tester.pumpAndSettle();

      expect(compte.envois.last['melo1'], 1549);
      expect(compte.envois.last.containsKey('melo2'), isFalse);
      expect(compte.envois.last.containsKey('variation2'), isFalse);
    });

    testWidgets('si l annonce ne vient jamais, rien ne casse', (tester) async {
      // Nino : « est faillible ». `melo_maj` est un événement : une socket
      // coupée au mauvais moment et il n'arrive pas. Le guetteur part alors
      // chercher le mélo lui-même ; ici il n'y a pas de compte en ligne,
      // donc rien à trouver — ce qu'on vérifie, c'est que la minuterie
      // s'arme, se déclenche et se range sans rien faire tomber.
      final compte = _CompteEspion();
      final tmp = Directory.systemTemp.createTempSync('lafuga_sans_melo');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final socket = FakeSocket();
      final partie = makeGame(socket: socket, cadence: Cadence.quinze);

      await tester.pumpWidget(
        MaterialApp(
          home: OnlineGameScreen(
            game: partie,
            myPseudo: 'nino',
            archive: GameArchive(
              account: compte,
              local: LocalGamesStore(directory: tmp),
            ),
          ),
        ),
      );
      await tester.pump();
      socket.emit(FugaEvents.partieTerminee, {
        'methode': 'fugue',
        'loser_color': 'Noir',
      });
      await tester.pumpAndSettle();

      // Bien au-delà des six secondes d'attente.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      expect(compte.envois, hasLength(1), reason: 'la partie reste rangée');
    });
  });

  group('L historique montre le mélo', () {
    late Directory tmp;
    late LocalGamesStore store;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lafuga_hist_melo');
      store = LocalGamesStore(directory: tmp);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<void> ouvre(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HistoryScreen(
            online: OnlineService.instance,
            mode: HistoryMode.local,
            store: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('il s écrit à côté du nom, suivi de sa variation', (
      tester,
    ) async {
      await store.save(
        const NmcMeta(
          date: '2026-11-06 12:00',
          player1: 'nino',
          player2: 'celia',
          blanc: 'nino',
          objectif: 'partie',
          cadence: '5min',
          result: '1-0',
          method: 'fugue',
          points: '2',
          melo1: 1512,
          melo2: 1488,
          variation1: 12,
          variation2: -12,
        ),
        const ['Do1-Do2'],
        name: 'p1',
      );
      await ouvre(tester);

      // Nino : « ajoute aussi le mélo des joueurs tel que : mesange 1500 -9
      // vs nino 1512 +9 ». Les ronds de couleur sont des widgets posés dans
      // le texte : on lit le texte NU, eux mis à part.
      expect(_ligneDesNoms(tester), 'nino 1512 +12  vs  celia 1488 -12');
    });

    testWidgets('sans variation, la ligne reste un texte simple', (
      tester,
    ) async {
      await store.save(
        const NmcMeta(
          date: '2026-11-06 12:00',
          player1: 'nino',
          player2: 'celia',
          blanc: 'nino',
          objectif: 'partie',
          cadence: '5min',
          result: '1-0',
          method: 'fugue',
          points: '2',
        ),
        const ['Do1-Do2'],
        name: 'p1',
      );
      await ouvre(tester);
      expect(_ligneDesNoms(tester), 'nino  vs  celia');
    });

    testWidgets('un rond dit qui tenait quelle couleur', (tester) async {
      // Nino : « mets aussi un rond noir ou blanc avant le nom pour
      // indiquer qui avait quelle couleur. »
      await store.save(
        const NmcMeta(
          date: '2026-11-06 12:00',
          player1: 'nino',
          player2: 'celia',
          // Les Blancs sont le SECOND nommé : le rond doit suivre le
          // joueur, pas la place.
          blanc: 'celia',
          objectif: 'partie',
          cadence: '5',
          result: '0-1',
          method: 'fugue',
          points: '2',
        ),
        const ['Do1-Do2'],
        name: 'p1',
      );
      await ouvre(tester);

      final ronds = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.shape == BoxShape.circle)
          .toList();
      expect(ronds, hasLength(2), reason: 'un rond par joueur');
      expect(ronds.first.color, Colors.black, reason: 'nino tenait les Noirs');
      expect(
        ronds.first.border!.top.color,
        Colors.white,
        reason: 'le cerne prend l autre couleur',
      );
      expect(ronds.last.color, Colors.white, reason: 'celia tenait les Blancs');
      expect(ronds.last.border!.top.color, Colors.black);
    });
  });

  group('Le titre des menus', () {
    testWidgets('il n est plus en italique, et il est gravé', (tester) async {
      // Nino : « je ne veux pas que les titres des menus soient marqués en
      // italique. J'aimerais en revanche qu'ils aient l'air gravés. »
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: FugaHeader(
              back: '< Retour',
              title: 'En local',
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final titre = tester.widget<Text>(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.textSpan?.toPlainText() ?? w.data ?? '').contains('En local'),
        ),
      );
      expect(titre.style!.fontStyle, isNot(FontStyle.italic));

      // La gravure : l'ombre du creux en haut à gauche, la lèvre éclairée en
      // bas à droite.
      final reliefs = titre.style!.shadows!;
      expect(reliefs, hasLength(2));
      expect(reliefs.first.offset.dx, lessThan(0));
      expect(reliefs.first.offset.dy, lessThan(0));
      expect(reliefs.last.offset.dx, greaterThan(0));
      expect(reliefs.last.offset.dy, greaterThan(0));
      // Encre sombre : c'est la lèvre CLAIRE qu'on voit.
      expect(reliefs.last.color.a, greaterThan(reliefs.first.color.a));
    });

    testWidgets('sur une encre claire, c est l ombre qui se voit', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: FugaHeader(
              back: '< Retour',
              title: 'Composer le thème',
              titleColor: Colors.white,
              bold: true,
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final titre = tester.widget<Text>(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.textSpan?.toPlainText() ?? w.data ?? '').contains('Composer'),
        ),
      );
      final reliefs = titre.style!.shadows!;
      expect(reliefs.first.color.a, greaterThan(reliefs.last.color.a));
    });
  });
}

/// La ligne des noms d'une carte, les ronds de couleur mis à part.
String _ligneDesNoms(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map(
      (t) =>
          t.textSpan?.toPlainText(includePlaceholders: false) ?? t.data ?? '',
    )
    .firstWhere((s) => s.contains(' vs '));
