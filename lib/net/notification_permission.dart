/// Permission d'afficher des notifications — portage de
/// `_android_notif_permission_granted`, `_android_request_notif_permission`
/// et `_android_open_notif_settings` (main.py).
///
/// Android 13 a rendu l'affichage des notifications soumis à permission : une
/// appli autorisée côté serveur peut donc rester muette. Kivy vérifie, demande,
/// et propose d'ouvrir les réglages du téléphone ; on fait de même.
library;

import 'package:flutter/services.dart';

/// Le pont vers `MainActivity`.
const MethodChannel _channel = MethodChannel('org.lafuga/notifications');

/// Injectable pour les tests : ce que sait faire le téléphone.
abstract interface class NotificationPermission {
  /// Les notifications sont-elles autorisées ? Vrai partout ailleurs qu'Android
  /// 13 et au-delà, où la permission n'existe pas.
  Future<bool> granted();

  /// Ouvre le dialogue système. Sans effet si déjà accordée.
  Future<void> request();

  /// Ouvre les réglages de notification de l'appli.
  Future<void> openSettings();
}

/// L'implémentation réelle, par le canal de plateforme.
final class AndroidNotificationPermission implements NotificationPermission {
  const AndroidNotificationPermission();

  @override
  Future<bool> granted() async {
    try {
      return await _channel.invokeMethod<bool>('granted') ?? true;
    } on PlatformException {
      return true;
    } on MissingPluginException {
      // Hors Android (tests, bureau) : rien ne bloque.
      return true;
    }
  }

  @override
  Future<void> request() => _invoke('request');

  @override
  Future<void> openSettings() => _invoke('openSettings');

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException {
      // Un téléphone qui refuse ne doit pas faire échouer l'appli.
    } on MissingPluginException {
      // Hors Android : rien à faire.
    }
  }
}
