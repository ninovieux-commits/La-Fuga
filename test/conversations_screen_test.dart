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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/messages.dart';
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
    }) async {
      server.replies['/login'] ??= {'ok': true, 'token': 't', 'pseudo': 'Nino'};
      await online.login('Nino', 'mdp');
      server.replies['/list_conversation'] = {'ok': true, 'messages': messages};
      server.replies['/get_profile'] = {
        'ok': true,
        'pseudo': 'Ana',
        'photo': '',
        if (sonTheme != null) 'theme': sonTheme,
      };
      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(online: online, pseudo: 'Ana'),
        ),
      );
      await tester.pumpAndSettle();
    }

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

    testWidgets('le FOND est à lui, les BULLES sont à moi', (tester) async {
      // Les deux ne vont pas ensemble, et c'est voulu : on entre chez lui, on
      // voit son décor, mais les bulles restent celles de mon application —
      // je dois m'y retrouver d'une conversation à l'autre.
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
        paletteOf('foret'),
        reason: 'les bulles sont les MIENNES',
      );
      expect(
        paletteOf('foret'),
        isNot(paletteOf('volcan')),
        reason: 'sans quoi ce test ne mesurerait rien',
      );
    });

    testWidgets('les photos de profil sont GROSSES', (tester) async {
      // À trente-quatre, un portrait de pièce ne se reconnaissait pas.
      await ouvrir(
        tester,
        messages: [
          {'texte': 'Salut', 'de_moi': false},
        ],
      );

      final photo = tester.widget<ProfilePhoto>(
        find.byType(ProfilePhoto).first,
      );
      expect(photo.size, kAvatarConversation);
      expect(
        photo.size,
        greaterThan(40),
        reason: 'plus grosses qu avant, où elles faisaient trente-quatre',
      );
    });

    testWidgets('sans son thème, le fond garde le nôtre', (tester) async {
      // Un serveur pas encore corrigé ne renvoie pas `theme` dans le profil :
      // la conversation doit s'afficher quand même, avec notre décor.
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
        'foret',
      );
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
