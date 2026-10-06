/// Défier par correspondance : le mode, puis la couleur.
///
/// Nino : « un popup apparaît de la taille de trois boutons : 1) standard
/// 2) random 3) personnalisé. La correspondance ne dépend donc plus de si le
/// menu est en mode Standard ou random. […] Quand on défie en correspondance,
/// à la fin de l'opération, l'app doit afficher le même popup que quand on
/// lance une partie contre Deep Grey, permettant de déterminer si on joue avec
/// les noirs, les blancs ou aléatoire. »
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/fug.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/correspondence.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/corr_mode_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> defis;
  late CorrespondenceService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
    defis = [];
    service = CorrespondenceService(
      OnlineClient(
        api: ApiClient(
          client: MockClient((r) async {
            if (r.url.path == '/corr_defier') {
              defis.add(Map<String, dynamic>.from(jsonDecode(r.body) as Map));
            }
            return http.Response(
              jsonEncode({'ok': true}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      ),
    );
  });
  tearDown(resetScale);

  group('Ce que le défi emporte', () {
    test('standard : aucune position, aucune couleur imposée', () async {
      await service.challenge('celia', 'partie');
      expect(defis.single['mode'], 'standard');
      expect(defis.single['random'], isFalse);
      expect(defis.single.containsKey('position'), isFalse);
      expect(
        defis.single.containsKey('couleur'),
        isFalse,
        reason: 'sans choix, le serveur tire — et personne ne sait avant',
      );
    });

    test('random : le drapeau que le serveur comprend déjà', () async {
      await service.challenge('celia', 'partie', mode: CorrMode.random);
      expect(defis.single['mode'], 'random');
      expect(
        defis.single['random'],
        isTrue,
        reason: 'un serveur pas encore corrigé doit continuer à comprendre',
      );
    });

    test('personnalisé : la position part sur une seule ligne', () async {
      final fug = fugEcrire(Board.initial(), Camp.noir);
      await service.challenge(
        'celia',
        'partie',
        mode: CorrMode.personnalise,
        position: fugEnUneLigne(fug),
        couleur: Camp.noir,
      );
      final envoye = defis.single;
      expect(envoye['mode'], 'personnalise');
      expect(envoye['couleur'], 'Noir');
      expect(
        (envoye['position'] as String).contains('\n'),
        isFalse,
        reason: 'une position doit tenir sur une ligne pour voyager',
      );
      // Et elle se relit à l'identique de l'autre côté.
      final relu = fugLire(fugDepuisUneLigne(envoye['position'] as String));
      expect(relu.erreur, isNull);
      expect(
        relu.position!.board.positionKey(Camp.blanc),
        Board.initial().positionKey(Camp.blanc),
      );
      expect(relu.position!.turn, Camp.noir);
    });

    test('couleur choisie : elle part ; aléatoire : rien ne part', () async {
      await service.challenge('celia', 'partie', couleur: Camp.blanc);
      expect(defis.last['couleur'], 'Blanc');
      await service.challenge('celia', 'partie');
      expect(
        defis.last.containsKey('couleur'),
        isFalse,
        reason: 'aléatoire ne s envoie pas : c est l absence de choix',
      );
    });
  });

  group('Les popups', () {
    Future<T?> ouvrir<T>(
      WidgetTester tester,
      Future<T?> Function(BuildContext) popup,
    ) async {
      T? resultat;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => resultat = await popup(context),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      return resultat;
    }

    testWidgets('le mode offre les trois, et rien d autre', (tester) async {
      await ouvrir<CorrMode>(tester, askCorrMode);
      expect(find.text('Standard'), findsOneWidget);
      expect(find.text('Random'), findsOneWidget);
      expect(find.text('Personnalisé'), findsOneWidget);
    });

    testWidgets('la couleur offre Blancs, Noirs et Aléatoire', (tester) async {
      await ouvrir<({Camp? camp})>(tester, askCorrCouleur);
      expect(find.text('Blancs'), findsOneWidget);
      expect(find.text('Noirs'), findsOneWidget);
      expect(find.text('Aléatoire'), findsOneWidget);
    });

    testWidgets('« Aléatoire » n est pas la même chose que refermer', (
      tester,
    ) async {
      // La distinction compte : l'un lance le défi, l'autre l'annule.
      ({Camp? camp})? choisi;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => choisi = await askCorrCouleur(context),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aléatoire'));
      await tester.pumpAndSettle();
      expect(choisi, isNotNull, reason: 'aléatoire EST un choix');
      expect(choisi!.camp, isNull);
    });
  });

  group('Le mode voyage en texte', () {
    test('aller et retour', () {
      for (final mode in CorrMode.values) {
        expect(CorrMode.fromWire(mode.wire), mode);
      }
    });

    test('un mode inconnu retombe sur standard, sans tomber', () {
      expect(CorrMode.fromWire(''), CorrMode.standard);
      expect(CorrMode.fromWire('n importe quoi'), CorrMode.standard);
    });
  });
}
