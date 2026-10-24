/// La touche « Pré-coups » : sa place, sa taille, et toutes ses langues.
///
/// Elle n'est plus dans le bandeau. « Analyser » et « Pré-coups » sont
/// maintenant les deux touches du popup de la boule de cristal — le risque de
/// rognage a suivi les mots, et c'est donc là qu'on le surveille.
///
/// ## Ce que ce fichier peut prouver, et ce qu'il ne peut pas
///
/// En test, Flutter dessine avec la police **Ahem**, dont chaque glyphe est un
/// carré d'un cadratin : « Pré-coups » y réclame exactement neuf fois la
/// taille de police. Une largeur mesurée ici ne dit donc RIEN de la largeur
/// sur un vrai téléphone — elle compte des caractères.
///
/// Ce fichier ne prétend donc pas qu'un mot « tient ». Il prouve deux choses
/// qui, elles, ne dépendent pas de la police :
///
///  1. **Le garde-fou contre le rognage est en place.** Les touches ont une
///     largeur fixe, et Flutter coupe un texte trop long sans la moindre
///     erreur. Un texte rogné et un texte réduit ont EXACTEMENT la même
///     géométrie — seuls les pixels dessinés diffèrent, et un test de widget
///     ne les voit pas. Ce test vérifie donc la présence du mécanisme
///     (`FittedBox`), pas le résultat peint : il tombe si on le retire.
///  2. **Aucune n'est réduite au point d'être illisible** — mesuré non pas en
///     pixels absolus, mais PAR RAPPORT à « Analyser », qui partage sa touche
///     depuis le début et dont on sait qu'elle se lit bien. La police de test
///     suffit pour cette comparaison : les deux mots y sont mesurés à la même
///     aune.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/theme/themes.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/boule_dialog.dart';
import 'package:lafuga/ui/widgets/fuga_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Les deux FORMES extrêmes du marché, comme `no_clipped_text_test` : c'est la
/// forme qui fait diverger les proportions, pas la taille.
const Map<String, Size> _formes = {
  '16:9 le plus trapu': Size(375, 667),
  '21:9 le plus élancé': Size(411, 960),
};

/// Au-delà, le mot serait sensiblement plus petit que « Analyser » dans la
/// même touche, et commencerait à se remarquer.
const double _reductionMax = 1.30;

String _traduction(String cle, String langue) {
  if (langue == 'fr') return cle;
  final d =
      jsonDecode(File('assets/i18n/$langue.json').readAsStringSync())
          as Map<String, dynamic>;
  return (d[cle] ?? cle) as String;
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
  });
  tearDown(resetScale);

  /// Le popup de la boule, ouvert, avec les deux touches qu'on veut comparer.
  Future<void> boule(WidgetTester tester, Size taille) async {
    tester.view.physicalSize = taille;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    setScaleSize(taille);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: GestureDetector(
                onTap: () => unawaited(
                  ouvrirBoule(
                    context,
                    palette: paletteOf('foret'),
                    onAnalyse: () {},
                    onPremove: () {},
                  ),
                ),
                child: const Text('boule'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('boule'));
    await tester.pumpAndSettle();
  }

  /// Largeur que [mot] réclame, dans le style de la touche « Pré-coups ».
  double reclame(WidgetTester tester, String mot) {
    final style = tester.widget<Text>(find.text(T('Pré-coups'))).style;
    return (TextPainter(
      text: TextSpan(text: mot, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout()).width;
  }

  group('Le garde-fou contre le rognage est en place', () {
    for (final forme in _formes.entries) {
      testWidgets(forme.key, (tester) async {
        await boule(tester, forme.value);
        // LES DEUX étiquettes du popup, pas seulement la nôtre : elles se
        // partagent la largeur à égalité et ont dix langues à porter.
        for (final label in [T('Pré-coups'), T('Analyser')]) {
          final boites = find.ancestor(
            of: find.text(label),
            matching: find.byType(FittedBox),
          );
          expect(
            boites,
            findsWidgets,
            reason: '« $label » n a plus rien qui le protège du rognage',
          );
          expect(
            tester.widget<FittedBox>(boites.first).fit,
            BoxFit.scaleDown,
            reason: 'scaleDown : il rétrécit s il le faut, et pas autrement',
          );
        }
      });
    }
  });

  group('Aucune langue n est réduite au point de se remarquer', () {
    for (final forme in _formes.entries) {
      for (final langue in kLanguageLabels.keys) {
        testWidgets('${forme.key} — $langue', (tester) async {
          await boule(tester, forme.value);
          final mot = _traduction('Pré-coups', langue);
          final reference = reclame(tester, T('Analyser'));
          final demande = reclame(tester, mot);
          expect(
            demande / reference,
            lessThanOrEqualTo(_reductionMax),
            reason:
                '« $mot » réclame ${(demande / reference).toStringAsFixed(2)} '
                'fois la place d « Analyser » dans la même touche : il y sera '
                'nettement plus petit, et cela se verra',
          );
        });
      }
    }
  });

  // Le débordement du bandeau et le trou de l'appareil photo se mesurent
  // désormais dans `boutons_fixes_test`, mode par mode. Le test qui vivait
  // ici entassait TOUTES les touches dans une seule rangée : aucun écran ne
  // les montre toutes, et depuis que le centre est réservé à l'appareil
  // photo, ce bandeau impossible déborde sans rien prouver.

  testWidgets('elle a exactement la taille d « Analyser »', (tester) async {
    await boule(tester, const Size(393, 851));
    Size taille(String label) =>
        tester.getSize(find.widgetWithText(FugaButton, label));
    expect(taille(T('Pré-coups')), taille(T('Analyser')));
    expect(
      tester.widget<Text>(find.text(T('Pré-coups'))).style?.fontSize,
      tester.widget<Text>(find.text(T('Analyser'))).style?.fontSize,
      reason: 'même police de départ : la réduction ne joue que si elle doit',
    );
  });
}
