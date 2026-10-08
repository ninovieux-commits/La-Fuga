/// Le coup de l'adversaire s'entend.
///
/// Nino : « les coups de l'adversaire ne sont pas accompagnés de sons. »
///
/// Le son ne partait que de `_onTapCell` — au doigt, et nulle part ailleurs.
/// Un coup joué par Deep Grey sonnait bien (`game_screen`), mais celui qui
/// arrivait par le réseau glissait sous les yeux dans un silence complet. En
/// correspondance aussi, où les coups arrivent maintenant en direct.
///
/// Deux manques, pas un :
///   — l'écran en ligne n'appelait jamais le lecteur pour un coup reçu, et il
///     n'avait de toute façon pas la notation sous la main : `pendingHighlight`
///     ne portait que l'encadrement et les glissées ;
///   — l'écran de correspondance animait le coup arrivé sans le jouer.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/clock.dart';
import 'package:lafuga/game/sound_player.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/net/socket_client.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/corr_game_screen.dart';
import 'package:lafuga/ui/screens/online_game_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_game_test.dart' show FakeSocket, makeGame;

/// Un lecteur qui ne joue rien et retient tout.
final class FauxSons implements SoundPlayer {
  final List<String> joues = [];

  /// Le volume de chaque coup joué — l'accent des danses passe par là.
  final List<double> gains = [];

  @override
  void playNotation(String? notation, {double gain = 1}) {
    joues.add(notation ?? '');
    gains.add(gain);
  }

  // `init` et `dispose` rendent un Future : les laisser à `noSuchMethod`
  // renvoie null, et l'écran plante avant d'avoir joué quoi que ce soit.
  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}

  @override
  void applySettings() {}

  @override
  void noSuchMethod(Invocation invocation) {}
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
  });

  group('En partie en ligne', () {
    testWidgets('le coup reçu de l adversaire sonne', (tester) async {
      final socket = FakeSocket();
      final sons = FauxSons();
      // Les Noirs : c'est donc l'adversaire qui ouvre.
      final game = makeGame(
        socket: socket,
        myCamp: Camp.noir,
        cadence: Cadence.quinze,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: OnlineGameScreen(game: game, myPseudo: 'Nino', sounds: sons),
        ),
      );
      await tester.pump();
      expect(sons.joues, isEmpty);

      socket.emit(FugaEvents.coupAdverse, {'notation': 'Do2-Do3'});
      await tester.pump();

      expect(sons.joues, [
        'Do2-Do3',
      ], reason: 'il arrivait en silence, là où Deep Grey s entend');
    });

    testWidgets('et c est bien SA notation qu on entend', (tester) async {
      // Pas celle d'un autre coup : le son dépend des cases, et un coup joué
      // ailleurs sur le plateau ne fait pas la même musique.
      final socket = FakeSocket();
      final sons = FauxSons();
      final game = makeGame(
        socket: socket,
        myCamp: Camp.noir,
        cadence: Cadence.quinze,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: OnlineGameScreen(game: game, myPseudo: 'Nino', sounds: sons),
        ),
      );
      await tester.pump();
      socket.emit(FugaEvents.coupAdverse, {'notation': 'Sol2-Sol3'});
      await tester.pump();
      expect(sons.joues.single, 'Sol2-Sol3');
    });

    testWidgets('un coup refusé ne fait aucun bruit', (tester) async {
      // Une notation qui ne correspond à rien de légal est ignorée : le
      // plateau ne bouge pas, et rien ne doit s'entendre non plus.
      final socket = FakeSocket();
      final sons = FauxSons();
      final game = makeGame(
        socket: socket,
        myCamp: Camp.noir,
        cadence: Cadence.quinze,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: OnlineGameScreen(game: game, myPseudo: 'Nino', sounds: sons),
        ),
      );
      await tester.pump();
      socket.emit(FugaEvents.coupAdverse, {'notation': 'Si1-Si9'});
      await tester.pump();
      expect(sons.joues, isEmpty);
    });

    testWidgets('un événement sans coup ne sonne pas non plus', (tester) async {
      final socket = FakeSocket();
      final sons = FauxSons();
      final game = makeGame(
        socket: socket,
        myCamp: Camp.noir,
        cadence: Cadence.quinze,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: OnlineGameScreen(game: game, myPseudo: 'Nino', sounds: sons),
        ),
      );
      await tester.pump();
      socket.emit(FugaEvents.adversaireDeconnecte, {'delai': 30});
      await tester.pump();
      expect(sons.joues, isEmpty);
    });
  });

  group('En correspondance', () {
    Map<String, dynamic> partie(String coups) => {
      'id': 'g1',
      'statut': 'en_cours',
      'adversaire': 'Ana',
      'adversaire_melo': 1600,
      'ma_couleur': 'Blanc',
      'turn': 'Noir',
      'my_turn': false,
      'mon_score': 0,
      'score_adverse': 0,
      'objectif': 'partie',
      'moves_text': coups,
      'is_defieur': false,
    };

    /// Ouvre une partie, et rend de quoi la faire bouger.
    Future<({FauxSons sons, void Function(String) joueAdverse})> ouvre(
      WidgetTester tester,
      String coups,
    ) async {
      var courants = coups;
      final sons = FauxSons();
      final client = OnlineClient(
        api: ApiClient(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'ok': true,
                'games': [partie(courants)],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        ),
      );
      clearReplayCache();
      OnlineService.instance = OnlineService();
      await tester.pumpWidget(
        MaterialApp(
          home: CorrGameScreen(
            game: CorrGame.fromJson(partie(courants)),
            service: CorrespondenceService(client),
            myPseudo: 'nino',
            sounds: sons,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (
        sons: sons,
        joueAdverse: (String ajout) {
          courants = courants.isEmpty ? ajout : '$courants\n$ajout';
          clearReplayCache();
          OnlineService.instance.corr.receive({
            'type': 'corr_turn',
            'game_id': 'g1',
          });
        },
      );
    }

    testWidgets('le coup qui arrive pendant qu on regarde sonne', (
      tester,
    ) async {
      final p = await ouvre(tester, 'Do2-Do3');
      p.sons.joues.clear();

      p.joueAdverse('Do7-Do6');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(p.sons.joues, [
        'Do7-Do6',
      ], reason: 'il glissait sous les yeux sans un bruit');
    });

    testWidgets('à l ouverture, le coup qu on avait manqué se rejoue', (
      tester,
    ) async {
      // L'écran l'anime déjà pour qu'on le voie : il doit s'entendre aussi.
      final p = await ouvre(tester, 'Do2-Do3\nDo7-Do6');
      expect(p.sons.joues, ['Do7-Do6']);
    });

    testWidgets('et une relecture sans coup neuf reste muette', (tester) async {
      final p = await ouvre(tester, 'Do2-Do3');
      p.sons.joues.clear();

      // Le serveur redit la même chose : rien de neuf, rien à entendre.
      OnlineService.instance.corr.receive({
        'type': 'corr_turn',
        'game_id': 'g1',
      });
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(p.sons.joues, isEmpty);
    });
  });
}
