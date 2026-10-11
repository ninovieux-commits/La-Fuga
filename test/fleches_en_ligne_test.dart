/// Les flèches du bandeau, en partie de matchmaking.
///
/// Nino : « les flèches directionnelles ne fonctionnent pas durant le
/// matchmaking ».
///
/// Elles ne faisaient rien du tout : l'écran de partie en ligne passait
/// `onSelect: (_) {}` au bandeau et ne lui donnait aucun `activeIndex`. La
/// correspondance et le jeu local, eux, câblaient les deux depuis le début.
///
/// Une partie en ligne a deux contraintes que les autres n'ont pas : la
/// pendule tourne, et le serveur tient l'unique cours de la partie. Revoir un
/// coup ne doit donc ni permettre de jouer depuis le passé — pas de branche
/// d'analyse ici — ni retenir le joueur quand l'adversaire répond.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/engine/random_fuga.dart';
import 'package:lafuga/game/clock.dart';
import 'package:lafuga/game/online_game.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/socket_client.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/online_game_screen.dart';
import 'package:lafuga/ui/widgets/game_board_view.dart';
import 'package:lafuga/ui/widgets/move_strip.dart';
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
  });

  /// Le plateau tel qu'il est AFFICHÉ.
  String affiche(WidgetTester tester) =>
      tester.widget<GameBoardView>(find.byType(GameBoardView)).board.render();

  MoveStrip bandeau(WidgetTester tester) =>
      tester.widget<MoveStrip>(find.byType(MoveStrip));

  GameBoardView vue(WidgetTester tester) =>
      tester.widget<GameBoardView>(find.byType(GameBoardView));

  /// Joue un coup au doigt, par l'écran : la case de départ, l'arrivée, puis
  /// l'arrivée à nouveau pour valider — c'est la manœuvre en trois gestes de
  /// `MoveController`, et deux gestes ne jouent rien du tout.
  Future<void> joueAuDoigt(WidgetTester tester, OnlineGame jeu) async {
    final move = generateMoves(jeu.game.board, jeu.game.turn).first;
    for (final cell in [move.from, move.to, move.to]) {
      vue(tester).onTapCell(cell);
      await tester.pumpAndSettle();
    }
  }

  /// Une partie en ligne ouverte, et les positions traversées.
  ///
  /// Les positions sont relevées sur le contrôleur APRÈS chaque coup, pas
  /// rejouées : un test qui rejouerait la partie de son côté ne prouverait
  /// rien de plus que la cohérence du rejeu avec lui-même.
  Future<({OnlineGame jeu, FakeSocket socket, List<String> positions})> ouvre(
    WidgetTester tester, {
    int coups = 0,
    String? randomCode,
  }) async {
    final socket = FakeSocket();
    final jeu = makeGame(
      socket: socket,
      cadence: Cadence.quinze,
      randomCode: randomCode,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OnlineGameScreen(game: jeu, myPseudo: 'Nino'),
      ),
    );
    await tester.pump();

    final positions = <String>[jeu.game.board.render()];
    for (var i = 0; i < coups; i++) {
      final move = generateMoves(jeu.game.board, jeu.game.turn).first;
      final notation = notationOn(jeu.game.board, move);
      socket.emit(FugaEvents.coupAdverse, {'notation': notation});
      await tester.pump();
      positions.add(jeu.game.board.render());
    }
    return (jeu: jeu, socket: socket, positions: positions);
  }

  group('Revoir un coup passé', () {
    testWidgets('la flèche gauche remonte coup par coup, jusqu au départ', (
      tester,
    ) async {
      final p = await ouvre(tester, coups: 3);
      expect(p.jeu.game.history.length, 3, reason: 'trois coups au bandeau');
      expect(affiche(tester), p.positions[3]);
      expect(bandeau(tester).activeIndex, isNull, reason: 'on est au présent');

      await tester.tap(find.text('<'));
      await tester.pumpAndSettle();
      expect(
        affiche(tester),
        p.positions[2],
        reason: 'la flèche ne faisait RIEN en partie de matchmaking',
      );
      expect(bandeau(tester).activeIndex, 1);

      await tester.tap(find.text('<'));
      await tester.pumpAndSettle();
      expect(affiche(tester), p.positions[1]);
      expect(bandeau(tester).activeIndex, 0);

      // Le dernier pas mène AVANT le premier coup.
      await tester.tap(find.text('<'));
      await tester.pumpAndSettle();
      expect(affiche(tester), p.positions[0]);
      expect(bandeau(tester).activeIndex, -1);
    });

    testWidgets('la flèche droite redescend jusqu au présent', (tester) async {
      final p = await ouvre(tester, coups: 3);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('<'));
        await tester.pumpAndSettle();
      }
      expect(affiche(tester), p.positions[0]);

      await tester.tap(find.text('>'));
      await tester.pumpAndSettle();
      expect(affiche(tester), p.positions[1]);

      await tester.tap(find.text('>'));
      await tester.pumpAndSettle();
      expect(affiche(tester), p.positions[2]);

      await tester.tap(find.text('>'));
      await tester.pumpAndSettle();
      expect(affiche(tester), p.positions[3]);
      expect(
        bandeau(tester).activeIndex,
        isNull,
        reason: 'le dernier coup, c est le présent',
      );
    });

    testWidgets('toucher une notation du bandeau y mène', (tester) async {
      final p = await ouvre(tester, coups: 3);
      await tester.tap(find.text(p.jeu.game.history[0]));
      await tester.pumpAndSettle();
      expect(affiche(tester), p.positions[1]);
      expect(bandeau(tester).activeIndex, 0);
    });

    testWidgets('sans coup joué, les flèches ne mènent nulle part', (
      tester,
    ) async {
      final p = await ouvre(tester);
      await tester.tap(find.text('<'));
      await tester.pumpAndSettle();
      expect(affiche(tester), p.positions[0]);
      expect(bandeau(tester).activeIndex, isNull);
    });

    testWidgets('le plateau regardé ne montre ni sélection ni cadre', (
      tester,
    ) async {
      await ouvre(tester, coups: 2);
      await tester.tap(find.text('<'));
      await tester.pumpAndSettle();
      final v = vue(tester);
      expect(v.selected, isNull);
      expect(v.groupSelection, isEmpty);
      expect(v.highlighted, isEmpty);
      expect(
        v.fuguedHeirs,
        isEmpty,
        reason: 'la fugue clôt la partie : elle est toujours au dernier coup',
      );
    });
  });

  group('Une partie en ligne n est pas une analyse', () {
    testWidgets('au présent, le doigt joue — sinon le test suivant est vide', (
      tester,
    ) async {
      final p = await ouvre(tester, coups: 2);
      expect(p.jeu.isMyTurn, isTrue, reason: 'c est bien à nous de jouer');

      await joueAuDoigt(tester, p.jeu);

      expect(p.jeu.game.history.length, 3);
      expect(
        p.socket.didSend('jouer_coup'),
        isTrue,
        reason: 'le coup doit partir au serveur',
      );
    });

    testWidgets('pendant la revue, le doigt ne joue pas', (tester) async {
      final p = await ouvre(tester, coups: 2);
      await tester.tap(find.text('<'));
      await tester.pumpAndSettle();

      final avant = p.jeu.game.history.length;
      final envoyes = p.socket.sent.length;
      // Les mêmes trois gestes qui jouent au présent : ici, rien.
      await joueAuDoigt(tester, p.jeu);

      expect(p.jeu.game.history.length, avant, reason: 'rien n a été joué');
      expect(
        p.socket.sent.length,
        envoyes,
        reason: 'le serveur tient l unique cours de la partie',
      );
      expect(
        affiche(tester),
        p.positions[1],
        reason: 'on regarde toujours le même coup',
      );
    });

    testWidgets('le coup de l adversaire ramène au présent', (tester) async {
      // La pendule tourne : rester sur une position passée, c est perdre au
      // temps en regardant ailleurs.
      final p = await ouvre(tester, coups: 2);
      await tester.tap(find.text('<'));
      await tester.pumpAndSettle();
      expect(bandeau(tester).activeIndex, 0);

      final move = generateMoves(p.jeu.game.board, p.jeu.game.turn).first;
      p.socket.emit(FugaEvents.coupAdverse, {
        'notation': notationOn(p.jeu.game.board, move),
      });
      await tester.pumpAndSettle();

      expect(bandeau(tester).activeIndex, isNull);
      expect(affiche(tester), p.jeu.game.board.render());
      expect(p.jeu.game.history.length, 3);
    });
  });

  group('La position de départ ne bouge pas', () {
    testWidgets('un coup joué au doigt ne la déplace pas', (tester) async {
      // `MoveController` fait muter SON plateau sur place pendant la manœuvre
      // (`board.setCell`). Si la position de départ était le même objet, le
      // premier geste la déplacerait, et le retour au départ montrerait une
      // position qui n'a jamais existé.
      final p = await ouvre(tester);
      await joueAuDoigt(tester, p.jeu);
      expect(p.jeu.game.history.length, 1, reason: 'un coup a bien été joué');

      await tester.tap(find.text('<'));
      await tester.pumpAndSettle();
      expect(bandeau(tester).activeIndex, -1);
      expect(
        affiche(tester),
        Board.initial().render(),
        reason: 'le départ doit être le départ, intact',
      );
      expect(affiche(tester), p.positions[0]);
    });
  });

  group('Random Fuga', () {
    testWidgets('le code s affiche, et le départ est SA position', (
      tester,
    ) async {
      const code = '.03-09';
      final depart = buildRandomFugaBoard(code);
      expect(depart, isNotNull, reason: 'le code doit être valide');
      expect(
        depart!.render(),
        isNot(Board.initial().render()),
        reason: 'sans quoi le test ne prouverait rien',
      );

      final p = await ouvre(tester, coups: 2, randomCode: code);
      expect(bandeau(tester).randomCode, code);

      await tester.tap(find.text('<'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('<'));
      await tester.pumpAndSettle();
      expect(bandeau(tester).activeIndex, -1);
      expect(
        affiche(tester),
        depart.render(),
        reason: 'la revue doit repartir de la position tirée au sort',
      );
      expect(affiche(tester), p.positions[0]);
    });
  });

  group('La partie suivante du match', () {
    testWidgets('repart sur ses propres coups', (tester) async {
      final p = await ouvre(tester, coups: 3);
      await tester.tap(find.text('<'));
      await tester.pumpAndSettle();
      expect(
        bandeau(tester).activeIndex,
        1,
        reason: 'trois coups, un pas en arrière',
      );

      // La partie suivante part d'AILLEURS : sans cela, les deux positions de
      // départ se ressembleraient et oublier de reprendre la nouvelle ne se
      // verrait pas.
      const code = '.03-09';
      final depart2 = buildRandomFugaBoard(code)!;
      expect(depart2.render(), isNot(Board.initial().render()));

      p.jeu.startNextGame(
        const OnlineGameInfo(
          gameId: 'g2',
          myCamp: Camp.noir,
          opponent: 'Adversaire',
          opponentMelo: 1500,
          objectif: '3',
          cadence: '15 min',
          randomCode: code,
        ),
      );
      await tester.pumpAndSettle();

      expect(p.jeu.game.history, isEmpty);
      expect(
        bandeau(tester).activeIndex,
        isNull,
        reason: 'on ne regarde plus un coup de la partie d avant',
      );
      expect(
        affiche(tester),
        depart2.render(),
        reason: 'la nouvelle partie part de SA position',
      );

      // Et les flèches marchent sur la NOUVELLE partie.
      final move = generateMoves(p.jeu.game.board, p.jeu.game.turn).first;
      final depart = p.jeu.game.board.render();
      p.socket.emit(FugaEvents.coupAdverse, {
        'notation': notationOn(p.jeu.game.board, move),
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('<'));
      await tester.pumpAndSettle();
      expect(affiche(tester), depart);
      expect(bandeau(tester).activeIndex, -1);
    });
  });
}
