/// Les deux popups ont l'allure de boutons, et chacun ses actions.
///
/// Nino, sur le volet des favoris : « je veux des boutons chat, et que le
/// bouton avec les infos joueurs ressemble à des boutons. Ainsi que le bouton
/// fermer. Pourquoi c'est écrit en violet ? »
///
/// Le violet venait de Flutter, pas de La Fuga : `ThemeData(useMaterial3)`
/// sans jeu de couleurs prend la graine d'usine de Material, qui est violette,
/// et toute touche plate la reprend.
///
/// Et sur le menu du nom en partie : « enlève le bouton message. Là aussi je
/// veux que les boutons ressemblent à des boutons. »
///
/// Ce menu-là n'existe plus. Nino : « le popup de l'image 1 doit remplacer
/// celui de l'image 2 […] ainsi il n'y a qu'un seul popup, toujours le
/// même. » La fiche s'ouvre donc aussi en partie — avec le seul pseudo en
/// main, le profil arrivant pendant qu'elle est à l'écran.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/game/defi_relais.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/favoris_connus.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/net/profile.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:lafuga/ui/widgets/player_card.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OnlineService connecte;

  /// Un service connecté dont `/get_profile` dit s'il est déjà favori, et qui
  /// retient les chemins appelés.
  ({OnlineService online, List<String> chemins}) serviceFavori({
    required bool dejaFavori,
  }) {
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
              'is_favorite': dejaFavori,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    return (online: OnlineService(client: client), chemins: chemins);
  }

  OnlineService service({bool ok = true}) => OnlineService(
    client: OnlineClient(
      api: ApiClient(
        client: MockClient(
          (req) async => http.Response(
            jsonEncode(
              ok ? {'ok': true, 'token': 't', 'pseudo': 'Nino'} : {'ok': true},
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      ),
    ),
  );

  // La connexion une fois pour toutes, HORS de tout cas. Elle déclenche du
  // travail asynchrone de paquet qui arme un minuteur, et la vérification de
  // fin de test l'imputerait au premier cas qui s'y connecte alors qu'il n'y
  // est pour rien.
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    connecte = service();
    await connecte.login('Nino', 'mdp');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    // Les favoris connus vivent toute la session : sans ce ménage, un cas
    // hériterait de ce qu'un autre a appris.
    FavorisConnus.instance.oublie();
    DefiRelais.oublie();
  });

  group('La fiche d un joueur', () {
    /// La fiche ouverte sur un autre joueur.
    Future<List<String>> ouvreFiche(
      WidgetTester tester, {
      bool favori = false,
      bool bloque = false,
    }) async {
      // Une vraie taille de téléphone : sur la fenêtre de test par défaut
      // (800 de large), l'échelle double tout et une largeur en pixels ne
      // voudrait rien dire.
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
                'is_favorite': favori,
                'is_blocked': bloque,
                'melo': 1449,
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );
      final online = OnlineService(client: client);
      await online.login('Nino', 'mdp');
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showPlayerCard(
                    context,
                    online: online,
                    player: Profile(
                      pseudo: 'celia',
                      isSelf: false,
                      melo: 1449,
                      isFavorite: favori,
                      isBlocked: bloque,
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
      return chemins;
    }

    testWidgets('ses touches sont LARGES et centrées, pas du texte violet', (
      tester,
    ) async {
      // Nino : « j'aimerai que les boutons bloquer retirer et fermer soient
      // centrés et élargis ».
      await ouvreFiche(tester, favori: true);

      for (final texte in [T('Bloquer'), T('Retirer'), T('Fermer')]) {
        expect(
          find.widgetWithText(FugaButton, texte),
          findsOneWidget,
          reason: '« $texte » doit être une touche',
        );
      }

      // Larges : chacune prend toute la largeur offerte par le popup, et non
      // celle de son texte. On mesure PAR RAPPORT au popup — mesuré : 265
      // sur 393, soit tout le contenu, le popup gardant ses marges. Un seuil
      // en
      // pixels ne prouve rien, l'échelle dépendant de la taille de l'écran.
      final popup = tester.getRect(find.byType(AlertDialog)).width;
      final largeurs = {
        for (final texte in [T('Bloquer'), T('Retirer'), T('Fermer')])
          tester.getRect(find.widgetWithText(FugaButton, texte)).width.round(),
      };
      expect(
        largeurs.length,
        1,
        reason: 'elles doivent toutes faire la même largeur : $largeurs',
      );
      expect(
        largeurs.first / popup,
        greaterThan(0.6),
        reason: 'touches étroites : $largeurs dans un popup de $popup',
      );

      // Centrées : autant de marge à gauche qu'à droite.
      final cadre = tester.getRect(
        find.widgetWithText(FugaButton, T('Fermer')),
      );
      final boite = tester.getRect(find.byType(AlertDialog));
      expect(
        ((cadre.left - boite.left) - (boite.right - cadre.right)).abs(),
        lessThan(2),
        reason: 'la touche doit être centrée dans le popup',
      );
    });

    testWidgets('« Enregistrer » quand il n est pas favori', (tester) async {
      await ouvreFiche(tester);
      expect(find.widgetWithText(FugaButton, T('Enregistrer')), findsOneWidget);
      expect(find.widgetWithText(FugaButton, T('Retirer')), findsNothing);
    });
  });

  group('La fiche ouverte sur un simple nom', () {
    /// La fiche ouverte comme en partie : on n'a que le pseudo.
    Future<void> ouvre(
      WidgetTester tester, {
      String pseudo = 'mesange',
      OnlineService? online,
      bool reglee = true,
    }) async {
      final service = online ?? connecte;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showPlayerCard(
                    context,
                    online: service,
                    pseudo: pseudo,
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
      // Une image : la fiche est là, le profil pas encore.
      await tester.pump();
      if (reglee) await tester.pumpAndSettle();
    }

    testWidgets('sans compte, elle ne s ouvre pas du tout', (tester) async {
      // La garantie d'origine du menu, reprise telle quelle : « elle ne
      // s'ouvre que sur un VRAI joueur et seulement si l'on est connecté ».
      await ouvre(tester, online: service(ok: false));
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('ni sur Deep Grey, qui n est pas un compte', (tester) async {
      await ouvre(tester, pseudo: 'Deep Grey');
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('ni sur « Joueur 1 », qui ne désigne personne', (tester) async {
      await ouvre(tester, pseudo: T('Joueur 1'));
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('elle paraît TOUT DE SUITE, et se remplit ensuite', (
      tester,
    ) async {
      // Attendre le profil pour ouvrir aurait fait un temps mort sous le
      // doigt : on touche un nom, rien ne se passe, puis le popup paraît.
      await ouvre(tester, reglee: false);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('mesange', findRichText: true), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.widgetWithText(FugaButton, T('Bloquer')), findsOneWidget);
    });

    testWidgets('c est bien LA fiche, avec ses mélos et ses scores', (
      tester,
    ) async {
      await ouvre(tester);
      expect(find.textContaining('Mélo'), findsOneWidget);
      expect(find.textContaining(T('En direct')), findsOneWidget);
      expect(find.textContaining(T('Correspondance')), findsOneWidget);
      for (final texte in [T('Profil'), T('Bloquer'), T('Fermer')]) {
        expect(find.widgetWithText(FugaButton, texte), findsOneWidget);
      }
    });

    testWidgets('plus de touche « Message »', (tester) async {
      await ouvre(tester);
      expect(
        find.text(T('Message')),
        findsNothing,
        reason: 'la touche Chat du bandeau du haut fait déjà cela',
      );
    });

    testWidgets('« Fermer » est une touche, pas un texte violet', (
      tester,
    ) async {
      await ouvre(tester);
      expect(find.widgetWithText(FugaButton, T('Fermer')), findsOneWidget);
    });

    testWidgets('« Retirer » quand il est DÉJÀ favori', (tester) async {
      final s = serviceFavori(dejaFavori: true);
      await s.online.client.login('Nino', 'mdp');
      await ouvre(tester, online: s.online);
      expect(find.text(T('Retirer')), findsOneWidget);
      expect(find.text(T('Enregistrer')), findsNothing);
    });

    testWidgets('et la touche FAIT ce qu elle annonce', (tester) async {
      final s = serviceFavori(dejaFavori: true);
      await s.online.client.login('Nino', 'mdp');
      await ouvre(tester, online: s.online);
      s.chemins.clear();
      await tester.tap(find.text(T('Retirer')));
      await tester.pumpAndSettle();
      expect(s.chemins, contains('/remove_favorite'));
      expect(s.chemins, isNot(contains('/add_favorite')));
    });

    testWidgets('sur MON nom, ni Défier ni Favori ni Bloquer', (tester) async {
      // Le serveur de ce test ne renvoie PAS `is_self` : c'est mon pseudo
      // qui le dit, et il suffit.
      await ouvre(tester, pseudo: 'Nino');
      expect(find.widgetWithText(FugaButton, T('Profil')), findsOneWidget);
      for (final texte in [T('Défier'), T('Enregistrer'), T('Bloquer')]) {
        expect(find.text(texte), findsNothing);
      }
    });
  });

  group('La touche « Défier »', () {
    // Elle ne prend plus d'ordre de l'appelant : elle lit LA règle. Nino :
    // « de partout tant qu'une partie en direct n'est pas en cours ».
    Future<void> ouvre(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showPlayerCard(
                    context,
                    online: connecte,
                    pseudo: 'mesange',
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

    final defier = find.widgetWithText(FugaButton, T('Défier'));

    testWidgets('personne pour mener le défi : HACHURÉE', (tester) async {
      DefiRelais.oublie();
      await ouvre(tester);
      expect(tester.widget<FugaButton>(defier).onPressed, isNull);
      expect(find.byKey(kHachuresKey), findsOneWidget);

      // Et elle ne ferme pas la fiche.
      await tester.tap(defier);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('une partie EN DIRECT en cours : hachurée aussi', (
      tester,
    ) async {
      // Nino : « lors d'une partie en direct, ce popup doit avoir la touche
      // défier hachurée en traits noirs et être désactivée. » Même avec
      // quelqu'un pour le mener : on ne joue pas deux parties à la fois.
      DefiRelais.pose((_) async {});
      DefiRelais.enPartieDirecte = true;
      addTearDown(DefiRelais.oublie);
      await ouvre(tester);
      expect(tester.widget<FugaButton>(defier).onPressed, isNull);
      expect(find.byKey(kHachuresKey), findsOneWidget);
    });

    testWidgets('sinon elle est pleine et renvoie le pseudo', (tester) async {
      DefiRelais.pose((_) async {});
      addTearDown(DefiRelais.oublie);
      await ouvre(tester);
      expect(tester.widget<FugaButton>(defier).onPressed, isNotNull);
      expect(
        find.byKey(kHachuresKey),
        findsNothing,
        reason: 'aucune hachure sur une touche en service',
      );

      await tester.tap(defier);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
