/// Messagerie : la liste des conversations, et une conversation.
///
/// Nino, sur la boîte de messages :
///
///   — « un appui long sur un mot d'un message reçu ou envoyé ouvre un
///     sélectionneur pour pouvoir copier coller » ;
///   — « on voit en fond de la conversation l'image de fond de menu choisit
///     par notre interlocuteur. Le texte doit apparaître dans des bulles par
///     dessus. Les bulles doivent être aux couleurs du thème […] du thème de
///     l'utilisateur, pas de l'interlocuteur comme le fond » ;
///   — « j'aimerai aussi que les images de profil soient plus grosses dans les
///     conversations » ;
///   — « quand on envoie un smiley seul il apparaît en plus gros ».
library;

import 'dart:convert';

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/messages.dart';
import 'package:lafuga/net/avatar_photos.dart';
import 'package:lafuga/net/decors_connus.dart';
import 'package:lafuga/net/favoris_connus.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:lafuga/ui/widgets/fuga_background.dart';
import 'package:lafuga/ui/widgets/message_bubble.dart';
import 'package:lafuga/ui/widgets/profile_photo.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prefs d'une appli déjà lancée une fois : ni choix de langue, ni tuto —
/// ils n'apparaissent qu'au tout premier démarrage.
const Map<String, Object> _launched = {'lang_chosen': true, 'tuto_seen': true};

/// Serveur simulé : répond ce qu'on lui dit, et retient ce qu'on lui envoie.
final class _Server {
  final List<({String path, Map<String, dynamic> body})> calls = [];
  final Map<String, Map<String, dynamic>> replies = {};

  http.Client get client => MockClient((request) async {
    calls.add((
      path: request.url.path,
      body: Map<String, dynamic>.from(jsonDecode(request.body) as Map),
    ));
    return http.Response(
      jsonEncode(replies[request.url.path] ?? {'ok': true}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  bool called(String path) => calls.any((c) => c.path == path);

  Map<String, dynamic> bodyOf(String path) =>
      calls.lastWhere((c) => c.path == path).body;
}

/// Mon thème, et celui de l'interlocuteur : deux noms bien distincts.
const String kMonTheme = 'foret';
const String kSonTheme = 'volcan';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Server server;
  late OnlineService online;

  setUp(() async {
    SharedPreferences.setMockInitialValues(_launched);
    await Settings.load();
    await Translations.load('fr');
    server = _Server();
    online = OnlineService(
      client: OnlineClient(api: ApiClient(client: server.client)),
    );
    // Photos et décors sont retenus pour toute la session : sans ce ménage,
    // un test hériterait de ce qu'un autre a appris.
    AvatarPhotos.clear();
    DecorsConnus.clear();
    FavorisConnus.instance.oublie();
  });

  group('Avatar', () {
    test("Deep Grey a sa photo, quelle que soit l'orthographe", () {
      expect(avatarPhotoFor('Deep Grey'), 'deepgrey');
      expect(avatarPhotoFor('  deepgrey '), 'deepgrey');
    });

    test('les autres gardent la leur', () {
      expect(avatarPhotoFor('Nino', 'dragon|Nurse'), 'dragon|Nurse');
      expect(avatarPhotoFor('Nino'), '');
    });
  });

  group('Liste des conversations', () {
    /// Connexion préalable, hors du temps simulé des tests de widgets.
    Future<void> logIn() async {
      server.replies['/login'] = {'ok': true, 'token': 't', 'pseudo': 'Nino'};
      await online.login('Nino', 'mdp');
    }

    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ConversationsScreen(online: online)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('sans compte, on demande la connexion', (tester) async {
      await open(tester);
      expect(find.text('Connexion requise'), findsOneWidget);
      expect(server.called('/list_conversations'), isFalse);
    });

    testWidgets('chaque conversation montre son aperçu et ses non-lus', (
      tester,
    ) async {
      await tester.runAsync(logIn);
      server.replies['/list_conversations'] = {
        'ok': true,
        'conversations': [
          {
            'pseudo': 'Ana',
            'last_text': 'À toi de jouer',
            'unread': 3,
            'last_de_moi': false,
          },
          {'pseudo': 'Bob', 'last_text': 'ok', 'last_de_moi': true},
        ],
      };

      await open(tester);

      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('À toi de jouer'), findsOneWidget);
      expect(find.text('3'), findsOneWidget, reason: 'la pastille des non-lus');
      expect(
        find.text('Vous : ok'),
        findsOneWidget,
        reason: 'mon propre dernier message est préfixé',
      );
    });

    testWidgets('aucune conversation, on le dit', (tester) async {
      await tester.runAsync(logIn);
      server.replies['/list_conversations'] = {
        'ok': true,
        'conversations': const [],
      };

      await open(tester);

      expect(find.text('Aucune conversation pour le moment.'), findsOneWidget);
    });
  });

  group('Conversation', () {
    Future<void> open(WidgetTester tester, {String pseudo = 'Ana'}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(online: online, pseudo: pseudo),
        ),
      );
      await tester.pumpAndSettle();
    }

    setUp(() async {
      server.replies['/login'] = {'ok': true, 'token': 't', 'pseudo': 'Nino'};
      await online.login('Nino', 'mdp');
    });

    testWidgets('ouvrir la conversation la marque comme lue', (tester) async {
      server.replies['/list_conversation'] = {'ok': true, 'messages': []};
      await open(tester);

      expect(server.called('/mark_read'), isTrue);
      expect(server.bodyOf('/mark_read')['pseudo'], 'Ana');
      expect(find.text('Aucun message. Écrivez le premier !'), findsOneWidget);
    });

    testWidgets('les messages s affichent des deux côtés', (tester) async {
      server.replies['/list_conversation'] = {
        'ok': true,
        'messages': [
          {'texte': 'Salut', 'de_moi': false},
          {'texte': 'Salut à toi', 'de_moi': true},
        ],
      };
      await open(tester);

      expect(find.text('Salut'), findsOneWidget);
      expect(find.text('Salut à toi'), findsOneWidget);
    });

    testWidgets('un message envoyé apparaît tout de suite', (tester) async {
      server.replies['/list_conversation'] = {'ok': true, 'messages': []};
      await open(tester);

      await tester.enterText(find.byType(TextField), 'Bien joué');
      await tester.tap(find.text('Envoyer'));
      await tester.pump();

      expect(
        find.text('Bien joué'),
        findsOneWidget,
        reason: 'affichage optimiste, avant la réponse du serveur',
      );

      await tester.pumpAndSettle();
      expect(server.bodyOf('/send_message')['pseudo'], 'Ana');
      expect(server.bodyOf('/send_message')['text'], 'Bien joué');
    });

    testWidgets('un envoi refusé est signalé, pas effacé', (tester) async {
      server.replies['/list_conversation'] = {'ok': true, 'messages': []};
      server.replies['/send_message'] = {'ok': false, 'error': 'bloqué'};
      await open(tester);

      await tester.enterText(find.byType(TextField), 'Coucou');
      await tester.tap(find.text('Envoyer'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Coucou'), findsOneWidget);
      expect(find.textContaining('non envoyé'), findsOneWidget);
    });

    testWidgets('un message vide ne part pas', (tester) async {
      server.replies['/list_conversation'] = {'ok': true, 'messages': []};
      await open(tester);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Envoyer'));
      await tester.pumpAndSettle();

      expect(server.called('/send_message'), isFalse);
    });

    testWidgets('une conversation indisponible le dit', (tester) async {
      server.replies['/list_conversation'] = {'ok': false, 'error': 'oups'};
      await open(tester);

      expect(find.text('Conversation indisponible.'), findsOneWidget);
    });
  });

  group('Les bulles', () {
    Future<void> ouvrir(
      WidgetTester tester, {
      List<Map<String, dynamic>> messages = const [],
      String? sonTheme,
      bool? favori,
    }) async {
      server.replies['/login'] ??= {'ok': true, 'token': 't', 'pseudo': 'Nino'};
      await online.login('Nino', 'mdp');
      server.replies['/list_conversation'] = {'ok': true, 'messages': messages};
      server.replies['/get_profile'] = {
        'ok': true,
        'pseudo': 'Ana',
        'photo': '',
        if (sonTheme != null) 'theme': sonTheme,
        if (favori != null) 'is_favorite': favori,
      };
      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(online: online, pseudo: 'Ana'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('l en-tête porte l étoile quand il est favori', (tester) async {
      // Nino, en montrant l'en-tête d'une conversation : « à ces endroits,
      // l'étoile doit aussi apparaître devant le nom. »
      //
      // Et SANS requête de plus : la conversation demande déjà le profil pour
      // son décor, et cette réponse-là porte aussi l'étoile.
      await ouvrir(tester, favori: true);
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(
        server.calls
            .where((c) => c.path == '/get_profile' && c.body['pseudo'] == 'Ana')
            .length,
        1,
        reason: 'une seule requête de profil pour le fond ET l étoile',
      );
    });

    testWidgets('et pas d étoile quand il ne l est pas', (tester) async {
      await ouvrir(tester, favori: false);
      expect(find.byIcon(Icons.star), findsNothing);
    });

    testWidgets('un serveur muet sur la clé n invente pas d étoile', (
      tester,
    ) async {
      await ouvrir(tester);
      expect(find.byIcon(Icons.star), findsNothing);
    });

    MessageBubble bulleDe(WidgetTester tester, String texte) =>
        tester.widget<MessageBubble>(
          find.byWidgetPredicate((w) => w is MessageBubble && w.texte == texte),
        );

    testWidgets('un appui long ouvre le sélectionneur, des DEUX côtés', (
      tester,
    ) async {
      // `SelectableText` et non `Text` : c'est lui qui pose les poignées et le
      // menu « Copier » sur un appui long. Reçu comme envoyé.
      await ouvrir(
        tester,
        messages: [
          {'texte': 'Salut', 'de_moi': false},
          {'texte': 'Salut à toi', 'de_moi': true},
        ],
      );

      for (final texte in ['Salut', 'Salut à toi']) {
        final champ = find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is MessageBubble && w.texte == texte,
          ),
          matching: find.byType(SelectableText),
        );
        expect(champ, findsOneWidget, reason: '« $texte » doit être copiable');
        expect(
          tester.widget<SelectableText>(champ).enableInteractiveSelection,
          isTrue,
        );
      }
    });

    testWidgets('mes bulles et les siennes n ont pas la même couleur', (
      tester,
    ) async {
      await ouvrir(
        tester,
        messages: [
          {'texte': 'Salut', 'de_moi': false},
          {'texte': 'Salut à toi', 'de_moi': true},
        ],
      );

      final mienne = bulleDe(tester, 'Salut à toi');
      final sienne = bulleDe(tester, 'Salut');
      expect(mienne.deMoi, isTrue);
      expect(sienne.deMoi, isFalse);
      expect(
        mienne.palette.clair,
        isNot(mienne.palette.fonce),
        reason: 'sans quoi on ne distinguerait pas qui parle',
      );
    });

    testWidgets('le fond ET les bulles sont à lui', (tester) async {
      // Nino, d'abord : « les bulles doivent être aux couleurs du thème de
      // l'utilisateur, pas de l'interlocuteur comme le fond ». Puis :
      // « j'aimerais que les bulles dépendent de la partie "général" du thème
      // de l'adversaire ». C'est ce second mot qui vaut : on entre chez lui,
      // tout l'écran est chez lui.
      server.replies['/login'] = {
        'ok': true,
        'token': 't',
        'pseudo': 'Nino',
        'theme': 'foret',
      };
      await ouvrir(
        tester,
        messages: [
          {'texte': 'Salut', 'de_moi': false},
        ],
        sonTheme: 'volcan',
      );

      expect(
        tester.widget<FugaBackground>(find.byType(FugaBackground)).theme,
        'volcan',
        reason: 'le fond est le SIEN',
      );
      expect(
        bulleDe(tester, 'Salut').palette,
        paletteOf('volcan'),
        reason: 'et les bulles aussi, maintenant',
      );
      expect(
        paletteOf('foret'),
        isNot(paletteOf('volcan')),
        reason: 'sans quoi ce test ne mesurerait rien',
      );
    });

    testWidgets(
      'un thème composite : c est l axe GÉNÉRAL qui fait les bulles',
      (tester) async {
        // Son thème a cinq axes. Le fond vient du quatrième (« menu »), les
        // bulles du premier (« général ») — Nino l'a précisé.
        await ouvrir(
          tester,
          messages: [
            {'texte': 'Salut', 'de_moi': false},
          ],
          sonTheme: 'volcan|foret|foret|hemo|foret',
        );

        expect(
          tester.widget<FugaBackground>(find.byType(FugaBackground)).theme,
          'hemo',
          reason: 'le fond, c est l axe menu',
        );
        expect(
          bulleDe(tester, 'Salut').palette,
          paletteOf('volcan'),
          reason: 'les bulles, c est l axe général',
        );
      },
    );

    testWidgets('UNE photo par personne, en bas et en grand', (tester) async {
      // Nino : « au lieu de faire apparaître plein de fois en petit les
      // images de profil des utilisateurs, je voudrais qu'elles soient une
      // seule fois en plus gros en bas ».
      await ouvrir(
        tester,
        messages: [
          {'texte': 'Salut', 'de_moi': false},
          {'texte': 'Salut à toi', 'de_moi': true},
          {'texte': 'et encore une', 'de_moi': false},
        ],
      );

      final photos = tester.widgetList<ProfilePhoto>(find.byType(ProfilePhoto));
      expect(
        photos.length,
        2,
        reason: 'une par personne, et non une par message',
      );
      for (final p in photos) {
        expect(p.size, kAvatarBasConversation);
        expect(
          p.size,
          greaterThan(kAvatarConversation),
          reason: 'plus grosses qu avant',
        );
      }

      // En bas : sous la dernière bulle, au-dessus de la saisie.
      final basDesBulles = tester.getRect(find.text('et encore une')).bottom;
      for (final coin in tester.widgetList<ProfilePhoto>(
        find.byType(ProfilePhoto),
      )) {
        expect(
          tester.getRect(find.byWidget(coin)).top,
          greaterThan(basDesBulles),
        );
      }
      expect(
        tester.getRect(find.byType(ProfilePhoto).last).top,
        lessThan(tester.getRect(find.byType(TextField)).top),
      );

      // La sienne à gauche, la mienne à droite — chacune du côté de ses
      // bulles.
      final gauche = tester.getRect(find.byType(ProfilePhoto).first);
      final droite = tester.getRect(find.byType(ProfilePhoto).last);
      expect(gauche.left, lessThan(droite.left));
    });

    testWidgets('aucune photo ne colle plus aux bulles', (tester) async {
      await ouvrir(
        tester,
        messages: [
          for (var i = 0; i < 8; i++)
            {'texte': 'message $i', 'de_moi': i.isEven},
        ],
      );
      expect(
        find.byType(ProfilePhoto),
        findsNWidgets(2),
        reason: 'huit messages ne font toujours que deux photos',
      );
    });

    testWidgets('sans son thème, AUCUN fond — et surtout pas le mien', (
      tester,
    ) async {
      // Un serveur pas encore corrigé ne renvoie pas `theme` dans le profil.
      // La conversation s'affiche quand même, sur la couleur unie, et elle y
      // reste.
      //
      // Elle montrait le nôtre avant. Nino : « Mon fond ne doit pas être
      // remplacé par celui de mon adversaire » — et montrer le mien, c'est
      // précisément promettre un remplacement, qu'il arrive une seconde plus
      // tard ou jamais.
      //
      // Le nôtre se pose à la CONNEXION et non dans les réglages locaux : le
      // compte gagne sur l'appareil, et une connexion sans thème ramènerait
      // « original » par-dessus ce qu'on aurait réglé ici.
      server.replies['/login'] = {
        'ok': true,
        'token': 't',
        'pseudo': 'Nino',
        'theme': 'foret',
      };
      await ouvrir(
        tester,
        messages: [
          {'texte': 'Salut', 'de_moi': false},
        ],
      );

      expect(
        tester.widget<FugaBackground>(find.byType(FugaBackground)).theme,
        kSansFond,
        reason: 'aucune image, plutôt que la mienne',
      );
      // Les bulles, elles, restent aux MIENNES couleurs : c'est mon
      // application, et ça n'a pas changé.
      expect(bulleDe(tester, 'Salut').palette, paletteOf('foret'));
    });

    testWidgets('une bulle ne prend pas toute la largeur', (tester) async {
      // 75 % : au-delà, l'œil ne distingue plus qui parle.
      await ouvrir(
        tester,
        messages: [
          {
            'texte':
                'Un message très long qui doit revenir à la ligne plutôt que '
                'de traverser tout l écran de part en part sans s arrêter.',
            'de_moi': false,
          },
        ],
      );

      final largeur = tester.getSize(find.byType(MessageBubble).first).width;
      final ecran =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(largeur, lessThanOrEqualTo(ecran * kBulleLargeurMax + 1));
    });
  });

  /// LE FOND EST POSÉ DU PREMIER COUP, JAMAIS REMPLACÉ.
  ///
  /// Nino : « quand je vais sur une conversation, ça affiche un petit moment
  /// mon fond au lieu de celui de mon adversaire. Mon fond ne doit pas être
  /// "remplacé" par celui de mon adversaire […] son app reçoit le nom du fond
  /// […] alors elle crée sa boîte de discussion en utilisant directement
  /// cette image de fond. »
  ///
  /// Rien ne se télécharge : l'image est dans l'application, c'est le NOM qui
  /// vient du serveur. Ces cas surveillent la SUITE des fonds posés depuis
  /// l'ouverture — le mien ne doit jamais y figurer.
  group('Le fond, du premier coup', () {
    /// Un serveur qui répond au compte-gouttes : chaque réponse n'arrive que
    /// lorsqu'on la libère. C'est ce qui permet de voir ce qui est affiché
    /// PENDANT l'attente.
    ({OnlineService online, List<String> demandes, void Function() libere})
    serveur({String? sonTheme = kSonTheme, bool retarde = false}) {
      final demandes = <String>[];
      final attente = Completer<void>();
      final client = OnlineClient(
        api: ApiClient(
          client: MockClient((req) async {
            demandes.add(
              req.url.path == '/get_profile' &&
                      req.body.contains('"pseudo":"toto"')
                  ? '/get_profile toto'
                  : req.url.path,
            );
            // Seul le profil de l'INTERLOCUTEUR traîne. `login` demande le
            // mien au passage (`fetchMyPhoto`) : le retarder aussi bloquerait
            // la connexion elle-même, et le test entier avec.
            final pourLui = req.body.contains('"pseudo":"toto"');
            if (retarde && req.url.path == '/get_profile' && pourLui) {
              await attente.future;
            }
            return http.Response(
              jsonEncode(switch (req.url.path) {
                '/login' => {
                  'ok': true,
                  'token': 't',
                  'pseudo': 'Nino',
                  'theme': kMonTheme,
                },
                '/list_conversation' => {
                  'ok': true,
                  'messages': [
                    {'texte': 'Salut', 'de_moi': false},
                  ],
                },
                '/get_profile' => {
                  'ok': true,
                  'pseudo': 'toto',
                  'photo': '',
                  if (sonTheme != null) 'theme': sonTheme,
                },
                _ => {'ok': true},
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );
      return (
        online: OnlineService(client: client),
        demandes: demandes,
        libere: () {
          if (!attente.isCompleted) attente.complete();
        },
      );
    }

    /// Mon thème posé, et le compte connecté : sans compte, l'application ne
    /// demande rien au serveur et le test ne prouverait rien.
    Future<void> pret(OnlineService online) async {
      await Settings.instance.setTheme(kMonTheme);
      await online.login('Nino', 'mdp');
    }

    /// Tous les fonds posés, dans l'ordre, depuis l'ouverture.
    Future<List<String?>> fondsPoses(
      WidgetTester tester,
      OnlineService online, {
      int frames = 30,
    }) async {
      final vus = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(online: online, pseudo: 'toto'),
        ),
      );
      for (var i = 0; i < frames; i++) {
        final fond = find.byType(FugaBackground);
        if (fond.evaluate().isNotEmpty) {
          final t = tester.widget<FugaBackground>(fond).theme;
          if (vus.isEmpty || vus.last != t) vus.add(t);
        }
        await tester.pump(const Duration(milliseconds: 16));
      }
      return vus;
    }

    test('le cache de décors retient, rend et oublie', () {
      expect(DecorsConnus.known('toto'), '');
      DecorsConnus.remember('Toto', kSonTheme);
      expect(
        DecorsConnus.known('toto'),
        kSonTheme,
        reason: 'la casse du pseudo ne doit pas compter',
      );
      DecorsConnus.remember('toto', '  ');
      expect(
        DecorsConnus.known('toto'),
        kSonTheme,
        reason: 'une réponse vide n efface pas ce qu on savait',
      );
      DecorsConnus.clear();
      expect(DecorsConnus.known('toto'), '');
    });

    testWidgets('MON fond ne paraît jamais, à aucune image', (tester) async {
      final s = serveur();
      await pret(s.online);
      // Une photo connue : `ProfilePhoto` charge sinon son image par défaut de
      // façon asynchrone, et ce chargement laisse un minuteur en vol que la
      // vérification de fin de test signale. Ce cas-ci parle du FOND ; l'avatar
      // n'y est qu'un figurant.
      AvatarPhotos.remember('toto', 'garde');

      final vus = await fondsPoses(tester, s.online);

      expect(
        vus,
        isNot(contains(kMonTheme)),
        reason: 'c est le remplacement que Nino a vu : suite posée = $vus',
      );
      expect(vus.last, kSonTheme, reason: 'on finit chez lui');
      expect(
        vus.where((t) => t != kSansFond).toSet(),
        {kSonTheme},
        reason: 'un seul décor en tout et pour tout, le sien',
      );
    });

    testWidgets('pendant l attente : aucune image, pas la mienne', (
      tester,
    ) async {
      // Le profil traîne : c'est exactement la fenêtre où mon fond s'affichait.
      final s = serveur(retarde: true);
      await pret(s.online);

      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(online: s.online, pseudo: 'toto'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        tester.widget<FugaBackground>(find.byType(FugaBackground)).theme,
        kSansFond,
        reason:
            'ni le sien, qu on ignore, ni le mien, qu il faudrait remplacer',
      );

      s.libere();
      await tester.pumpAndSettle();
      expect(
        tester.widget<FugaBackground>(find.byType(FugaBackground)).theme,
        kSonTheme,
      );
    });

    testWidgets('la conversation n est montrée qu une fois le fond connu', (
      tester,
    ) async {
      final s = serveur(retarde: true);
      await pret(s.online);

      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(online: s.online, pseudo: 'toto'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Salut'),
        findsNothing,
        reason: 'afficher les messages avant le fond, c est le clignotement',
      );

      s.libere();
      await tester.pumpAndSettle();
      expect(find.text('Salut'), findsOneWidget);
    });

    testWidgets('la deuxième visite ouvre d emblée sur son fond', (
      tester,
    ) async {
      // Le nom est retenu : l image est déjà dans l application, il n y a rien
      // à attendre.
      final s = serveur(retarde: true);
      await pret(s.online);
      DecorsConnus.remember('toto', kSonTheme);

      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(online: s.online, pseudo: 'toto'),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<FugaBackground>(find.byType(FugaBackground)).theme,
        kSonTheme,
        reason: 'dès la première image, sans réseau',
      );
      expect(
        s.demandes,
        isNot(contains('/get_profile toto')),
        reason: 'le nom est connu : on ne le redemande pas',
      );
      s.libere();
      await tester.pumpAndSettle();
    });

    testWidgets(
      'une photo déjà connue n empêche pas d aller chercher le fond',
      (tester) async {
        // Le piège : un écran de partie a retenu la photo, et la garde du cache
        // des photos sautait la requête — la conversation restait alors sans
        // aucun fond, et pour de bon.
        final s = serveur();
        await pret(s.online);
        AvatarPhotos.remember('toto', 'garde');

        final vus = await fondsPoses(tester, s.online);
        expect(s.demandes, contains('/get_profile toto'));
        expect(vus.last, kSonTheme);
        expect(vus, isNot(contains(kMonTheme)));
      },
    );

    testWidgets('serveur muet sur le thème : aucun fond, et ça ne bouge plus', (
      tester,
    ) async {
      final s = serveur(sonTheme: null);
      await pret(s.online);

      final vus = await fondsPoses(tester, s.online);

      expect(vus, [kSansFond], reason: 'une seule valeur, et pas la mienne');
      expect(
        find.text('Salut'),
        findsOneWidget,
        reason: 'la boîte s ouvre quand même',
      );
    });
  });

  group('Un émoji seul', () {
    Future<void> ouvrir(WidgetTester tester, List<String> textes) async {
      server.replies['/login'] = {'ok': true, 'token': 't', 'pseudo': 'Nino'};
      await online.login('Nino', 'mdp');
      server.replies['/list_conversation'] = {
        'ok': true,
        'messages': [
          for (final t in textes) {'texte': t, 'de_moi': true},
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(online: online, pseudo: 'Ana'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('il s affiche en GROS, et sans bulle', (tester) async {
      // Les deux messages dans la MÊME conversation : les tailles se
      // comparent alors sans dépendre de deux montages successifs.
      await ouvrir(tester, ['coucou', '😀']);

      final grosse = tester.widget<Text>(find.text('😀')).style!.fontSize!;
      final normale = tester
          .widget<SelectableText>(
            find.descendant(
              of: find.byWidgetPredicate(
                (w) => w is MessageBubble && w.texte == 'coucou',
              ),
              matching: find.byType(SelectableText),
            ),
          )
          .style!
          .fontSize!;

      expect(
        grosse,
        greaterThan(normale * 2),
        reason: 'un smiley seul doit sauter aux yeux',
      );
      expect(
        find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is MessageBubble && w.texte == '😀',
          ),
          matching: find.byType(SelectableText),
        ),
        findsNothing,
        reason: 'hors de sa bulle : il n y a rien à encadrer',
      );
    });

    testWidgets('mais un émoji DANS une phrase reste normal', (tester) async {
      await ouvrir(tester, ['bravo 😀']);
      expect(
        find.descendant(
          of: find.byType(MessageBubble),
          matching: find.byType(SelectableText),
        ),
        findsOneWidget,
        reason: 'c est un message ordinaire, il garde sa bulle',
      );
    });
  });
}
