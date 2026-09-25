/// Une touche a la même épaisseur partout.
///
/// Les écrans secondaires et les popups se réglaient chacun sur une valeur de
/// référence en LARGEUR — `S(52)`, `S(50)`, `S(48)`, `S(44)` — là où les
/// grandes touches du menu sont proportionnées à la HAUTEUR, `SH(0.06)`. Sur
/// un écran de téléphone, plus haut que large, ces touches sortaient deux fois
/// plus fines que celles du menu. Ce test les mesure toutes, dans trois formes
/// d'écran, et refuse le moindre écart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/net/online_service.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/screens/account_screen.dart';
import 'package:lafuga/ui/screens/conversations_screen.dart';
import 'package:lafuga/ui/screens/login_screen.dart';
import 'package:lafuga/ui/screens/menu_screen.dart';
import 'package:lafuga/ui/screens/parties_menu_screen.dart';
import 'package:lafuga/ui/screens/photo_picker.dart';
import 'package:lafuga/ui/screens/reader_screen.dart';
import 'package:lafuga/ui/screens/settings_screen.dart';
import 'package:lafuga/ui/screens/history_screen.dart';
import 'package:lafuga/ui/screens/theme_composer_screen.dart';
import 'package:lafuga/ui/screens/tuto_screen.dart';
import 'package:lafuga/ui/widgets/deep_grey_dialog.dart';
import 'package:lafuga/ui/widgets/end_dialogs.dart';
import 'package:lafuga/ui/widgets/first_launch.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:lafuga/ui/widgets/pause_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Size _phone = Size(393, 851);
const Size _small = Size(320, 640);
const Size _tablet = Size(834, 1112);

/// Les touches qui ne sont pas des touches d'écran : celles peintes dans une
/// case de correspondance, taillées à leur vignette comme en Kivy
/// (`size_hint=(0.8, 0.15)` du slot).
const Set<String> _inSlot = {
  'Accepter',
  'Refuser',
  'Annuler',
  'Revanche',
  'Fermer la case',
};

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

  /// Vérifie que chaque touche affichée fait l'épaisseur voulue.
  void expectAllTouches(WidgetTester tester, String where) {
    final wanted = touchHeight();
    var seen = 0;
    for (final element in find.byType(FugaButton).evaluate()) {
      final button = element.widget as FugaButton;
      if (_inSlot.contains(button.text)) continue;
      final height = tester.getSize(find.byWidget(button)).height;
      expect(
        height,
        moreOrLessEquals(wanted, epsilon: 0.5),
        reason:
            '$where : la touche « ${button.text} » fait '
            '${height.toStringAsFixed(1)} au lieu de ${wanted.toStringAsFixed(1)}',
      );
      seen++;
    }
    expect(seen, greaterThan(0), reason: '$where : aucune touche mesurée');
  }

  for (final (shape, size) in [
    ('un téléphone', _phone),
    ('un petit écran', _small),
    ('une tablette', _tablet),
  ]) {
    Future<void> open(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: FugaScale(child: home)));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    }

    group('sur $shape', () {
      // Le service est construit à l'ouverture de l'écran, pas à la
      // déclaration du groupe : les réglages ne sont chargés qu'au `setUp`.
      for (final (name, build) in <(String, Widget Function())>[
        ('le menu', () => MenuScreen(online: OnlineService())),
        ('la connexion', () => LoginScreen(online: OnlineService())),
        ('le compte', () => AccountScreen(online: OnlineService())),
        ('les réglages', () => const SettingsScreen()),
        ('le composeur de thème', () => const ThemeComposerScreen()),
        ('la galerie de photos', () => const PhotoPickerScreen()),
        ('le lecteur nmc', () => const ReaderScreen()),
        (
          'le menu des parties',
          () => PartiesMenuScreen(online: OnlineService()),
        ),
        ('le tuto', () => const TutoScreen()),
        ('la messagerie', () => ConversationsScreen(online: OnlineService())),
        ('l historique', () => HistoryScreen(online: OnlineService())),
      ]) {
        testWidgets('les touches de $name', (tester) async {
          await open(tester, build());
          expectAllTouches(tester, name);
        });
      }

      testWidgets('les touches de la pause', (tester) async {
        await open(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showPauseDialog(context, palette: paletteOf(kDefaultTheme)),
              child: const Text('pause'),
            ),
          ),
        );
        await tester.tap(find.text('pause'));
        await tester.pumpAndSettle();
        expectAllTouches(tester, 'la pause');
      });

      testWidgets('les touches du choix de camp contre Deep Grey', (
        tester,
      ) async {
        await open(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => askDeepGreyCamp(context),
              child: const Text('camp'),
            ),
          ),
        );
        await tester.tap(find.text('camp'));
        await tester.pumpAndSettle();
        expect(find.text('Blancs'), findsOneWidget);
        expectAllTouches(tester, 'le choix de camp');
      });

      for (final (name, show)
          in <(String, void Function(BuildContext, ThemePalette))>[
            (
              'la fin de partie',
              (context, palette) => showFinishDialog(
                context,
                palette: palette,
                title: 'Fugue',
                body: 'Les Blancs gagnent',
                onMenu: () {},
              ),
            ),
            (
              'la partie suivante',
              (context, palette) => showContinueDialog(
                context,
                palette: palette,
                title: 'Partie 2',
                body: 'Les camps changent',
                nextFirstBlanc: 'moi',
                onNext: () {},
              ),
            ),
            (
              'la suite en ligne',
              (context, palette) => showOnlineContinueDialog(
                context,
                palette: palette,
                title: 'Partie 2',
                body: 'Prêt ?',
                readySent: false,
                onReady: () {},
                onQuit: () {},
              ),
            ),
          ]) {
        testWidgets('les touches de $name', (tester) async {
          await open(
            tester,
            Builder(
              builder: (context) => TextButton(
                onPressed: () => show(context, paletteOf(kDefaultTheme)),
                child: const Text('ouvrir'),
              ),
            ),
          );
          await tester.tap(find.text('ouvrir'));
          await tester.pumpAndSettle();
          expectAllTouches(tester, name);
        });
      }

      testWidgets('les touches du choix de la langue', (tester) async {
        await open(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => askFirstLanguage(context),
              child: const Text('langue'),
            ),
          ),
        );
        await tester.tap(find.text('langue'));
        await tester.pumpAndSettle();
        expectAllTouches(tester, 'le choix de la langue');
      });
    });
  }
}
