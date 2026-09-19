/// Historique et lecteur : la liste de l'appareil, puis le rejeu.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/nmc.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/local_games.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/history_screen.dart';
import 'package:lafuga/ui/screens/replay_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _meta = NmcMeta(
  date: '2026-09-19',
  player1: 'Nino',
  player2: 'Deep Grey',
  blanc: 'Nino',
  objectif: 'partie',
  cadence: '5min',
  result: '1-0',
  method: 'fugue',
  points: '2',
);

/// Quelques coups légaux, pour avoir une partie à rejouer.
List<String> _someMoves(int count) {
  var board = Board.initial();
  var camp = Camp.blanc;
  final moves = <String>[];
  for (var i = 0; i < count; i++) {
    final legal = generateMoves(
      board,
      camp,
    ).where((m) => !m.fugue && m.matOn == null && m.fugueBy == null).toList();
    final mv = legal[i % legal.length];
    moves.add(notationOn(board, mv));
    board = mv.board;
    camp = camp.opposite;
  }
  return moves;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late LocalGamesStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.load();
    await Translations.load('fr');
    tmp = Directory.systemTemp.createTempSync('lafuga_hist');
    store = LocalGamesStore(directory: tmp);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HistoryScreen(online: OnlineService.instance, local: store),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sans compte, l onglet du compte demande la connexion', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('Connexion requise'), findsOneWidget);
  });

  testWidgets('les parties de l appareil sont listées', (tester) async {
    await store.save(_meta, _someMoves(4), name: 'partie1');
    await open(tester);

    await tester.tap(find.text('Sur cet appareil'));
    await tester.pumpAndSettle();

    expect(find.text('Nino – Deep Grey'), findsOneWidget);
    expect(find.textContaining('fugue'), findsOneWidget);
  });

  testWidgets('sans partie enregistrée, on le dit', (tester) async {
    await open(tester);

    await tester.tap(find.text('Sur cet appareil'));
    await tester.pumpAndSettle();

    expect(find.text('Aucune partie sur cet appareil.'), findsOneWidget);
  });

  testWidgets('on ouvre une partie et on la rejoue coup par coup', (
    tester,
  ) async {
    await store.save(_meta, _someMoves(4), name: 'partie1');
    await open(tester);

    await tester.tap(find.text('Sur cet appareil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nino – Deep Grey'));
    await tester.pumpAndSettle();

    expect(find.byType(ReplayScreen), findsOneWidget);
    expect(find.text('Position de départ'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(find.text('Position de départ'), findsNothing);
    expect(find.textContaining('1 / 4'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.last_page));
    await tester.pumpAndSettle();
    expect(find.textContaining('4 / 4'), findsOneWidget);
  });

  testWidgets('une partie effacée disparaît de la liste', (tester) async {
    await store.save(_meta, _someMoves(2), name: 'partie1');
    await open(tester);

    await tester.tap(find.text('Sur cet appareil'));
    await tester.pumpAndSettle();
    expect(find.text('Nino – Deep Grey'), findsOneWidget);

    await tester.drag(find.text('Nino – Deep Grey'), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Aucune partie sur cet appareil.'), findsOneWidget);
    expect(await store.list(), isEmpty);
  });
}
