/// Copier le .nmc d'une partie depuis l'historique — local ET en ligne.
///
/// Un test vérifiait déjà que la touche « Copier » s'affiche, mais il ne la
/// pressait jamais : la copie elle-même n'était pas éprouvée. Et elle
/// n'existait pas du tout sur l'historique en ligne, où le fichier n'est pas
/// sur le téléphone mais chez le serveur.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/nmc.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/local_games.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/history_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Map<String, Object> _launched = {'lang_chosen': true, 'tuto_seen': true};

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

List<String> _quelquesCoups(int nombre) {
  var board = Board.initial();
  var camp = Camp.blanc;
  final coups = <String>[];
  for (var i = 0; i < nombre; i++) {
    final legaux = generateMoves(
      board,
      camp,
    ).where((m) => !m.fugue && m.matOn == null && m.fugueBy == null).toList();
    final coup = legaux[i % legaux.length];
    coups.add(notationOn(board, coup));
    board = coup.board;
    camp = camp.opposite;
  }
  return coups;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dossier;
  late LocalGamesStore magasin;

  /// Ce que l'application a posé dans le presse-papiers.
  String? copie;

  setUp(() async {
    SharedPreferences.setMockInitialValues(_launched);
    await Settings.load();
    await Translations.load('fr');
    dossier = Directory.systemTemp.createTempSync('lafuga_copie');
    magasin = LocalGamesStore(directory: dossier);
    copie = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copie = '${(call.arguments as Map)['text']}';
        }
        return null;
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    dossier.deleteSync(recursive: true);
  });

  testWidgets('une partie de l appareil se copie telle quelle', (tester) async {
    final fichier = await magasin.save(
      _meta,
      _quelquesCoups(4),
      name: 'partie1',
    );
    final attendu = fichier.readAsStringSync();
    expect(attendu, contains('Nino'), reason: 'le fichier écrit est vide ?');

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryScreen(
          online: OnlineService.instance,
          mode: HistoryMode.local,
          store: magasin,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Copier'));
    await tester.pumpAndSettle();

    expect(
      copie,
      attendu,
      reason: 'le presse-papiers ne contient pas le .nmc du fichier',
    );
    // Kivy montre aussi le contenu, pour pouvoir le sélectionner à la main.
    expect(find.text('Contenu .nmc'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('CONNECTÉ, l onglet « En local » offre aussi la copie', (
    tester,
  ) async {
    // Le piège : `_fromServer` vaut vrai dès qu'on est CONNECTÉ, y compris en
    // mode local. Les deux onglets passent alors par la même ligne, celle des
    // parties du serveur — et c'est là que la touche manquait. Un joueur
    // connecté, c'est-à-dire tout le monde, ne la voyait donc jamais, dans
    // aucun onglet. Le test qui existait ouvrait l'écran DÉCONNECTÉ : il
    // vérifiait un chemin que personne n'emprunte.
    const nmcServeur = '[Date "2026-09-26"]\n[Blanc "nino"]\n1. Dc3 Df6\n';
    final service = OnlineService(
      client: OnlineClient(
        api: ApiClient(
          client: MockClient((request) async {
            final corps = switch (request.url.path) {
              '/login' => {
                'ok': true,
                'token': 't',
                'pseudo': 'nino',
                'melo': 1600,
              },
              '/list_games' => {
                'ok': true,
                'games': [
                  {
                    'game_uid': 'local_7',
                    'joueur1': 'nino',
                    'joueur2': 'deep grey',
                    'resultat': '1-0',
                    'methode': 'fugue',
                    'cadence': 'zen',
                    'objectif': 'partie',
                    'played_at': '1790000000',
                  },
                ],
              },
              '/get_game' => {'ok': true, 'nmc_text': nmcServeur},
              _ => {'ok': true},
            };
            return http.Response(
              jsonEncode(corps),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      ),
    );
    await tester.runAsync(() => service.login('nino', 'mdp'));

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryScreen(
          online: service,
          mode: HistoryMode.local,
          store: magasin,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('deep grey'),
      findsWidgets,
      reason: 'la partie locale du serveur ne s affiche pas : test sans valeur',
    );
    expect(
      find.text('Copier'),
      findsOneWidget,
      reason:
          'connecté, l onglet En local n offre pas de quoi copier le .nmc '
          '— c est exactement ce que voit le joueur',
    );

    await tester.tap(find.text('Copier'));
    await tester.pumpAndSettle();

    expect(copie, nmcServeur);
  });

  testWidgets('une partie EN LIGNE se copie aussi, depuis le serveur', (
    tester,
  ) async {
    const nmcServeur = '[Date "2026-09-20"]\n[Blanc "Nino"]\n1. Dc3 Df6\n';
    final service = OnlineService(
      client: OnlineClient(
        api: ApiClient(
          client: MockClient((request) async {
            final corps = switch (request.url.path) {
              '/login' => {
                'ok': true,
                'token': 't',
                'pseudo': 'Nino',
                'melo': 1600,
              },
              '/list_games' => {
                'ok': true,
                'games': [
                  {
                    'game_uid': 'online_42',
                    'joueur1': 'Nino',
                    'joueur2': 'Ana',
                    'resultat': '1-0',
                    'methode': 'fugue',
                    'cadence': '5',
                    'objectif': 'partie',
                    'played_at': '1790000000',
                  },
                ],
              },
              '/get_game' => {'ok': true, 'nmc_text': nmcServeur},
              _ => {'ok': true},
            };
            return http.Response(
              jsonEncode(corps),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      ),
    );
    // Hors du temps simulé : la connexion pose un minuteur que le cadre de
    // test compterait comme resté en suspens.
    await tester.runAsync(() => service.login('Nino', 'mdp'));

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryScreen(
          online: service,
          mode: HistoryMode.online,
          store: magasin,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Ana'),
      findsWidgets,
      reason: 'la partie en ligne ne s affiche pas : test sans valeur',
    );
    expect(
      find.text('Copier'),
      findsOneWidget,
      reason: 'l historique en ligne n offre pas de quoi copier le .nmc',
    );

    await tester.tap(find.text('Copier'));
    await tester.pumpAndSettle();

    expect(copie, nmcServeur, reason: 'le .nmc du serveur n a pas été copié');
    expect(find.text('Contenu .nmc'), findsOneWidget);
  });
}
