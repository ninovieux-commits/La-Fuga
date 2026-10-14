/// L'étoile des favoris, et la touche qui la commande.
///
/// Nino : « le bouton favori doit devenir retirer quand le joueur est favori.
/// Derrière, il doit y avoir une étoile dans les infos de joueur s'il est
/// favori et cette étoile doit disparaître s'il est retiré. Il doit y avoir
/// cette même étoile quand on est sur le profil d'une personne. »
///
/// CE QUI AVAIT ÉCHAPPÉ À MES TESTS. La veille, j'avais fait « Favori » ↔
/// « Retirer » et je l'avais cru vérifié : mes tests simulaient un serveur
/// renvoyant `is_favorite`. Le vrai serveur ne l'a jamais renvoyé, donc la
/// touche disait toujours « Favori ». Je testais contre une fiction.
///
/// D'où les cas ci-dessous sur un serveur MUET : ils fixent ce que l'app fait
/// quand la clé manque, au lieu de supposer qu'elle est là.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/favoris_connus.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/widgets/player_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // La toute première connexion d'un fichier arme un minuteur que la
  // vérification de fin de test signale, et qui ne vient pas de notre code.
  // On la fait ici, hors de tout cas.
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    final amorce = OnlineService(
      client: OnlineClient(
        api: ApiClient(
          client: MockClient(
            (req) async => http.Response(
              jsonEncode({'ok': true, 'token': 't', 'pseudo': 'Nino'}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        ),
      ),
    );
    await amorce.login('Nino', 'mdp');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    FavorisConnus.instance.oublie();
  });

  /// Un service connecté dont `/get_profile` répond ce qu'on lui dit.
  ///
  /// `favori: null` imite un serveur pas encore corrigé : la clé est ABSENTE.
  ({OnlineService online, List<String> chemins}) serveur({bool? favori}) {
    final chemins = <String>[];
    final client = OnlineClient(
      api: ApiClient(
        client: MockClient((req) async {
          chemins.add(req.url.path);
          return http.Response(
            jsonEncode({
              'ok': true,
              'token': 't',
              'pseudo': 'Nino',
              'is_self': false,
              if (favori != null) 'is_favorite': favori,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    return (online: OnlineService(client: client), chemins: chemins);
  }

  group('Le cache des favoris', () {
    test('ne sait rien avant d avoir demandé', () {
      expect(FavorisConnus.instance.connu('celia'), isNull);
    });

    test('retient, et la casse du pseudo ne compte pas', () {
      FavorisConnus.instance.retiens('Celia', true);
      expect(FavorisConnus.instance.connu('celia'), isTrue);
      FavorisConnus.instance.retiens('celia', false);
      expect(FavorisConnus.instance.connu('Celia'), isFalse);
    });

    test('prévient quand ça change, et se tait sinon', () {
      var avis = 0;
      void compte() => avis++;
      FavorisConnus.instance.addListener(compte);
      FavorisConnus.instance.retiens('celia', true);
      expect(avis, 1);
      FavorisConnus.instance.retiens('celia', true);
      expect(avis, 1, reason: 'la même réponse ne redessine rien');
      FavorisConnus.instance.retiens('celia', false);
      expect(avis, 2);
      FavorisConnus.instance.removeListener(compte);
    });

    testWidgets('un serveur MUET sur la clé donne « pas favori »', (
      tester,
    ) async {
      // Le défaut que j'avais manqué : la clé absente doit valoir faux, et ne
      // doit pas faire redemander sans fin.
      final s = serveur(favori: null);
      await s.online.login('Nino', 'mdp');
      expect(
        await FavorisConnus.instance.demande('celia', online: s.online),
        isFalse,
      );
      s.chemins.clear();
      expect(
        await FavorisConnus.instance.demande('celia', online: s.online),
        isFalse,
      );
      expect(
        s.chemins,
        isNot(contains('/get_profile')),
        reason: 'la question ne se repose pas à chaque écran',
      );
    });

    testWidgets('un serveur qui répond VRAI est cru', (tester) async {
      final s = serveur(favori: true);
      await s.online.login('Nino', 'mdp');
      expect(
        await FavorisConnus.instance.demande('celia', online: s.online),
        isTrue,
      );
      expect(FavorisConnus.instance.connu('celia'), isTrue);
    });
  });

  group('L étoile du bandeau', () {
    Future<void> montre(WidgetTester tester, {required bool favori}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 120,
              child: PlayerPanel(
                name: 'celia',
                clock: '∞',
                palette: paletteOf('original'),
                isWhite: true,
                isTurn: false,
                captures: const [],
                favori: favori,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('paraît quand il est favori', (tester) async {
      await montre(tester, favori: true);
      expect(find.byIcon(Icons.star), findsOneWidget);
      // L'étoile est un FRAGMENT du texte : la chaîne complète porte en plus
      // son caractère de remplacement, d'où la recherche par contenu.
      expect(find.textContaining('celia', findRichText: true), findsOneWidget);
    });

    testWidgets('et pas quand il ne l est pas', (tester) async {
      await montre(tester, favori: false);
      expect(find.byIcon(Icons.star), findsNothing);
      expect(find.textContaining('celia', findRichText: true), findsOneWidget);
    });

    testWidgets('un pseudo long ne la fait pas disparaître', (tester) async {
      // Elle se range AVANT le nom : le `ellipsis` du nom ne doit pas la
      // manger.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 120,
              child: PlayerPanel(
                name: 'un pseudo vraiment très long qui déborde largement',
                clock: '∞',
                palette: paletteOf('original'),
                isWhite: true,
                isTurn: false,
                captures: const [],
                favori: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.star), findsOneWidget);
    });
  });
}
