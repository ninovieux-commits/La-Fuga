/// Point d'entrée de La Fuga.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'i18n/translations.dart';
import 'net/online_service.dart';
import 'net/push_notifications.dart';
import 'state/settings.dart';
import 'ui/scale.dart';
import 'ui/screens/menu_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _guardAgainstCrashes();

  // L'app Kivy est verrouillée en portrait (buildozer.spec) : le plateau est
  // calé sur la largeur de l'écran.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Plein écran immersif — portage d'`_enable_immersive_mode`. Kivy masque la
  // barre d'état et celle de navigation ; elles reviennent au glissement
  // depuis un bord, puis se recachent. C'est cette hauteur-là qui manquait :
  // sans elle, la bande de ralliement du bas ne rentre pas.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final settings = await Settings.load();
  await Translations.load(settings.language);

  // Reconnexion au compte, sans bloquer l'affichage : le menu doit
  // apparaître tout de suite, connecté ou non. Le jeton de notification part
  // ensuite, quand on sait si un compte est ouvert.
  unawaited(
    OnlineService.instance.autoLogin.then(
      (_) => PushNotifications.sendPendingToken(),
    ),
  );

  // Notifications push : comme en Kivy, on ne bloque pas le démarrage pour
  // elles et une erreur ne coûte que les notifications.
  unawaited(PushNotifications.init());

  runApp(const FugaApp());
}

/// Filet de sécurité : une erreur imprévue ne doit pas fermer une partie.
///
/// Un jeu n'a rien à gagner à s'arrêter net. Une exception dans un rendu ou
/// dans un travail de fond est notée en développement, et **avalée** une fois
/// l'application livrée : le joueur garde son plateau et peut continuer, ou au
/// pire revenir au menu.
void _guardAgainstCrashes() {
  FlutterError.onError = (details) {
    if (kDebugMode) {
      FlutterError.presentError(details);
    }
  };

  // Erreur asynchrone que personne n'a rattrapée : on la déclare traitée
  // plutôt que de laisser le moteur arrêter l'application.
  PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('La Fuga — erreur non rattrapée : $error\n$stack');
    }
    return true;
  };

  // Le carré rouge de Flutter n'a rien à faire sous les yeux d'un joueur.
  ErrorWidget.builder = (details) => Material(
    color: const Color(0xFF3B3B3B),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          T('Quelque chose n a pas pu s afficher.'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ),
    ),
  );
}

class FugaApp extends StatefulWidget {
  const FugaApp({super.key});

  @override
  State<FugaApp> createState() => _FugaAppState();
}

class _FugaAppState extends State<FugaApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Le plein écran se perd au retour d'une autre application, ou après un
  /// clavier. Kivy le réapplique toutes les trois secondes ; ici il suffit de
  /// le redemander quand l'application revient au premier plan.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Même les textes que Material fournit par défaut (boîtes de dialogue,
    // listes, boutons plats) suivent l'échelle de l'écran : Kivy ne laisse
    // aucune taille en dur, et `SF` vaut ici un facteur global.
    final base = ThemeData(
      brightness: Brightness.dark,
      fontFamily: 'NotoSansCJK',
      useMaterial3: true,
    );

    return MaterialApp(
      title: 'La Fuga',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        textTheme: scaleTextTheme(base.textTheme, scaleFactor * kFontBoost),
        primaryTextTheme: scaleTextTheme(
          base.primaryTextTheme,
          scaleFactor * kFontBoost,
        ),
      ),
      // Le texte doit occuper la même proportion de l'écran quel que soit le
      // réglage système, comme en Kivy où l'on refuse l'unité « sp » au profit
      // de pixels purs mis à l'échelle sur la largeur.
      builder: (context, child) => MediaQuery.withNoTextScaling(
        // Toutes les tailles sont exprimées en pixels de l'écran de référence
        // et mises à l'échelle de celui-ci : voir `ui/scale.dart`.
        child: FugaScale(child: child ?? const SizedBox.shrink()),
      ),
      home: const MenuScreen(),
    );
  }
}
