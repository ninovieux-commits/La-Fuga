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
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/account_screen.dart';
import 'package:lafuga/ui/screens/corr_game_screen.dart';
import 'package:lafuga/ui/widgets/bulle_devise.dart';
import 'package:lafuga/ui/widgets/corr_slot.dart';
import 'package:lafuga/ui/widgets/fuga_background.dart';
import 'package:lafuga/ui/widgets/entete_profil.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:lafuga/ui/widgets/game_layout.dart';
import 'package:lafuga/ui/widgets/profile_photo.dart';
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

    testWidgets('une boîte trop courte le fait RÉTRÉCIR, pas déborder', (
      tester,
    ) async {
      // `tailleMin` dit « en deçà, ça ne se lit plus ». Quand la boîte est
      // plus courte que ça, il reste à choisir entre un texte un peu trop
      // petit et un texte tranché en plein milieu : on prend le petit.
      // C'est ce qui arrivait à la ligne des mélos du profil, et le texte
      // sortait coupé en deux.
      //
      // On mesure le TEXTE, pas sa boîte : un parent trop court rabote la
      // boîte du `Text` à sa propre hauteur, si bien que comparer les deux
      // boîtes ne montre jamais rien — les lettres, elles, dépassent.
      await taille(tester, 'Mélo : 1530', hauteur: 8);
      final rendu = tester.widget<Text>(find.byType(Text).first);
      final peintre = TextPainter(
        text: TextSpan(text: rendu.data, style: rendu.style),
        maxLines: rendu.maxLines,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 200);
      expect(
        peintre.height,
        lessThanOrEqualTo(8.5),
        reason:
            'le texte occupe ${peintre.height.toStringAsFixed(1)} dans une '
            'boîte de 8 : il sera coupé',
      );
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
    /// Une boîte décorée d'une IMAGE à l'intérieur du bandeau : il ne doit
    /// plus y en avoir.
    final fondDuBandeau = find.descendant(
      of: find.byType(EnteteProfil),
      matching: find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox && (w.decoration as BoxDecoration).image != null,
      ),
    );

    testWidgets('n a PLUS de fond à lui : c est celui de la page', (
      tester,
    ) async {
      // Nino : « la partie du haut ne doit pas avoir une partie de fond
      // séparée : on met carrément le fond de menu choisi par la personne en
      // fond de son profil. » Le bandeau portait une TRANCHE de cette image,
      // découpée à sa hauteur : deux cadrages de la même image se touchaient
      // au milieu de l'écran, et la couture se voyait.
      reponses['/get_profile'] = profil();
      await ouvrir(tester);

      expect(
        fondDuBandeau,
        findsNothing,
        reason: 'une image dans le bandeau, c est la couture qui revient',
      );
      // Et la page, elle, porte bien SON décor d'un bord à l'autre.
      final fond = tester.widget<FugaBackground>(
        find.byType(FugaBackground).first,
      );
      expect(fond.theme, kSonTheme);
    });

    testWidgets('la photo mesure LE TIERS de la largeur', (tester) async {
      // Nino, schéma à l'appui : « l'emplacement image mesure 1/3 de la
      // largeur de l'écran. »
      reponses['/get_profile'] = profil();
      await ouvrir(tester);

      final photo = tester.getRect(find.byType(ProfilePhoto).first);
      expect(photo.width, closeTo(393 / 3, 0.5), reason: 'un tiers pile');
      expect(photo.height, closeTo(photo.width, 0.5), reason: 'carrée');
    });

    testWidgets('devise courte : la bulle descend pile au bas de la photo', (
      tester,
    ) async {
      // « La bulle devise occupe la place qu'il reste. » Les deux colonnes du
      // dessin s'arrêtent sur la même ligne.
      reponses['/get_profile'] = profil(devise: 'Vite et mal.');
      await ouvrir(tester);

      final photo = tester.getRect(find.byType(ProfilePhoto).first);
      final bulle = tester.getRect(find.byType(BulleDevise));
      expect(bulle.bottom, closeTo(photo.bottom, 0.5));
      expect(
        bulle.top,
        greaterThan(tester.getRect(find.text('mesange')).bottom),
      );
      expect(
        tester.getSize(find.byType(EnteteProfil)).height,
        closeTo(photo.height, 0.5),
        reason: 'rien ne dépasse : le bandeau fait la hauteur de la photo',
      );
    });

    testWidgets('devise longue : trois lignes, et le bandeau s allonge', (
      tester,
    ) async {
      // « La bulle doit pouvoir faire trois lignes, rallonge la zone s'il le
      // faut. Si elle fait plus de trois lignes c'est encore mieux. » Entre
      // écrire plus petit et écrire une ligne de plus, c'est la ligne de plus.
      reponses['/get_profile'] = profil(
        devise:
            'Une devise qui prend ses aises, assez longue pour tenir sur '
            'trois bonnes lignes sans jamais se faire couper nulle part.',
      );
      await ouvrir(tester);

      final photo = tester.getRect(find.byType(ProfilePhoto).first);
      expect(
        tester.getSize(find.byType(EnteteProfil)).height,
        greaterThan(photo.height),
        reason: 'la zone devait s allonger au lieu de rapetisser la devise',
      );
      expect(lignesDeLaDevise(tester), greaterThanOrEqualTo(3));
    });

    testWidgets('le tout est décalé d un TIERS de bandeau de partie', (
      tester,
    ) async {
      // « Le tout doit être décalé vers le bas de la taille des bandeaux dans
      // les parties », puis, l'ayant vu : « moins grand l'espace au-dessus du
      // profil, tu peux le diviser par 3. » Assez pour sortir le pseudo de
      // dessous la barre d'état, pas assez pour faire un trou.
      reponses['/get_profile'] = profil();
      await ouvrir(tester);

      expect(
        tester.getRect(find.byType(EnteteProfil)).top,
        closeTo(hauteurBandeauJoueur() / 3, 0.5),
        reason: 'collé en haut, le pseudo se fait manger ; trop bas, ça baille',
      );
      expect(hauteurBandeauJoueur(), greaterThan(0));
    });

    /// Le défaut que Nino a vu sur son téléphone : la ligne des mélos
    /// tranchée en deux, la devise coupée en bas. Les boîtes se mesuraient en
    /// `S` et les polices en `SF`, qui vaut 1,70 fois plus — `SF(9)` fait
    /// 15,3 avant même l'interligne, dans une boîte de `S(16)`.
    ///
    /// On mesure donc, pour CHAQUE texte du bandeau, ce qu'il occupe vraiment
    /// contre la place qu'on lui laisse. Et sur les trois profils qui
    /// existent : celui d'un autre, le mien — où le crayon prend sa place à
    /// côté de la devise —, et celui dont la devise tient trois lignes.
    final cas = {
      'sur le profil d un autre': profil(),
      'sur le mien, crayon compris': profil(moi: true, pseudo: 'nino'),
      'avec une devise de trois lignes': profil(
        devise:
            'Une devise qui prend ses aises, assez longue pour tenir sur '
            'trois bonnes lignes sans jamais se faire couper nulle part.',
      ),
      'avec un pseudo interminable': profil(
        pseudo: 'un pseudo vraiment interminable et sans la moindre pitié',
      ),
      'sans devise du tout': profil(devise: ''),
    };
    cas.forEach((quand, reponse) {
      testWidgets('rien n y est coupé, $quand', (tester) async {
        reponses['/get_profile'] = reponse;
        await ouvrir(
          tester,
          pseudo: reponse['is_self'] == true ? null : 'mesange',
        );
        verifieQueRienNEstCoupe(tester);
      });
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
        find.widgetWithText(FugaButton, T('Retour')),
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
        find.widgetWithText(FugaButton, T('Retour')),
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
        find.byTooltip(T('Chat')),
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
        reason: 'entre les historiques et « Retour »',
      );
      expect(
        tester.getRect(favori).top,
        lessThan(
          tester.getRect(find.widgetWithText(FugaButton, T('Retour'))).top,
        ),
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

/// Chaque texte du bandeau est-il entier, et à sa taille ?
///
/// DEUX façons de rater une boîte trop courte, et il faut les deux :
///
/// 1. le texte DÉBORDE et se fait trancher — c'est ce que Nino a vu ;
/// 2. le texte RÉTRÉCIT pour y entrer, et devient illisible — c'est ce que
///    `TexteRemplissant` fait maintenant plutôt que de le trancher, et ce
///    serait tout aussi faux dans un bandeau censé s'adapter à son contenu.
///
/// `TexteRemplissant` impose son interligne, si bien que ce qu'on mesure ici
/// est ce que le téléphone affichera — et non ce que la police des tests,
/// dont l'interligne vaut 1,0, voudrait bien faire croire.
void verifieQueRienNEstCoupe(WidgetTester tester) {
  // La plus petite taille demandée dans tout le bandeau : celle des mélos.
  final plancher = SF(9);
  final textes = find.descendant(
    of: find.byType(EnteteProfil),
    matching: find.byType(Text),
  );
  expect(textes, findsWidgets);
  for (final element in textes.evaluate()) {
    final texte = element.widget as Text;
    final boite = (element.renderObject! as RenderBox).size;
    final peintre = TextPainter(
      text: TextSpan(text: texte.data, style: texte.style),
      maxLines: texte.maxLines,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: boite.width);
    expect(
      peintre.height,
      lessThanOrEqualTo(boite.height + 0.5),
      reason:
          '« ${texte.data} » occupe ${peintre.height.toStringAsFixed(1)} '
          'dans une boîte de ${boite.height.toStringAsFixed(1)} : il est coupé',
    );
    expect(
      texte.style!.fontSize!,
      greaterThanOrEqualTo(plancher - 0.01),
      reason:
          '« ${texte.data} » est écrit en '
          '${texte.style!.fontSize!.toStringAsFixed(1)} : sa boîte le force '
          'sous le plancher de lisibilité (${plancher.toStringAsFixed(1)})',
    );
  }
}

/// Combien de lignes la devise occupe réellement.
int lignesDeLaDevise(WidgetTester tester) {
  final texte = tester.widget<Text>(
    find.descendant(of: find.byType(BulleDevise), matching: find.byType(Text)),
  );
  final boite = tester
      .renderObject<RenderBox>(
        find.descendant(
          of: find.byType(BulleDevise),
          matching: find.byType(Text),
        ),
      )
      .size;
  final peintre = TextPainter(
    text: TextSpan(text: texte.data, style: texte.style),
    maxLines: texte.maxLines,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: boite.width);
  return peintre.computeLineMetrics().length;
}
