/// Les notifications qui ne disent rien ne s'affichent pas.
///
/// Un message de données pures — sans charge `notification`, et sans `title`
/// ni `body` dans `data` — donnait une carte vide dans le volet : « La Fuga »
/// et rien d'autre.
///
/// Le test n'interroge pas seulement le prédicat : il INTERCEPTE le canal du
/// greffon de notifications et regarde ce qui y passe. C'est la seule façon
/// de prouver que la garde est bien branchée sur `show`, et pas seulement
/// écrite à côté.
library;

import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:lafuga/net/push_notifications.dart';

/// Ce que le greffon a reçu : un appel par notification réellement posée.
class _Greffon {
  final List<Map<Object?, Object?>> posees = [];

  void brancher() {
    // Hors appareil, le greffon n'a pas d'implémentation Android enregistrée
    // et `show` ne fait rien du tout — le test passerait donc quoi qu'il
    // arrive. On l'enregistre à la main pour que les appels partent vraiment
    // sur le canal, où on les intercepte.
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async {
            if (call.method == 'show') {
              posees.add(call.arguments as Map<Object?, Object?>);
            }
            // `initialize` attend un booléen : lui rendre `null` faisait
            // échouer l'appel, et tout ce qui suit ne partait jamais.
            return call.method == 'initialize' ? true : null;
          },
        );
  }

  void debrancher() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          null,
        );
  }
}

RemoteMessage _message({
  String? titre,
  String? corps,
  Map<String, String> data = const {},
}) => RemoteMessage(
  data: data,
  notification: (titre == null && corps == null)
      ? null
      : RemoteNotification(title: titre, body: corps),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Ce qu un message dit', () {
    test('un message de données pures ne dit rien', () {
      final c = contentOf(_message(data: {'type': 'corr_turn'}));
      expect(c.title, kDefaultTitle, reason: 'le titre retombe sur le défaut');
      expect(c.body, '');
      expect(hasSomethingToSay(c), isFalse);
    });

    test('un corps de blancs ne dit rien non plus', () {
      expect(hasSomethingToSay((title: 'mesange', body: '   ')), isFalse);
      expect(hasSomethingToSay((title: 'mesange', body: '\n')), isFalse);
    });

    test('une vraie notification dit quelque chose', () {
      final c = contentOf(
        _message(titre: 'mesange', corps: 'a joué 6.Sol1-Sol2>Fa3'),
      );
      expect(c.title, 'mesange');
      expect(c.body, 'a joué 6.Sol1-Sol2>Fa3');
      expect(hasSomethingToSay(c), isTrue);
    });

    test('un titre seul ne suffit pas', () {
      // C est exactement la carte vide du volet : « La Fuga », et rien.
      expect(hasSomethingToSay((title: 'La Fuga', body: '')), isFalse);
    });
  });

  group('Ce que le greffon reçoit', () {
    late _Greffon greffon;

    setUp(() {
      greffon = _Greffon()..brancher();
    });
    tearDown(() => greffon.debrancher());

    test('rien, pour un message sans contenu', () async {
      await PushNotifications.show(_message(data: {'type': 'corr_turn'}));
      expect(
        greffon.posees,
        isEmpty,
        reason: 'une carte vide est arrivée dans le volet',
      );
    });

    test('rien non plus, pour un message entièrement vide', () async {
      await PushNotifications.show(_message());
      expect(greffon.posees, isEmpty);
    });

    test('une notification, pour un vrai message', () async {
      await PushNotifications.show(
        _message(titre: 'mesange', corps: 'a joué 6.Sol1-Sol2>Fa3'),
      );
      expect(
        greffon.posees.length,
        1,
        reason: 'la garde a mangé une vraie notification',
      );
      expect(greffon.posees.single['title'], 'mesange');
      expect(greffon.posees.single['body'], 'a joué 6.Sol1-Sol2>Fa3');
    });
  });

  group('Le salon du manifeste', () {
    final manifeste = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    test('c est celui que l application crée', () {
      // Android pose LUI-MÊME les notifications reçues en arrière-plan, dans
      // le salon nommé ici. S il nomme un salon que l application efface au
      // démarrage, ces notifications-là perdent le son.
      final m = RegExp(
        r'default_notification_channel_id"\s*\n?\s*android:value="([^"]+)"',
      ).firstMatch(manifeste);
      expect(m, isNotNull, reason: 'salon par défaut absent du manifeste');
      expect(m!.group(1), kChannelId);
    });

    test('ce n est aucun des salons effacés au démarrage', () {
      for (final vieux in kLegacyChannelIds) {
        expect(
          manifeste.contains('android:value="$vieux"'),
          isFalse,
          reason: '$vieux est effacé au démarrage : Android n y poserait rien',
        );
      }
    });
  });
}
