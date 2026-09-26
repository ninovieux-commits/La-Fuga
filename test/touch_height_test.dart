/// Une touche a la même épaisseur partout.
///
/// Les écrans secondaires et les popups se réglaient chacun sur une valeur de
/// référence en LARGEUR — `S(52)`, `S(50)`, `S(48)`, `S(44)` — là où les
/// grandes touches du menu sont proportionnées à la HAUTEUR, `SH(0.06)`. Sur
/// un écran de téléphone, plus haut que large, ces touches sortaient deux fois
/// plus fines que celles du menu. Ce test les mesure toutes, dans trois formes
/// d'écran, et refuse le moindre écart.
///
/// Les champs de saisie ne sont PAS mesurés ici : la boîte d'un `TextField` ne
/// dit rien de ce qu'on VOIT. C'est exactement ce qui m'a trompé — la boîte
/// faisait bien 51 px pendant que la barre peinte sur le téléphone en faisait
/// 19. La barre de recherche a donc sa propre épreuve, en pixels :
/// `menu_search_bar_test.dart`.
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
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/move_generator.dart';
import 'package:lafuga/engine/piece.dart';
import 'package:lafuga/game/nmc.dart';
import 'package:lafuga/state/local_games.dart';
import 'package:lafuga/ui/screens/history_screen.dart';
import 'package:lafuga/ui/screens/theme_composer_screen.dart';
import 'package:lafuga/ui/screens/tuto_screen.dart';
import 'package:lafuga/ui/widgets/corr_slot.dart';
import 'package:lafuga/ui/widgets/deep_grey_dialog.dart';
import 'package:lafuga/ui/widgets/end_dialogs.dart';
import 'package:lafuga/ui/widgets/first_launch.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:lafuga/ui/widgets/pause_dialog.dart';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

const Size _phone = Size(393, 851);
const Size _small = Size(320, 640);
const Size _tablet = Size(834, 1112);

/// Les touches d'une case de correspondance ne sont pas des touches d'écran :
/// elles sont taillées à leur vignette, comme en Kivy. `corr_slot_test.dart`
/// les vérifie à leur propre mesure. L'exclusion est structurelle et non par
/// intitulé : « Fermer » et « Annuler » sont aussi de vraies touches ailleurs.
bool _inSlot(WidgetTester tester, Widget button) => find
    .ancestor(of: find.byWidget(button), matching: find.byType(CorrSlot))
    .evaluate()
    .isNotEmpty;

/// Une partie jouable, pour peupler l'historique.
List<String> _quelquesCoups(int nombre) {
  var board = Board.initial();
  var camp = Camp.blanc;
  final coups = <String>[];
  for (var i = 0; i < nombre; i++) {
    final legaux = generateMoves(
      board,
      camp,
    ).where((m) => !m.fugue && m.matOn == null && m.fugueBy == null).toList();
    final coup = legaux[i % legaux.length];
    coups.add(notationOn(board, coup));
    board = coup.board;
    camp = camp.opposite;
  }
  return coups;
}

const _partie = NmcMeta(
  date: '2026-09-19',
  player1: 'Nino',
  player2: 'Deep Grey',
  blanc: 'Nino',
  objectif: 'partie',
  cadence: '5min',
  result: '1-0',
  method: 'fugue',
  points: '2',
);

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
      if (_inSlot(tester, button)) continue;
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

      // L'historique VIDE ne montre aucune partie, donc aucune touche
      // « Copier » : sa hauteur, calculée sur la LARGEUR, n'a jamais été
      // mesurée. Un écran vide ne prouve rien sur les touches qu'il cache.
      testWidgets('les touches de l historique AVEC une partie', (
        tester,
      ) async {
        final dossier = Directory.systemTemp.createTempSync('lafuga_touches');
        addTearDown(() => dossier.deleteSync(recursive: true));
        final magasin = LocalGamesStore(directory: dossier);
        await magasin.save(_partie, _quelquesCoups(4), name: 'partie1');
        await open(
          tester,
          HistoryScreen(
            online: OnlineService(),
            mode: HistoryMode.local,
            store: magasin,
          ),
        );
        expect(
          find.text('Copier'),
          findsWidgets,
          reason: 'la partie enregistrée ne s affiche pas : test sans valeur',
        );
        expectAllTouches(tester, 'l historique avec une partie');
      });

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
