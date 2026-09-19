/// Point d'entrée de La Fuga.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'i18n/translations.dart';
import 'state/settings.dart';
import 'ui/screens/menu_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // L'app Kivy est verrouillée en portrait (buildozer.spec) : le plateau est
  // calé sur la largeur de l'écran.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final settings = await Settings.load();
  await Translations.load(settings.language);

  runApp(const FugaApp());
}

class FugaApp extends StatelessWidget {
  const FugaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'La Fuga',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'NotoSansCJK',
        useMaterial3: true,
      ),
      // Le texte doit occuper la même proportion de l'écran quel que soit le
      // réglage système, comme en Kivy où l'on refuse l'unité « sp » au profit
      // de pixels purs mis à l'échelle sur la largeur.
      builder: (context, child) =>
          MediaQuery.withNoTextScaling(child: child ?? const SizedBox.shrink()),
      home: const MenuScreen(),
    );
  }
}
