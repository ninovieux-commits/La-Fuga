/// La revue d'un coup tient, même quand l'adversaire joue.
///
/// Nino : « des fois quand je navigue avec les flèches durant une partie, ça
/// revient seul au dernier coup, il faut réparer ça. »
///
/// C'était la relecture de la partie : son coup arrive, l'écran rejoue tout
/// l'historique pour retrouver la position, et la revue sautait avec. Mesuré
/// avant correction — « APRÈS DEUX FLÈCHES : 0 », puis « APRÈS SON COUP :
/// null », le présent.
///
/// La correspondance n'a pas de pendule, et c'est ce qui décide : son coup
/// peut arriver trois jours plus tard, rien ne presse. L'écran de partie en
/// DIRECT ramène au présent exprès, lui — y rester, c'est perdre au temps en
/// regardant ailleurs — et `fleches_en_ligne_test.dart` le fige.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/corr_game_screen.dart';
import 'package:lafuga/ui/widgets/move_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('son coup ne me ramène pas au présent', (tester) async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    clearReplayCache();

    var coups = 'Do2-Do3\nDo7-Do6\nRe2-Re3';
    final client = OnlineClient(
      api: ApiClient(
        client: MockClient((req) async {
          final jeu = {
            'id': 'g1',
            'statut': 'en_cours',
            'adversaire': 'mesange',
            'ma_couleur': 'Blanc',
            'turn': 'Noir',
            'my_turn': false,
            'moves_text': coups,
            'objectif': 'partie',
          };
          final corps = req.url.path.endsWith('/corr_list')
              ? {
                  'ok': true,
                  'games': [jeu],
                }
              : {'ok': true};
          return http.Response(
            jsonEncode(corps),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CorrGameScreen(
          game: CorrGame.fromJson({
            'id': 'g1',
            'statut': 'en_cours',
            'adversaire': 'mesange',
            'ma_couleur': 'Blanc',
            'turn': 'Noir',
            'my_turn': false,
            'moves_text': coups,
            'objectif': 'partie',
          }),
          service: CorrespondenceService(client),
          myPseudo: 'nino',
        ),
      ),
    );
    await tester.pumpAndSettle();

    int? actif() =>
        tester.widget<MoveStrip>(find.byType(MoveStrip)).activeIndex;
    expect(actif(), isNull, reason: 'on ouvre au présent');

    // Je recule de deux coups avec la flèche gauche.
    final gauche = find.text('<');
    await tester.tap(gauche);
    await tester.pumpAndSettle();
    await tester.tap(gauche);
    await tester.pumpAndSettle();
    expect(actif(), 0);

    // L'adversaire joue. La relecture de sécurité passe.
    coups = 'Do2-Do3\nDo7-Do6\nRe2-Re3\nRe7-Re6';
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(
      actif(),
      0,
      reason: 'je regardais le premier coup : j y suis toujours',
    );

    // Et le coup est bien arrivé : la flèche droite le montre maintenant.
    final droite = find.text('>');
    for (var i = 0; i < 4; i++) {
      await tester.tap(droite);
      await tester.pumpAndSettle();
    }
    expect(actif(), isNull, reason: 'en avançant, on retrouve le présent');
  });
}
