/// Un réglage validé se voit PARTOUT, tout de suite.
///
/// Nino : « les thèmes ne se mettent pas bien à jour. Quand on valide un
/// nouveau thème, la différence doit se charger dans toute l'app directement,
/// les pages ne doivent pas créer la modif une par une quand elles sont
/// rechargées. »
///
/// Un réglage n'était qu'une valeur lue au moment de dessiner : un écran déjà
/// construit gardait son ancien thème jusqu'à ce que quelque chose le
/// reconstruise. Et reconstruire la racine ne suffit pas — c'est le premier
/// test ci-dessous, et c'est ce qui rend l'abonnement nécessaire.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/suit_les_reglages.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deux écrans jumeaux qui lisent le thème en se dessinant et comptent leurs
/// dessins. Seule différence : l'un suit les réglages, l'autre non.
class EcranSuiveur extends StatefulWidget {
  const EcranSuiveur({super.key});

  @override
  State<EcranSuiveur> createState() => _EcranSuiveurState();
}

class _EcranSuiveurState extends State<EcranSuiveur> with SuitLesReglages {
  static int dessins = 0;
  static String dernierTheme = '';

  @override
  Widget build(BuildContext context) {
    dessins++;
    dernierTheme = Settings.instance.themeAxes.general;
    return Scaffold(body: Center(child: Text(dernierTheme)));
  }
}

class EcranSourd extends StatefulWidget {
  const EcranSourd({super.key});

  @override
  State<EcranSourd> createState() => _EcranSourdState();
}

class _EcranSourdState extends State<EcranSourd> {
  static int dessins = 0;
  static String dernierTheme = '';

  @override
  Widget build(BuildContext context) {
    dessins++;
    dernierTheme = Settings.instance.themeAxes.general;
    return Scaffold(body: Center(child: Text(dernierTheme)));
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
    await Settings.instance.setTheme('original');
    _EcranSourdState.dessins = 0;
    _EcranSuiveurState.dessins = 0;
  });

  /// Le menu, puis un écran empilé par-dessus — la pile de tous les jours.
  Future<void> empile(WidgetTester tester, {required bool suit}) async {
    final cle = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: cle,
        home: const Scaffold(body: Center(child: Text('LE MENU'))),
      ),
    );
    cle.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => suit ? const EcranSuiveur() : const EcranSourd(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('un écran EMPILÉ voit le nouveau thème sans être rouvert', (
    tester,
  ) async {
    await empile(tester, suit: true);
    expect(_EcranSuiveurState.dernierTheme, 'original');

    await Settings.instance.setTheme('medieval');
    await tester.pumpAndSettle();

    expect(
      _EcranSuiveurState.dernierTheme,
      'medieval',
      reason: 'il doit se repeindre là où il est, sans qu on le rouvre',
    );
    expect(find.text('medieval'), findsOneWidget);
  });

  testWidgets('sans l abonnement, il garde l ancien — c est le défaut', (
    tester,
  ) async {
    // La preuve que l'abonnement sert à quelque chose : le même écran, sans
    // lui, ne bouge pas d'un pixel.
    await empile(tester, suit: false);
    final avant = _EcranSourdState.dessins;

    await Settings.instance.setTheme('medieval');
    await tester.pumpAndSettle();

    expect(
      _EcranSourdState.dessins,
      avant,
      reason: 'il ne s est pas redessiné',
    );
    expect(_EcranSourdState.dernierTheme, 'original');
  });

  testWidgets('la LANGUE aussi se propage', (tester) async {
    await empile(tester, suit: true);
    final avant = _EcranSuiveurState.dessins;
    await Settings.instance.setLanguage('en');
    await tester.pumpAndSettle();
    expect(
      _EcranSuiveurState.dessins,
      greaterThan(avant),
      reason: 'une phrase traduite ne doit pas attendre un rechargement',
    );
    await Settings.instance.setLanguage('fr');
  });

  testWidgets('et l écran s en détache en partant', (tester) async {
    // Un écouteur laissé derrière ferait repeindre un écran démonté.
    await empile(tester, suit: true);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();

    await Settings.instance.setTheme('insectes');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('le volume et l instrument ne font PAS repeindre', () async {
    // Ils sont lus au moment de jouer un son. Les y mettre ferait repeindre
    // l'application entière à chaque mouvement du curseur.
    var preventions = 0;
    void compte() => preventions++;
    reglagesVisibles.addListener(compte);
    addTearDown(() => reglagesVisibles.removeListener(compte));

    await Settings.instance.setVolume(0.5);
    await Settings.instance.setInstrument('harpe');
    expect(preventions, 0);

    await Settings.instance.setTheme('dragon');
    expect(preventions, 1, reason: 'le thème, lui, se voit');
  });
}
