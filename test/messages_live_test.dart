/// Les messages arrivent en direct, partout où ils se signalent.
///
/// Trois défauts tenaient ensemble : la connexion ne gardait qu'UN écouteur
/// par événement — ouvrir la boîte rendait le menu sourd, la refermer coupait
/// tout le monde —, la pastille du menu était un compteur entre parenthèses,
/// et une notification reçue en arrière-plan s'affichait deux fois.
library;

import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/message_hub.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/net/push_notifications.dart';
import 'package:lafuga/net/socket_client.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:lafuga/ui/screens/menu_screen.dart';
import 'package:lafuga/ui/widgets/game_top_bar.dart';
import 'package:lafuga/ui/widgets/unread_dot.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_realtime.dart';

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

  group('La connexion porte plusieurs écouteurs', () {
    test('un événement réveille tout le monde', () {
      final listeners = SocketListeners();
      final vus = <String>[];
      void menu(Map<String, dynamic> d) => vus.add('menu:${d['de']}');
      void boite(Map<String, dynamic> d) => vus.add('boite:${d['de']}');

      listeners
        ..add(FugaEvents.messageRecu, menu)
        ..add(FugaEvents.messageRecu, boite)
        ..dispatch(FugaEvents.messageRecu, {'de': 'toto'});

      expect(vus, ['menu:toto', 'boite:toto']);
    });

    test('se retirer ne rend pas les autres sourds', () {
      final listeners = SocketListeners();
      final vus = <String>[];
      void menu(Map<String, dynamic> d) => vus.add('menu');
      void boite(Map<String, dynamic> d) => vus.add('boite');

      listeners
        ..add(FugaEvents.messageRecu, menu)
        ..add(FugaEvents.messageRecu, boite)
        // La boîte se referme.
        ..remove(FugaEvents.messageRecu, boite)
        ..dispatch(FugaEvents.messageRecu, const {});

      expect(vus, ['menu'], reason: 'le menu écoute toujours');
      expect(listeners.count(FugaEvents.messageRecu), 1);
    });

    test('le même écouteur ne s abonne pas deux fois', () {
      final listeners = SocketListeners();
      var appels = 0;
      void handler(Map<String, dynamic> d) => appels++;
      listeners
        ..add(FugaEvents.messageRecu, handler)
        ..add(FugaEvents.messageRecu, handler)
        ..dispatch(FugaEvents.messageRecu, const {});
      expect(appels, 1);
    });
  });

  group('La boîte aux lettres', () {
    test('compte les non-lus par correspondant', () {
      final hub = MessageHub();
      var avis = 0;
      hub.addListener(() => avis++);

      hub.attach(_FakeSocket()..hub = hub);
      expect(hub.hasUnread, isFalse);

      hub.receive({'de': 'toto', 'texte': 'salut'});
      hub.receive({'de': 'toto', 'texte': 'ça va ?'});
      hub.receive({'de': 'titi', 'texte': 'hé'});

      expect(hub.total, 3);
      expect(hub.unreadFrom('toto'), 2);
      expect(hub.hasUnreadFrom('toto'), isTrue);
      expect(hub.hasUnreadFrom('inconnu'), isFalse);
      expect(hub.hasUnreadFrom(null), isFalse);
      expect(avis, 3);

      hub.markRead('toto');
      expect(hub.unreadFrom('toto'), 0);
      expect(hub.total, 1);
      hub.dispose();
    });

    test('les messages passent au fil de l eau', () async {
      final hub = MessageHub();
      final recus = <IncomingMessage>[];
      final sub = hub.incoming.listen(recus.add);

      hub.receive({'de': 'toto', 'texte': 'salut'});
      await Future<void>.delayed(Duration.zero);

      expect(recus, hasLength(1));
      expect(recus.single.from, 'toto');
      expect(recus.single.text, 'salut');
      await sub.cancel();
      hub.dispose();
    });
  });

  group('La conversation ouverte', () {
    testWidgets('affiche un message à l instant où il arrive', (tester) async {
      final online = OnlineService(
        client: OnlineClient(
          api: ApiClient(
            client: MockClient(
              (request) async => http.Response(
                jsonEncode({'ok': true, 'messages': const []}),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(online: online, pseudo: 'toto'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('coucou'), findsNothing);

      // Le message arrive pendant qu'on regarde l'écran.
      online.messages.receive({'de': 'toto', 'texte': 'coucou'});
      await tester.pumpAndSettle();

      expect(
        find.text('coucou'),
        findsOneWidget,
        reason: 'plus besoin de quitter la boîte et d y revenir',
      );
      // Et il est lu : la pastille ne doit pas s'allumer pour lui.
      expect(online.messages.unreadFrom('toto'), 0);
    });

    testWidgets('un message d un tiers ne s invite pas', (tester) async {
      final online = OnlineService(
        client: OnlineClient(
          api: ApiClient(
            client: MockClient(
              (request) async => http.Response(
                jsonEncode({'ok': true, 'messages': const []}),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(online: online, pseudo: 'toto'),
        ),
      );
      await tester.pumpAndSettle();

      online.messages.receive({'de': 'titi', 'texte': 'ailleurs'});
      await tester.pumpAndSettle();

      expect(find.text('ailleurs'), findsNothing);
      expect(online.messages.unreadFrom('titi'), 1);
    });
  });

  group('La pastille du menu', () {
    testWidgets('s allume en direct, sans compteur', (tester) async {
      final socket = FakeRealtime();
      final online = OnlineService(
        client: OnlineClient(
          api: ApiClient(
            client: MockClient(
              (request) async => http.Response(
                jsonEncode({'ok': true, 'games': const [], 'total_unread': 0}),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              ),
            ),
          ),
        ),
        socketFactory: (_) => socket,
      );

      await tester.pumpWidget(MaterialApp(home: MenuScreen(online: online)));
      await tester.pumpAndSettle();

      final bouton = find.ancestor(
        of: find.text('Messages'),
        matching: find.byType(UnreadDot),
      );
      expect(bouton, findsOneWidget);
      expect(
        tester.widget<UnreadDot>(bouton).show,
        isFalse,
        reason: 'rien à signaler au départ',
      );

      online.messages.receive({'de': 'toto', 'texte': 'salut'});
      await tester.pumpAndSettle();

      expect(
        tester.widget<UnreadDot>(bouton).show,
        isTrue,
        reason: 'la pastille s allume sans qu on ait quitté le menu',
      );
      // L'intitulé ne porte plus de compteur.
      expect(find.text('Messages'), findsOneWidget);
      expect(find.textContaining('(1)'), findsNothing);
    });
  });

  group('La pastille', () {
    testWidgets('se montre et se cache', (tester) async {
      Future<void> show(bool value) => tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: UnreadDot(show: value, child: const Text('Messages')),
          ),
        ),
      );

      await show(false);
      expect(find.byType(Container), findsNothing);
      await show(true);
      expect(find.byType(Container), findsOneWidget);
      // Le texte de la touche ne change pas : plus de « (1) ».
      expect(find.text('Messages'), findsOneWidget);
    });
  });

  group('La pastille en partie', () {
    testWidgets('ne s allume que pour l adversaire', (tester) async {
      Future<void> bar(int unread) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 60,
              child: GameTopBar(
                palette: paletteOf(kDefaultTheme),
                color: paletteOf(kDefaultTheme).clair,
                onFlip: () {},
                onPause: () {},
                onChat: () {},
                unreadChat: unread,
              ),
            ),
          ),
        ),
      );

      // Un message d'un tiers ne compte pas : l'écran de partie n'interroge
      // la boîte aux lettres que sur SON adversaire.
      final hub = MessageHub();
      hub.receive({'de': 'un tiers', 'texte': 'hé'});
      await bar(hub.unreadFrom('mon adversaire'));
      expect(tester.widget<UnreadDot>(find.byType(UnreadDot)).show, isFalse);

      hub.receive({'de': 'mon adversaire', 'texte': 'à toi'});
      await bar(hub.unreadFrom('mon adversaire'));
      expect(tester.widget<UnreadDot>(find.byType(UnreadDot)).show, isTrue);
      // La touche n'affiche toujours pas de nombre.
      expect(find.textContaining('('), findsNothing);
      hub.dispose();
    });
  });

  group('Les notifications', () {
    test('une notification déjà posée par Android ne se repose pas', () {
      final avecNotification = const RemoteMessage(
        notification: RemoteNotification(title: 'La Fuga', body: 'coup'),
      );
      expect(
        shouldShowInBackground(avecNotification),
        isFalse,
        reason: 'Android l a déjà affichée : la reposer en ferait deux',
      );
    });

    test('un message de données pures, lui, est à afficher', () {
      final donnees = const RemoteMessage(data: {'title': 'A', 'body': 'B'});
      expect(shouldShowInBackground(donnees), isTrue);
    });
  });
}

/// Une connexion qui ne fait rien : la boîte aux lettres s'y attache, et le
/// test lui pousse les messages directement.
class _FakeSocket implements RealtimeSocket {
  MessageHub? hub;

  @override
  void noSuchMethod(Invocation invocation) {}
}
