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

import 'firebase_options.dart';
import 'online_service.dart';

/// Salons d'autrefois, à effacer : l'ancien muet, et ceux d'une version
/// intermédiaire qui donnait un son par instrument. Les laisser empilerait
/// des lignes mortes dans les réglages Android du téléphone.
const List<String> kLegacyChannelIds = [
  'lafuga_default',
  'lafuga_piano',
  'lafuga_orgue',
  'lafuga_guitare',
  'lafuga_cloche',
];

/// Le salon de notification. Un seul.
///
/// Android FIGE le son d'un salon à sa création : pour qu'il suive
/// l'instrument choisi, il en faudrait un PAR instrument — quatre lignes dans
/// les réglages du téléphone et quatre fichiers dans l'APK. Pour un son de
/// trois secondes, ça ne valait pas son prix : c'est le piano pour tout le
/// monde.
const String kChannelId = 'lafuga_notif';
const String kChannelName = 'La Fuga';

/// Fichier de son embarqué, fabriqué par `tool/gen_notif_sound.dart` à partir
/// des vraies notes du jeu : le glissando qui arrive au milieu de la
/// tessiture, au piano.
const String kChannelSound = 'notif_piano';

/// Titre par défaut, quand le message n'en porte pas — comme en Kivy.
const String kDefaultTitle = 'La Fuga';

/// Ce qu'un message push contient, une fois démêlé.
typedef PushContent = ({String title, String body});

/// Ce message a-t-il quelque chose à dire ?
///
/// Un message de données pures — sans charge `notification`, et sans `title`
/// ni `body` dans `data` — donnait une carte vide dans le volet : « La Fuga »
/// et rien d'autre, ou même rien du tout. Le titre par défaut ne dit rien
/// qu'Android n'écrive déjà au-dessus, avec l'icône.
///
/// Les six notifications du serveur portent toutes un corps ; une carte sans
/// corps ne peut donc rien annoncer. On ne l'affiche pas.
///
/// On a essayé d'annoncer quelque chose quand même, à partir du `type` des
/// données — « À vous de jouer » et compagnie — au cas où ces cartes vides
/// auraient été de vraies notifications arrivées sans leur texte. Elles n'en
/// sont pas : rien ne bouge dans l'application quand elles tombent. Ce repli
/// n'aurait donc rien sauvé, et aurait au contraire FABRIQUÉ des cartes
/// inutiles si ces messages portent un `type`.
bool hasSomethingToSay(PushContent content) => content.body.trim().isNotEmpty;

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
  /// compte — et s'il les empile au lieu de les remplacer, cela fait deux
  /// notifications par message.
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
  static Future<void> show(RemoteMessage message) async {
    final content = contentOf(message);
    if (!hasSomethingToSay(content)) return;
    try {
      await _prepareChannel();
      await _local.show(
        DateTime.now().millisecondsSinceEpoch % 100000,
        content.title,
        content.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            kChannelId,
            kChannelName,
            importance: Importance.high,
            priority: Priority.high,
            icon: 'notif_icon',
            // Le salon décide sur Android 8 et au-delà ; avant, c'est cette
            // ligne-ci. Les deux disent la même chose.
            sound: RawResourceAndroidNotificationSound(kChannelSound),
          ),
        ),
      );
    } catch (_) {
      // Ne jamais planter à cause d'une notification — comme le service Java.
    }
  }

  static bool _channelReady = false;

  static Future<void> _prepareChannel() async {
    if (_channelReady) return;
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('notif_icon'),
      ),
    );
    final android = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    for (final vieux in kLegacyChannelIds) {
      await android?.deleteNotificationChannel(vieux);
    }
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        kChannelId,
        kChannelName,
        importance: Importance.high,
        sound: RawResourceAndroidNotificationSound(kChannelSound),
      ),
    );
    _channelReady = true;
  }
}
