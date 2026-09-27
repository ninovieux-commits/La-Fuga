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

import '../game/sound_plan.dart';
import '../state/settings.dart';
import 'firebase_options.dart';
import 'online_service.dart';

/// Ancien salon, sans son choisi. Supprimé au démarrage : il resterait sinon
/// dans les réglages Android du téléphone, muet et sans emploi.
const String kLegacyChannelId = 'lafuga_default';

/// Salon de notification, un par instrument.
///
/// Android FIGE le son d'un salon à sa création : on ne peut pas le changer
/// ensuite. Changer d'instrument dans les réglages veut donc dire changer de
/// salon, et il en faut un par instrument. C'est la seule façon d'avoir un son
/// de notification qui suive le réglage du joueur.
String channelIdFor(String instrument) => 'lafuga_$instrument';

/// Nom affiché dans les réglages Android. L'instrument y figure, sinon quatre
/// lignes « La Fuga » s'y empileraient sans qu'on sache laquelle est laquelle.
String channelNameFor(String instrument) => 'La Fuga — $instrument';

/// Fichier de son embarqué, fabriqué par `tool/gen_notif_sound.dart` à partir
/// des vraies notes du jeu : le glissando qui arrive au milieu de la
/// tessiture, joué par l'instrument choisi.
String channelSoundFor(String instrument) => 'notif_$instrument';

/// Titre par défaut, quand le message n'en porte pas — comme en Kivy.
const String kDefaultTitle = 'La Fuga';

/// Ce qu'un message push contient, une fois démêlé.
typedef PushContent = ({String title, String body});

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
      await _prepareChannel(await currentInstrument());

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
    try {
      final instrument = await currentInstrument();
      await _prepareChannel(instrument);
      await _local.show(
        DateTime.now().millisecondsSinceEpoch % 100000,
        content.title,
        content.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelIdFor(instrument),
            channelNameFor(instrument),
            importance: Importance.high,
            priority: Priority.high,
            icon: 'notif_icon',
            // Le salon décide sur Android 8 et au-delà ; avant, c'est cette
            // ligne-ci. Les deux disent la même chose.
            sound: RawResourceAndroidNotificationSound(
              channelSoundFor(instrument),
            ),
          ),
        ),
      );
    } catch (_) {
      // Ne jamais planter à cause d'une notification — comme le service Java.
    }
  }

  /// L'instrument choisi dans les réglages, piano à défaut.
  ///
  /// Une notification reçue application fermée est affichée dans un ISOLAT à
  /// part, où les réglages ne sont pas chargés : il faut les y ouvrir. Si rien
  /// n'y parvient, le piano — le réglage par défaut — plutôt que pas de son.
  static Future<String> currentInstrument() async {
    try {
      return Settings.instance.instrument;
    } catch (_) {
      try {
        await Settings.load();
        return Settings.instance.instrument;
      } catch (_) {
        return kInstruments.first;
      }
    }
  }

  /// Salons déjà créés dans cette exécution.
  static final Set<String> _channelsReady = {};
  static bool _initialised = false;

  static Future<void> _prepareChannel(String instrument) async {
    final android = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (!_initialised) {
      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('notif_icon'),
        ),
      );
      // L'ancien salon n'a pas de son choisi et ne sert plus. Le laisser
      // laisserait une ligne morte dans les réglages du téléphone.
      await android?.deleteNotificationChannel(kLegacyChannelId);
      _initialised = true;
    }
    if (_channelsReady.contains(instrument)) return;
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        channelIdFor(instrument),
        channelNameFor(instrument),
        importance: Importance.high,
        sound: RawResourceAndroidNotificationSound(channelSoundFor(instrument)),
      ),
    );
    _channelsReady.add(instrument);
  }
}
