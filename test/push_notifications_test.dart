/// Notifications push : ce qu'on tire d'un message, et la permission Android.
///
/// Firebase lui-même ne se teste pas ici (il lui faut un téléphone) : on fige
/// les deux décisions que l'app prend elle-même, et que Kivy prend pareil.
library;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/notification_permission.dart';
import 'package:lafuga/net/push_notifications.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/screens/account_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafuga/net/api_client.dart';
import 'package:lafuga/net/online_client.dart';
import 'package:lafuga/net/online_service.dart';

/// Permission simulée : accordée ou non, et on note ce qui a été demandé.
final class FakePermission implements NotificationPermission {
  FakePermission({this.isGranted = true});

  bool isGranted;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<bool> granted() async => isGranted;

  @override
  Future<void> request() async => requests++;

  @override
  Future<void> openSettings() async => settingsOpened++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Contenu d un message', () {
    test('la charge notification donne le titre et le texte', () {
      const m = RemoteMessage(
        notification: RemoteNotification(
          title: 'À toi de jouer',
          body: 'Ana a joué Do2-Do3',
        ),
      );

      expect(contentOf(m).title, 'À toi de jouer');
      expect(contentOf(m).body, 'Ana a joué Do2-Do3');
    });

    test('les clés data l emportent, comme dans le service Java', () {
      const m = RemoteMessage(
        notification: RemoteNotification(title: 'Générique', body: 'x'),
        data: {'title': 'Ana vous défie', 'body': 'Correspondance'},
      );

      expect(contentOf(m).title, 'Ana vous défie');
      expect(contentOf(m).body, 'Correspondance');
    });

    test('un message nu porte le nom du jeu', () {
      expect(contentOf(const RemoteMessage()).title, 'La Fuga');
      expect(contentOf(const RemoteMessage()).body, '');
    });
  });

  group('Permission Android', () {
    late OnlineService online;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Settings.load();
      await Translations.load('fr');

      // Serveur simulé : un profil à moi, notifications éteintes au départ.
      final client = MockClient((request) async {
        final body = request.url.path == '/get_profile'
            ? {
                'ok': true,
                'pseudo': 'Nino',
                'is_self': true,
                'melo': 1500,
                'melo_random': 1500,
                'email': '',
                'photo': '',
                'description': '',
                'followers': const [],
                'following': const [],
                'blocked': const [],
              }
            : request.url.path == '/account_info'
            ? {
                'ok': true,
                'notif': const {'mail': false},
              }
            : {'ok': true};
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      online = OnlineService(
        client: OnlineClient(api: ApiClient(client: client)),
      );
    });

    Future<FakePermission> openAccount(
      WidgetTester tester, {
      required bool granted,
    }) async {
      final permission = FakePermission(isGranted: granted);
      await tester.pumpWidget(
        MaterialApp(
          home: AccountScreen(online: online, permission: permission),
        ),
      );
      await tester.pumpAndSettle();
      return permission;
    }

    testWidgets('rallumer les notifications demande la permission', (
      tester,
    ) async {
      final permission = await openAccount(tester, granted: false);

      await tester.tap(find.text('Recevoir des notifications :'));
      await tester.pumpAndSettle();

      expect(permission.requests, 1);
      expect(
        find.textContaining('autorisez La Fuga'),
        findsOneWidget,
        reason: 'refusée : Kivy explique où la donner',
      );

      await tester.tap(find.text('Ouvrir les réglages'));
      await tester.pumpAndSettle();
      expect(permission.settingsOpened, 1);
    });

    testWidgets('permission déjà accordée : rien ne s affiche', (tester) async {
      final permission = await openAccount(tester, granted: true);

      await tester.tap(find.text('Recevoir des notifications :'));
      await tester.pumpAndSettle();

      expect(permission.requests, 0);
      expect(find.textContaining('autorisez La Fuga'), findsNothing);
    });
  });
}
