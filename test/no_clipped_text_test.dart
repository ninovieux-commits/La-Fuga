/// Aucun texte n'est coupé, sur aucun écran, dans aucune forme d'écran.
///
/// Le cas qui l'a révélé : le titre des écrans secondaires était écrit à sa
/// taille de référence BRUTE — un `32` fixe, sans passer par `SF` — dans un
/// bandeau haut de 24. Sur un téléphone, « Historique » sortait tranché par le
/// milieu. D'autres suivaient : la consigne du lecteur nmc pliée sur deux
/// lignes dans une bande d'une seule, les explications du tuto qui débordent
/// de leur cadre, et sur grand écran les étiquettes du menu dont la police
/// grandit plus vite que leur bande.
///
/// Le test mesure, pour chaque texte affiché, la place qu'il demande une fois
/// mis à la largeur qu'on lui donne, et la compare à celle qu'il reçoit.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/account_screen.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:lafuga/ui/screens/history_screen.dart';
import 'package:lafuga/ui/screens/login_screen.dart';
import 'package:lafuga/ui/screens/menu_screen.dart';
import 'package:lafuga/ui/screens/parties_menu_screen.dart';
import 'package:lafuga/ui/screens/photo_picker.dart';
import 'package:lafuga/ui/screens/reader_screen.dart';
import 'package:lafuga/ui/screens/settings_screen.dart';
import 'package:lafuga/ui/screens/theme_composer_screen.dart';
import 'package:lafuga/ui/screens/tuto_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Size _phone = Size(393, 851);
const Size _small = Size(320, 640);
const Size _tablet = Size(834, 1112);

/// Les deux FORMES extrêmes du marché du téléphone. C'est la forme, et elle
/// seule, qui fait diverger les deux familles de proportions : les touches
/// suivent la hauteur, les polices et les écarts suivent la largeur. Ni la
/// taille ni la résolution n'y changent quoi que ce soit.
const Size _large169 = Size(375, 667); // 16:9, le plus trapu — iPhone SE
const Size _etroit219 = Size(411, 960); // 21:9, le plus élancé — Xperia 1

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    resetScale();
  });
  tearDown(resetScale);

  for (final (shape, size) in [
    ('un téléphone', _phone),
    ('un petit écran', _small),
    ('une tablette', _tablet),
    ('un écran 16:9', _large169),
    ('un écran 21:9', _etroit219),
  ]) {
    for (final (name, build) in <(String, Widget Function())>[
      ('le menu', () => MenuScreen(online: OnlineService())),
      ('la connexion', () => LoginScreen(online: OnlineService())),
      ('le compte', () => AccountScreen(online: OnlineService())),
      ('les réglages', () => const SettingsScreen()),
      ('le composeur de thème', () => const ThemeComposerScreen()),
      ('la galerie de photos', () => const PhotoPickerScreen()),
      ('le lecteur nmc', () => const ReaderScreen()),
      ('le menu des parties', () => PartiesMenuScreen(online: OnlineService())),
      ('le tuto', () => const TutoScreen()),
      ('la messagerie', () => ConversationsScreen(online: OnlineService())),
      ('l historique', () => HistoryScreen(online: OnlineService())),
    ]) {
      testWidgets('rien n est coupé sur $name, sur $shape', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(home: FugaScale(child: build())));
        await tester.pumpAndSettle(const Duration(milliseconds: 300));

        var seen = 0;
        for (final element in find.byType(Text).evaluate()) {
          final widget = element.widget as Text;
          final data = widget.data;
          if (data == null || data.isEmpty) continue;
          final box = tester.getSize(find.byWidget(widget));
          if (box.height <= 0 || box.width <= 0) continue;

          final style = DefaultTextStyle.of(element).style.merge(widget.style);
          final painter = TextPainter(
            text: TextSpan(text: data, style: style),
            textDirection: TextDirection.ltr,
            maxLines: widget.maxLines,
            textScaler: TextScaler.noScaling,
          )..layout(maxWidth: box.width);

          expect(
            painter.height,
            lessThanOrEqualTo(box.height + 0.5),
            reason:
                '$name sur $shape : « ${data.replaceAll("\n", " ")} » demande '
                '${painter.height.toStringAsFixed(1)} de haut et n en reçoit '
                'que ${box.height.toStringAsFixed(1)}',
          );
          seen++;
        }
        expect(seen, greaterThan(0), reason: '$name : aucun texte mesuré');
      });
    }
  }
}
