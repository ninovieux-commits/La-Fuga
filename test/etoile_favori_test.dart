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
import 'package:lafuga/net/avatar_photos.dart';
import 'package:lafuga/net/profile.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/replay_screen.dart';
import 'package:lafuga/ui/widgets/fuga_header.dart';
import 'package:lafuga/ui/widgets/player_card.dart';
import 'package:lafuga/ui/widgets/player_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    FavorisConnus.instance.oublie();
    AvatarPhotos.clear();
    setScaleSize(const Size(393, 851));
  });
  tearDown(resetScale);

  /// Un service connecté dont `/get_profile` répond ce qu'on lui dit.
  ///
  /// La connexion se fait par le CLIENT et non par le service : celle du
  /// service ouvre en plus une socket, dont le minuteur survit au cas de test
  /// et le fait échouer — sur une machine lente, là où il passait ici.
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
      await s.online.client.login('Nino', 'mdp');
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
      await s.online.client.login('Nino', 'mdp');
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
                clock: '',
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
                clock: '',
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

  group('L étoile de l en-tête', () {
    Future<void> montre(WidgetTester tester, {required bool favori}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FugaHeader(
              back: '< Retour',
              title: 'celia',
              titleSize: 18,
              favori: favori,
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('paraît devant le titre', (tester) async {
      await montre(tester, favori: true);
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(find.textContaining('celia', findRichText: true), findsOneWidget);
    });

    testWidgets('et pas quand il ne l est pas', (tester) async {
      await montre(tester, favori: false);
      expect(find.byIcon(Icons.star), findsNothing);
    });

    testWidgets('elle reste DANS le bandeau', (tester) async {
      // Le bandeau se mesure sur son titre : l'étoile ne doit pas le faire
      // déborder, ni par le haut ni par le bas.
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await montre(tester, favori: true);
      final bandeau = tester.getRect(find.byType(FugaHeader));
      final etoile = tester.getRect(find.byIcon(Icons.star));
      expect(etoile.top, greaterThanOrEqualTo(bandeau.top - 0.5));
      expect(etoile.bottom, lessThanOrEqualTo(bandeau.bottom + 0.5));
    });
  });

  group('L étoile de la fiche', () {
    /// La fiche ouverte sur « celia », sur un serveur qui dit toujours oui.
    Future<void> ouvre(WidgetTester tester, {required bool favori}) async {
      final s = serveur(favori: favori);
      await s.online.client.login('Nino', 'mdp');
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showPlayerCard(
                    context,
                    online: s.online,
                    player: Profile(
                      pseudo: 'celia',
                      isSelf: false,
                      melo: 1449,
                      isFavorite: favori,
                    ),
                    palette: paletteOf('original'),
                  ),
                  child: const Text('ouvrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('paraît devant le pseudo du titre', (tester) async {
      await ouvre(tester, favori: true);
      expect(find.byIcon(Icons.star), findsOneWidget);
      // DANS le titre, et pas ailleurs dans la fiche : le texte qui porte
      // l'étoile est celui qui porte le pseudo. (« celia » paraît aussi plus
      // bas, dans « Moi contre celia : ».)
      final porteur = tester.widget<RichText>(
        find
            .ancestor(
              of: find.byIcon(Icons.star),
              matching: find.byType(RichText),
            )
            .first,
      );
      expect(porteur.text.toPlainText(), contains('celia'));
    });

    testWidgets('et pas quand il ne l est pas', (tester) async {
      await ouvre(tester, favori: false);
      expect(find.byIcon(Icons.star), findsNothing);
    });

    testWidgets('elle SUIT la touche, dans les deux sens', (tester) async {
      // « Retirer » : l'étoile s'éteint sans qu'on referme la fiche.
      await ouvre(tester, favori: true);
      await tester.tap(find.text(T('Retirer')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.star), findsNothing);
      expect(find.text(T('Enregistrer')), findsOneWidget);

      // Et elle se rallume.
      await tester.tap(find.text(T('Enregistrer')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('et la touche prévient les écrans restés dessous', (
      tester,
    ) async {
      // C'est ainsi que l'étoile du bandeau de partie s'allume : le cache est
      // le seul lien entre la fiche et ce qu'il y a derrière elle.
      await ouvre(tester, favori: false);
      expect(FavorisConnus.instance.connu('celia'), isFalse);
      await tester.tap(find.text(T('Enregistrer')));
      await tester.pumpAndSettle();
      expect(FavorisConnus.instance.connu('celia'), isTrue);
    });
  });

  group('Le lecteur de parties', () {
    /// Une partie de l'historique, nino contre mesange.
    const String nmc =
        '[Date "2026-10-14"]\n'
        '[Joueur1 "nino"]\n'
        '[Joueur2 "mesange"]\n'
        '[Blanc "nino"]\n'
        '[Cadence "15"]\n\n'
        '1.Do2-Do3/Do7-Do6';

    Future<List<PlayerPanel>> ouvre(WidgetTester tester) async {
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: ReplayScreen(nmc: nmc)));
      await tester.pumpAndSettle();
      return tester.widgetList<PlayerPanel>(find.byType(PlayerPanel)).toList();
    }

    testWidgets('montre la photo attachée au nom de compte', (tester) async {
      // Nino : « dans l'historique, ce serait bien si ça affichait l'image de
      // profil liée au nom de compte ». Le fichier ne porte que des noms :
      // c'est le cache qui tient les visages.
      AvatarPhotos.remember('nino', 'dragon|Nurse');
      AvatarPhotos.remember('mesange', 'insectes|Ladybug');
      final panneaux = await ouvre(tester);
      expect(panneaux.map((p) => p.photo).toSet(), {
        'dragon|Nurse',
        'insectes|Ladybug',
      });
    });

    testWidgets('et l étoile de celui qui est dans mes favoris', (
      tester,
    ) async {
      FavorisConnus.instance.retiens('mesange', true);
      final panneaux = await ouvre(tester);
      expect(
        {for (final p in panneaux) p.name: p.favori},
        {'nino': false, 'mesange': true},
      );
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('sans rien savoir, aucune étoile et aucune photo', (
      tester,
    ) async {
      final panneaux = await ouvre(tester);
      expect(panneaux.map((p) => p.photo).toSet(), {''});
      expect(find.byIcon(Icons.star), findsNothing);
    });
  });
}
