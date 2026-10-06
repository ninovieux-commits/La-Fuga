/// Aucun libellé de touche n'est tranché, dans aucune langue.
///
/// Nino : « On peut pas faire que quoi qu'il arrive le texte se réduit de
/// taille pour rentrer dans la touche ? »
///
/// ## Pourquoi la garantie est dans la touche, et pas dans une mesure
///
/// Une touche a une largeur, son libellé en a une autre, et Flutter coupe
/// l'excédent **sans lever la moindre erreur**. Rien ne plante, rien ne
/// s'affiche en rouge : le mot part simplement amputé, et seul l'œil le voit.
/// Dix langues de longueurs différentes multiplient les occasions.
///
/// On ne peut pas non plus le vérifier en mesurant. En test, Flutter dessine
/// avec **Ahem**, dont chaque glyphe est un carré d'un cadratin : une largeur
/// mesurée ici compte des caractères, pas des pixels. Tout libellé de plus de
/// quatre lettres y « déborderait », y compris ceux qui tiennent parfaitement
/// sur un vrai téléphone. Une mesure ne donnerait que des fausses alertes.
///
/// La garantie est donc **structurelle** : chaque touche réduit son texte si
/// besoin, et c'est vrai de toute langue, toute police, tout écran — sans rien
/// avoir à mesurer. Ce fichier vérifie que le mécanisme est bien partout, et
/// tombe le jour où une touche s'en passe.
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
import 'package:lafuga/ui/screens/settings_screen.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:lafuga/ui/widgets/game_top_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Toute touche de ce type réduit son libellé plutôt que de le couper.
void verifieReduction(WidgetTester tester, Finder touches, String quoi) {
  final n = touches.evaluate().length;
  expect(n, greaterThan(0), reason: '$quoi : aucune touche trouvée');
  for (var i = 0; i < n; i++) {
    final textes = find.descendant(
      of: touches.at(i),
      matching: find.byType(Text),
    );
    if (textes.evaluate().isEmpty) continue;
    final libelle = (textes.evaluate().first.widget as Text).data ?? '';
    final boites = find.descendant(
      of: touches.at(i),
      matching: find.byType(FittedBox),
    );
    expect(
      boites,
      findsWidgets,
      reason: '$quoi : « $libelle » n a rien qui le protège du rognage',
    );
    expect(
      (boites.evaluate().first.widget as FittedBox).fit,
      BoxFit.scaleDown,
      reason: '$quoi : « $libelle » doit rétrécir, et seulement s il le faut',
    );
  }
}

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

  // Le lecteur de partie n'a aucune FugaButton : ses touches sont celles du
  // bandeau, vérifiées par le test qui suit ce groupe.
  group('Les touches du menu et des écrans', () {
    for (final (nom, build) in <(String, Widget Function())>[
      ('le menu', () => MenuScreen(online: OnlineService())),
      ('la connexion', () => LoginScreen(online: OnlineService())),
      ('le compte', () => AccountScreen(online: OnlineService())),
      ('les réglages', () => const SettingsScreen()),
      ('le menu des parties', () => PartiesMenuScreen(online: OnlineService())),
      ('la messagerie', () => ConversationsScreen(online: OnlineService())),
      ('l historique', () => HistoryScreen(online: OnlineService())),
    ]) {
      testWidgets('rien ne sera tranché sur $nom', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(home: FugaScale(child: build())));
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
        verifieReduction(tester, find.byType(FugaButton), nom);
      });
    }
  });

  testWidgets('et les touches du bandeau de partie', (tester) async {
    setScaleSize(const Size(393, 851));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 851 * 7 / 104,
            child: GameTopBar(
              palette: paletteOf('foret'),
              color: Colors.grey,
              onFlip: () {},
              onPause: () {},
              onMenu: () {},
              onChat: () {},
              onAnalyse: () {},
              onPremove: () {},
              onCopyNmc: () {},
              onDeepGrey: () {},
              onToggleAiMode: () {},
              aiDeepMode: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Toutes les touches LARGES du bandeau à la fois : c'est leur largeur
    // fixe qui les expose, et les dix langues ne font pas la même longueur.
    for (final libelle in [
      T('Retour au menu'),
      T('Chat'),
      T('Profond'),
      T('Copier'),
      T('Analyser'),
      T('Pré-coups'),
      'Deep Grey',
    ]) {
      final boites = find.ancestor(
        of: find.text(libelle),
        matching: find.byType(FittedBox),
      );
      expect(
        boites,
        findsWidgets,
        reason: '« $libelle » n a rien qui le protège du rognage',
      );
      expect(
        tester.widget<FittedBox>(boites.first).fit,
        BoxFit.scaleDown,
        reason: '« $libelle » doit rétrécir, et seulement s il le faut',
      );
    }
  });
}
