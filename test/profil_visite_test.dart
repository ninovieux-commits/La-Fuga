/// Le profil, refait d'après le dessin de Nino.
///
/// « Le profil de quelqu'un doit ressembler à ça quand on le visite […] la
/// partie du haut (photo pseudo étoile devise) doit avoir comme fond la partie
/// correspondante du fond du menu choisi par la personne. Le pseudo doit
/// occuper l'espace (plus grand si pseudo court). La devise doit être dans une
/// bulle qui pointe vers l'image de profil à gauche (comme dans les chats). »
///
/// Et : « le profil perso et le profil d'autrui doivent être construits de la
/// même façon et avec les mêmes proportions. »
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
import 'package:lafuga/theme/theme_assets.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/account_screen.dart';
import 'package:lafuga/ui/screens/corr_game_screen.dart';
import 'package:lafuga/ui/widgets/bulle_devise.dart';
import 'package:lafuga/ui/widgets/corr_slot.dart';
import 'package:lafuga/ui/widgets/fuga_background.dart';
import 'package:lafuga/ui/widgets/entete_profil.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:lafuga/ui/widgets/texte_remplissant.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mon thème, et celui de la personne visitée : deux décors distincts.
const String kMonTheme = 'medieval';
const String kSonTheme = 'insectes';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<({String path, Map<String, dynamic> body})> appels;
  late Map<String, Map<String, dynamic>> reponses;
  late OnlineService online;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Settings.instance.setTheme(kMonTheme);
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
    FavorisConnus.instance.oublie();

    appels = [];
    reponses = {};
    online = OnlineService(
      client: OnlineClient(
        api: ApiClient(
          client: MockClient((req) async {
            appels.add((
              path: req.url.path,
              body: Map<String, dynamic>.from(jsonDecode(req.body) as Map),
            ));
            return http.Response(
              jsonEncode(reponses[req.url.path] ?? {'ok': true}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      ),
    );
  });
  tearDown(resetScale);

  Map<String, dynamic> profil({
    bool moi = false,
    String pseudo = 'mesange',
    String devise = 'Je joue vite et mal.',
    String theme = kSonTheme,
    List<Map<String, dynamic>> suiveurs = const [
      {'pseudo': 'celia', 'melo': 1449, 'online': true},
    ],
  }) => {
    'ok': true,
    'pseudo': pseudo,
    'is_self': moi,
    'melo': 1530,
    'melo_random': 1500,
    'photo': 'dragon|Nurse',
    'theme': theme,
    'description': devise,
    'followers': suiveurs,
    'following': const [],
    'blocked': const [],
    'h2h_direct_moi': 8,
    'h2h_direct_lui': 8,
  };

  Future<void> ouvrir(WidgetTester tester, {String? pseudo = 'mesange'}) async {
    // La fiche d'un joueur ne s'ouvre que connecté — et par le CLIENT, dont
    // la connexion n'ouvre pas de socket.
    await online.client.login('nino', 'mdp');
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: AccountScreen(online: online, pseudo: pseudo),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Un texte qui occupe sa place', () {
    /// La taille réellement choisie pour ce texte, dans cette boîte.
    Future<double> taille(
      WidgetTester tester,
      String texte, {
      double largeur = 200,
      double hauteur = 40,
      int lignes = 1,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: largeur,
                height: hauteur,
                child: TexteRemplissant(
                  texte,
                  style: const TextStyle(color: Colors.white),
                  tailleMin: 10,
                  tailleMax: 40,
                  maxLignes: lignes,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.widget<Text>(find.text(texte)).style!.fontSize!;
    }

    testWidgets('un mot court est écrit PLUS GROS qu un long', (tester) async {
      final court = await taille(tester, 'Jo');
      final long = await taille(tester, 'un pseudo vraiment interminable');
      expect(
        court,
        greaterThan(long),
        reason: 'le court doit occuper la place que le long n a pas',
      );
      expect(court, lessThanOrEqualTo(40));
      expect(long, greaterThanOrEqualTo(10));
    });

    testWidgets('et il ne déborde jamais de sa boîte', (tester) async {
      await taille(tester, 'un pseudo vraiment interminable, et même plus');
      final boite = tester.getSize(find.byType(TexteRemplissant));
      final rendu = tester.getSize(find.byType(Text).first);
      expect(rendu.width, lessThanOrEqualTo(boite.width + 0.5));
      expect(rendu.height, lessThanOrEqualTo(boite.height + 0.5));
    });

    testWidgets('trois lignes tiennent dans la hauteur donnée', (tester) async {
      await taille(
        tester,
        'une devise un peu longue qui tient sur plusieurs lignes',
        hauteur: 70,
        lignes: 3,
      );
      final boite = tester.getSize(find.byType(TexteRemplissant));
      final rendu = tester.getSize(find.byType(Text).first);
      expect(rendu.height, lessThanOrEqualTo(boite.height + 0.5));
    });
  });

  group('Le bandeau du haut', () {
    /// Le fond du bandeau : la seule boîte décorée d'une IMAGE qu'il
    /// contienne. La chercher par sa position dans l'arbre attrapait le
    /// crayon, qui est décoré lui aussi.
    final fondDuBandeau = find.descendant(
      of: find.byType(EnteteProfil),
      matching: find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox && (w.decoration as BoxDecoration).image != null,
      ),
    );

    testWidgets('porte SON décor, pas le mien', (tester) async {
      reponses['/get_profile'] = profil();
      await ouvrir(tester);

      final fond = tester.widget<DecoratedBox>(fondDuBandeau);
      final image = (fond.decoration as BoxDecoration).image!.image;
      expect(
        (image as AssetImage).assetName,
        imagesFor(kSonTheme)!.background,
        reason: 'on entre chez lui : c est son fond de menu',
      );
      expect((image).assetName, isNot(imagesFor(kMonTheme)!.background));
    });

    testWidgets('en montre la TRANCHE du haut, pas l image écrasée', (
      tester,
    ) async {
      // « La partie correspondante du fond du menu » : l'image est dessinée à
      // la taille de l'écran et coupée à la hauteur du bandeau.
      reponses['/get_profile'] = profil();
      await ouvrir(tester);

      final bandeau = tester.getSize(find.byType(EnteteProfil));
      final peint = tester.getSize(fondDuBandeau);
      expect(
        peint.height,
        851,
        reason: 'l image est posée en plein écran, puis coupée',
      );
      expect(bandeau.height, lessThan(peint.height));
    });

    testWidgets(
      'la devise est dans une bulle qui laisse la place à sa pointe',
      (tester) async {
        reponses['/get_profile'] = profil();
        await ouvrir(tester);

        final bulle = tester.getRect(find.byType(BulleDevise));
        final texte = tester.getRect(find.text('Je joue vite et mal.'));
        expect(
          texte.left - bulle.left,
          greaterThan(S(9)),
          reason: 'la pointe sort à gauche : le texte ne vient pas dessus',
        );
        // Et la pointe regarde la photo, qui est à sa gauche.
        final photo = tester.getRect(find.byType(EnteteProfil));
        expect(bulle.left, greaterThan(photo.left));
      },
    );

    testWidgets('les mélos sont SOUS le pseudo', (tester) async {
      reponses['/get_profile'] = profil();
      await ouvrir(tester);

      final melos = find.textContaining('1530');
      expect(melos, findsOneWidget);
      expect(find.textContaining('1500'), findsOneWidget);

      final nom = tester.getRect(find.text('mesange'));
      final classement = tester.getRect(melos);
      expect(
        classement.top,
        greaterThanOrEqualTo(nom.bottom - 1),
        reason: 'sous le pseudo, pas à côté',
      );
      // Et au-dessus de la devise : pseudo, mélos, devise.
      expect(
        classement.bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(BulleDevise)).top + 1),
      );
    });

    testWidgets('l étoile paraît sur le profil d un favori', (tester) async {
      FavorisConnus.instance.retiens('mesange', true);
      reponses['/get_profile'] = profil()..['is_favorite'] = true;
      await ouvrir(tester);
      expect(find.byIcon(Icons.star), findsOneWidget);
    });
  });

  group('Tout est monté selon SON thème', () {
    // Nino : « quand on va sur le profil d'une personne, tout doit être monté
    // selon le thème choisi par la personne. »

    testWidgets('le fond de la page est le SIEN', (tester) async {
      reponses['/get_profile'] = profil();
      await ouvrir(tester);

      final fond = tester.widget<FugaBackground>(
        find.byType(FugaBackground).first,
      );
      expect(fond.theme, kSonTheme);
      expect(fond.theme, isNot(kMonTheme));
    });

    testWidgets('et les touches portent SES couleurs', (tester) async {
      reponses['/get_profile'] = profil();
      await ouvrir(tester);

      final retour = tester.widget<FugaButton>(
        find.widgetWithText(FugaButton, T('Revenir au menu')),
      );
      expect(retour.color, paletteOf(kSonTheme).clair);
      expect(
        retour.color,
        isNot(paletteOf(kMonTheme).clair),
        reason: 'ce ne sont pas les miennes',
      );
    });

    testWidgets('sur MON profil, ce sont les miennes', (tester) async {
      reponses['/get_profile'] = profil(
        moi: true,
        pseudo: 'nino',
        theme: kMonTheme,
      );
      await ouvrir(tester, pseudo: null);

      final retour = tester.widget<FugaButton>(
        find.widgetWithText(FugaButton, T('Revenir au menu')),
      );
      expect(retour.color, paletteOf(kMonTheme).clair);
    });
  });

  group('Les parties d un autre, en visiteur', () {
    /// Une partie en cours de `mesange` contre `celia`, telle que la route
    /// publique la rend : du point de vue de mesange.
    Map<String, dynamic> sonJeu({bool aLui = true}) => {
      'ok': true,
      'games': [
        {
          'id': 7,
          'statut': 'en_cours',
          'ma_couleur': 'Blanc',
          'adversaire': 'celia',
          'adversaire_melo': 1449,
          'mon_score': 3,
          'score_adverse': 1,
          'objectif': 'partie',
          'turn': aLui ? 'Blanc' : 'Noir',
          'moves_text': '',
          'my_turn': aLui,
        },
      ],
    };

    testWidgets('l aperçu porte les DEUX noms', (tester) async {
      // Chez moi, le nom de l'adversaire suffit — l'autre, c'est moi. Sur le
      // profil de quelqu'un, il en faut deux.
      reponses['/get_profile'] = profil();
      reponses['/corr_list_public'] = sonJeu();
      await ouvrir(tester);

      expect(find.byType(CorrSlot), findsOneWidget);
      final case_ = tester.widget<CorrSlot>(find.byType(CorrSlot));
      expect(case_.proprietaire, 'mesange');
      expect(find.textContaining('mesange — celia'), findsOneWidget);
    });

    testWidgets('et dit LEQUEL des deux doit jouer', (tester) async {
      reponses['/get_profile'] = profil();
      reponses['/corr_list_public'] = sonJeu();
      await ouvrir(tester);
      expect(find.textContaining('À mesange de jouer'), findsOneWidget);
      expect(
        find.textContaining('À vous de jouer'),
        findsNothing,
        reason: 'ce n est pas à moi de jouer : je regarde',
      );
    });

    testWidgets('quand c est à son adversaire, c est lui qu on nomme', (
      tester,
    ) async {
      reponses['/get_profile'] = profil();
      reponses['/corr_list_public'] = sonJeu(aLui: false);
      await ouvrir(tester);
      expect(find.textContaining('À celia de jouer'), findsOneWidget);
    });

    testWidgets('la toucher ouvre la partie en VISITEUR', (tester) async {
      // Nino : « donner sur la partie de la personne en mode visiteur (ne
      // peut pas intervenir ni voir la boîte de message) ».
      reponses['/get_profile'] = profil();
      reponses['/corr_list_public'] = sonJeu();
      await ouvrir(tester);

      await tester.tap(find.byType(CorrSlot));
      await tester.pumpAndSettle();

      final ecran = tester.widget<CorrGameScreen>(find.byType(CorrGameScreen));
      expect(ecran.visiteur, isTrue);
      expect(
        ecran.myPseudo,
        'mesange',
        reason: 'la partie est rendue de SON point de vue, son nom en bas',
      );
      expect(
        find.text('Chat'),
        findsNothing,
        reason: 'sa conversation avec son adversaire ne nous regarde pas',
      );
      expect(find.text('½'), findsNothing);
      expect(find.text('X'), findsNothing);
    });

    testWidgets('sur MON profil, rien de tout cela', (tester) async {
      reponses['/get_profile'] = profil(moi: true, pseudo: 'nino');
      reponses['/corr_list'] = sonJeu();
      await ouvrir(tester, pseudo: null);

      final case_ = tester.widget<CorrSlot>(find.byType(CorrSlot));
      expect(case_.proprietaire, '');
      await tester.tap(find.byType(CorrSlot));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CorrGameScreen>(find.byType(CorrGameScreen)).visiteur,
        isFalse,
      );
    });
  });

  group('Les sections du dessin', () {
    testWidgets('« Moi contre » paraît sur le profil d un autre', (
      tester,
    ) async {
      reponses['/get_profile'] = profil();
      await ouvrir(tester);
      expect(find.text('Moi contre :'), findsOneWidget);
      expect(find.textContaining('8/8'), findsWidgets);
    });

    testWidgets('et pas sur le mien', (tester) async {
      reponses['/get_profile'] = profil(moi: true, pseudo: 'nino');
      await ouvrir(tester, pseudo: null);
      expect(find.text('Moi contre :'), findsNothing);
    });

    testWidgets('« Parties » dit qu il n y en a pas', (tester) async {
      reponses['/get_profile'] = profil();
      await ouvrir(tester);
      expect(find.text('Parties :'), findsOneWidget);
      expect(find.text('Pas de partie en cours'), findsOneWidget);
    });

    testWidgets('et montre les aperçus quand il y en a', (tester) async {
      reponses['/get_profile'] = profil(moi: true, pseudo: 'nino');
      reponses['/corr_list'] = {
        'ok': true,
        'games': [
          {
            'id': 'g1',
            'statut': 'en_cours',
            'adversaire': 'celia',
            'adversaire_melo': 1449,
            'ma_couleur': 'Blanc',
            'turn': 'Blanc',
            'my_turn': true,
            'moves_text': '',
            'objectif': 'partie',
          },
        ],
      };
      await ouvrir(tester, pseudo: null);

      expect(find.text('Pas de partie en cours'), findsNothing);
      expect(find.byType(CorrSlot), findsOneWidget);
      // La MÊME grille qu'au menu : deux colonnes à la forme du plateau.
      final grille = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          grille.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 2);
      expect(delegate.childAspectRatio, 7 / 8);
    });

    testWidgets('les noms suivis sont des TOUCHES qui ouvrent la fiche', (
      tester,
    ) async {
      // Nino : « les noms des "le suivent" et "suivis" doivent être des
      // boutons cliquables affichant le popup qu'on a branché partout. »
      reponses['/get_profile'] = profil();
      await ouvrir(tester);

      final nom = find.widgetWithText(FugaButton, 'celia   1449');
      expect(nom, findsOneWidget);
      await tester.ensureVisible(nom);
      await tester.pumpAndSettle();
      await tester.tap(nom);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FugaButton, T('Bloquer')),
        ),
        findsOneWidget,
        reason: 'celui de la FICHE — le profil a le sien, derrière',
      );
    });

    testWidgets('« Favori » et « Bloquer » sont sous les deux historiques', (
      tester,
    ) async {
      reponses['/get_profile'] = profil();
      await ouvrir(tester);

      final favori = find.widgetWithText(FugaButton, T('Favori'));
      final bloquer = find.widgetWithText(FugaButton, T('Bloquer'));
      final histoire = find.widgetWithText(FugaButton, T('Historique local'));
      await tester.scrollUntilVisible(
        bloquer,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(favori, findsOneWidget);
      expect(bloquer, findsOneWidget);
      expect(
        tester.getRect(favori).top,
        greaterThan(tester.getRect(histoire).top),
        reason: 'entre les historiques et « Revenir au menu »',
      );
      expect(
        tester.getRect(favori).top,
        lessThan(tester.getRect(find.text(T('Revenir au menu'))).top),
      );
    });

    testWidgets('et pas sur mon propre profil', (tester) async {
      reponses['/get_profile'] = profil(moi: true, pseudo: 'nino');
      await ouvrir(tester, pseudo: null);
      expect(find.widgetWithText(FugaButton, T('Favori')), findsNothing);
      expect(find.widgetWithText(FugaButton, T('Bloquer')), findsNothing);
    });
  });
}
