/// Notifications push — portage de `_init_firebase`, `_register_fcm_token`
/// (main.py) et de `FugaMessagingService.java`.
///
/// Le chemin est le même que chez Kivy :
///
///   1. Firebase s'initialise avec les quatre valeurs de l'application —
///      aucun `google-services.json`, comme en Kivy ;
///   2. on demande le jeton de l'appareil et on l'envoie à `/set_fcm_token` ;
///      s'il n'y a pas encore de compte, il repartira à la connexion ;
///   3. un message reçu devient une notification Android : le titre et le
///      texte viennent de la charge `notification`, et les clés `title` et
///      `body` de la charge `data` l'emportent si elles existent.
///
/// L'icône affichée est `notif_icon` — la silhouette blanche de Kivy, que
/// `tool/gen_android_icons.py` installe dans les cinq densités.
library;

import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../i18n/translations.dart';
import 'firebase_options.dart';
import 'notification_reply.dart';
import 'online_service.dart';

/// Salon de notification, identique à celui du service Java de Kivy.
const String kChannelId = 'lafuga_default';
const String kChannelName = 'La Fuga';

/// Titre par défaut, quand le message n'en porte pas — comme en Kivy.
const String kDefaultTitle = 'La Fuga';

/// Ce qu'un message push contient, une fois démêlé.
typedef PushContent = ({String title, String body});

/// Clés sous lesquelles un push de message peut nommer son expéditeur.
///
/// Le serveur ne change pas : on accepte donc les façons usuelles de le dire
/// plutôt que d'en imposer une. Sans expéditeur reconnu, la notification
/// s'affiche sans champ de réponse — on ne saurait pas à qui l'envoyer.
const List<String> kSenderKeys = [
  'de',
  'from',
  'from_pseudo',
  'expediteur',
  'pseudo',
  'sender',
];

/// Qui a envoyé ce message, si le push le dit.
String? senderOf(RemoteMessage message) {
  for (final key in kSenderKeys) {
    final value = message.data[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

/// Démêle un message comme le fait `onMessageReceived` : la charge
/// `notification` d'abord, puis les clés `data` qui l'emportent.
PushContent contentOf(RemoteMessage message) {
  var title = message.notification?.title ?? kDefaultTitle;
  var body = message.notification?.body ?? '';
  final data = message.data;
  if (data['title'] is String) title = data['title'] as String;
  if (data['body'] is String) body = data['body'] as String;
  return (title: title, body: body);
}

/// Reçoit les messages quand l'application est en arrière-plan ou fermée.
///
/// Doit rester une fonction de premier niveau : Android la rappelle dans un
/// isolate neuf, sans rien de l'application en cours.
///
/// **Un message qui porte une charge `notification` a déjà été affiché par
/// Android avant d'arriver ici**, et en poster une seconde en faisait deux.
/// C'est la différence avec le service Java de Kivy, dont `onMessageReceived`
/// n'est tout simplement pas appelé dans ce cas : Flutter, lui, réveille
/// quand même l'application. Seuls les messages de données pures nous
/// reviennent donc à afficher.
/// Faut-il afficher nous-mêmes ce message reçu en arrière-plan ?
///
/// Non s'il porte une charge `notification` : Android l'a déjà posée.
bool shouldShowInBackground(RemoteMessage message) =>
    message.notification == null;

@pragma('vm:entry-point')
Future<void> handleBackgroundMessage(RemoteMessage message) async {
  if (!shouldShowInBackground(message)) return;
  await Firebase.initializeApp(options: kFirebaseOptions);
  await PushNotifications.show(message);
}

/// Les notifications push de l'application.
class PushNotifications {
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  /// Jeton de l'appareil, une fois connu.
  static String? token;

  /// Prépare Firebase, le salon de notification et l'écoute des messages.
  ///
  /// Ne fait rien hors Android : Kivy s'arrête aussi à `platform != "android"`.
  /// N'échoue jamais — une notification qui ne marche pas ne doit pas empêcher
  /// de jouer.
  static Future<void> init() async {
    if (!_supported) return;
    try {
      await Firebase.initializeApp(options: kFirebaseOptions);
      await _prepareChannel();

      // Android 13 et au-delà demandent la permission d'afficher.
      await FirebaseMessaging.instance.requestPermission();

      FirebaseMessaging.onBackgroundMessage(handleBackgroundMessage);
      FirebaseMessaging.onMessage.listen(show);

      // Le jeton peut changer : on renvoie le nouveau au serveur.
      FirebaseMessaging.instance.onTokenRefresh.listen(registerToken);
      final current = await FirebaseMessaging.instance.getToken();
      if (current != null) await registerToken(current);
    } catch (_) {
      // Pas de Firebase sur cet appareil : on continue sans notifications.
    }
  }

  static bool get _supported {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// Dernier couple (compte, jeton) déjà déclaré au serveur.
  ///
  /// Le jeton part à l'initialisation ET après la reconnexion automatique :
  /// sans repère, le serveur le recevait deux fois de suite pour le même
  /// compte.
  static String? _declared;

  /// Mémorise le jeton et l'envoie au serveur si un compte est ouvert.
  ///
  /// Sans compte, il attend : [sendPendingToken] le renverra à la connexion.
  static Future<void> registerToken(String value) async {
    if (value.isEmpty) return;
    token = value;
    await _declare(value);
  }

  /// Renvoie le jeton connu, à appeler après chaque connexion — Kivy le fait
  /// au même endroit (`_on_login_ok` et la reconnexion automatique).
  static Future<void> sendPendingToken() async {
    final value = token;
    if (value == null || value.isEmpty) return;
    await _declare(value);
  }

  static Future<void> _declare(String value) async {
    final online = OnlineService.instance;
    if (!online.isLoggedIn) return;
    final mark = '${online.pseudo}|$value';
    if (mark == _declared) return;
    _declared = mark;
    await online.client.setFcmToken(value);
  }

  /// Oublie ce qui a été déclaré — à la déconnexion, et pour les tests.
  static void forgetDeclaredToken() => _declared = null;

  /// Affiche une notification. Reprend l'icône, le salon et l'importance du
  /// service Java de Kivy.
  ///
  /// Quand le push nomme son expéditeur, la notification porte en plus un
  /// champ « Répondre » : on répond depuis le volet, sans ouvrir
  /// l'application, comme le font les applis de messagerie.
  static Future<void> show(RemoteMessage message) async {
    final content = contentOf(message);
    final sender = senderOf(message);
    try {
      await _prepareChannel();
      await _local.show(
        DateTime.now().millisecondsSinceEpoch % 100000,
        content.title,
        content.body,
        NotificationDetails(android: androidDetails(sender)),
        payload: sender == null ? null : replyPayloadFor(sender),
      );
    } catch (_) {
      // Ne jamais planter à cause d'une notification — comme le service Java.
    }
  }

  /// Le détail Android d'une notification, avec ou sans champ de réponse.
  static AndroidNotificationDetails androidDetails(String? sender) =>
      AndroidNotificationDetails(
        kChannelId,
        kChannelName,
        importance: Importance.high,
        priority: Priority.high,
        icon: 'notif_icon',
        actions: sender == null
            ? null
            : <AndroidNotificationAction>[
                AndroidNotificationAction(
                  kReplyActionId,
                  T('Répondre'),
                  inputs: <AndroidNotificationActionInput>[
                    AndroidNotificationActionInput(label: T('Votre réponse…')),
                  ],
                  // La notification se referme dès l'envoi : sans cela
                  // Android y laisse tourner un rouet en attendant qu'on la
                  // mette à jour.
                  cancelNotification: true,
                  // Rien à afficher : la réponse part toute seule.
                  showsUserInterface: false,
                ),
              ],
      );

  /// Prévient que la réponse n'est pas partie.
  ///
  /// Une réponse tapée puis perdue en silence est pire que pas de réponse du
  /// tout : le joueur croit avoir répondu.
  static Future<void> warnReplyFailed(String pseudo, String text) async {
    try {
      await _prepareChannel();
      await _local.show(
        DateTime.now().millisecondsSinceEpoch % 100000,
        T('Réponse non envoyée'),
        '$pseudo — $text',
        NotificationDetails(android: androidDetails(pseudo)),
        payload: replyPayloadFor(pseudo),
      );
    } catch (_) {
      // Rien de plus à tenter.
    }
  }

  static bool _channelReady = false;

  static Future<void> _prepareChannel() async {
    if (_channelReady) return;
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('notif_icon'),
      ),
      onDidReceiveNotificationResponse: handleNotificationResponse,
      // Application fermée : Android réveille un isolate neuf, et cette
      // fonction doit être de premier niveau pour y être retrouvée.
      onDidReceiveBackgroundNotificationResponse: handleNotificationResponse,
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            kChannelId,
            kChannelName,
            importance: Importance.high,
          ),
        );
    _channelReady = true;
  }
}

/// Traite une réponse tapée dans une notification.
///
/// Appelée aussi bien par l'application vivante que par un isolate réveillé
/// pour l'occasion : elle ne suppose donc rien de chargé et va chercher la
/// session dans les préférences.
@pragma('vm:entry-point')
Future<void> handleNotificationResponse(NotificationResponse response) async {
  if (response.actionId != kReplyActionId) return;
  final pseudo = pseudoFromPayload(response.payload);
  final text = response.input?.trim() ?? '';
  if (pseudo == null || text.isEmpty) return;

  final sent = await sendReplyFromNotification(pseudo: pseudo, text: text);
  if (!sent) {
    await PushNotifications.warnReplyFailed(pseudo, text);
    return;
  }
  // Si l'application tourne, ce qu'on vient d'écrire ne doit pas s'y compter
  // comme non lu. Si elle ne tourne pas, il n'y a rien à prévenir — et lui
  // faire créer un service depuis cet isolate ferait tout tomber.
  OnlineService.instanceOrNull?.messages.markRead(pseudo);
}
