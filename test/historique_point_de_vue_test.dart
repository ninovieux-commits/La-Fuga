/// Qui a gagné, dans un historique qu'on regarde ?
///
/// Nino : « quand je vais sur le profil de mesange et que j'accède à son
/// historique, les parties affichent qu'elle a gagné. Peut-être que c'est
/// affiché de mon point de vue, mais du coup qui est-ce que ça considère
/// comme gagnant si je regarde une partie qu'elle a faite contre quelqu'un
/// d'autre ? »
///
/// C'était le PREMIER JOUEUR, donc les Blancs : dès que je n'étais pas dans
/// la partie, le vert disait « les Blancs ont gagné » sans que rien ne le
/// dise. Le point de vue est maintenant celui du joueur DONT ON LIT
/// l'historique, et gris quand il n'est pas dans la partie.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/history_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_realtime.dart';

const Color _vert = Color.fromRGBO(77, 217, 77, 1);
const Color _rouge = Color.fromRGBO(255, 84, 84, 1);
const Color _gris = Color.fromRGBO(191, 191, 191, 1);

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

  /// Une partie telle que `/list_games` la rend. `joueur1` tient les Blancs.
  Map<String, dynamic> partie({
    required String joueur1,
    required String joueur2,
    required String resultat,
  }) => {
    'game_uid': 'online_g1',
    'joueur1': joueur1,
    'joueur2': joueur2,
    'resultat': resultat,
    'methode': 'fugue',
    'date': '2026-10-24 13:36',
  };

  /// Ouvre l'historique en ligne de [target] — nul : le mien.
  Future<void> ouvrir(
    WidgetTester tester,
    Map<String, dynamic> jeu, {
    String? target,
  }) async {
    final online = OnlineService(
      client: OnlineClient(
        api: ApiClient(
          client: MockClient(
            (request) async => http.Response(
              jsonEncode({
                'ok': true,
                // La session retient le pseudo que le serveur lui rend :
                // sans lui, l'appli ne sait pas qui elle est.
                'pseudo': 'nino',
                'games': [jeu],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        ),
      ),
      socketFactory: (_) => FakeRealtime(),
    );
    await online.login('nino', 'mdp');
    await tester.pumpWidget(
      MaterialApp(
        home: HistoryScreen(online: online, target: target),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// La couleur du symbole de résultat.
  Color couleur(WidgetTester tester) =>
      tester.widget<Text>(find.text('*')).style!.color!;

  testWidgets('mon historique : vert quand c est MOI qui ai gagné', (
    tester,
  ) async {
    await ouvrir(
      tester,
      partie(joueur1: 'mesange', joueur2: 'nino', resultat: '0-1'),
    );
    expect(couleur(tester), _vert);
  });

  testWidgets('mon historique : rouge quand j ai perdu', (tester) async {
    await ouvrir(
      tester,
      partie(joueur1: 'mesange', joueur2: 'nino', resultat: '1-0'),
    );
    expect(couleur(tester), _rouge);
  });

  testWidgets('son historique : le point de vue est le SIEN', (tester) async {
    // La même partie, vue depuis le profil de mesange : elle a gagné.
    await ouvrir(
      tester,
      partie(joueur1: 'mesange', joueur2: 'nino', resultat: '1-0'),
      target: 'mesange',
    );
    expect(couleur(tester), _vert);
  });

  testWidgets('son historique, contre un tiers, et elle est SECONDE', (
    tester,
  ) async {
    await ouvrir(
      tester,
      partie(joueur1: 'lilou', joueur2: 'mesange', resultat: '0-1'),
      target: 'mesange',
    );
    expect(
      couleur(tester),
      _vert,
      reason: 'le premier joueur tient les Blancs : « 0-1 » la fait gagner',
    );
  });

  testWidgets('la casse du pseudo ne compte pas', (tester) async {
    await ouvrir(
      tester,
      partie(joueur1: 'Mesange', joueur2: 'lilou', resultat: '1-0'),
      target: 'mesange',
    );
    expect(couleur(tester), _vert);
  });

  testWidgets('personne de connu dans la partie : le symbole reste gris', (
    tester,
  ) async {
    // Sans cible, c'est mon point de vue — et je n'y suis pas. Le vert
    // disait alors « les Blancs ont gagné », ce que personne ne demandait.
    await ouvrir(
      tester,
      partie(joueur1: 'lilou', joueur2: 'celia', resultat: '1-0'),
    );
    expect(couleur(tester), _gris);
  });
}
