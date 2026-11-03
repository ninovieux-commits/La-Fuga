/// Les enveloppes : leur chrono, et ce qui se balance.
///
/// Nino : « il y a un minuteur de 48 heures sur chaque enveloppe. Quand le
/// minuteur s'est écoulé, l'enveloppe est supprimée automatiquement. Le
/// minuteur affiche le temps selon le modèle 48h00 -> 47h59 », puis « les
/// enveloppes qu'on peut ouvrir doivent osciller ».
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/game/enveloppe.dart';
import 'package:lafuga/i18n/translations.dart';
import 'package:lafuga/state/settings.dart';
import 'package:lafuga/ui/scale.dart';
import 'package:lafuga/ui/widgets/enveloppe_jeton.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Une enveloppe qui expire dans [reste], vue de [maintenant].
Enveloppe enveloppe(Duration reste, {bool deMoi = false}) {
  final maintenant = DateTime(2026, 11, 3, 12);
  return Enveloppe(
    id: 1,
    deMoi: deMoi,
    creeA: maintenant.millisecondsSinceEpoch ~/ 1000,
    expireA: maintenant.add(reste).millisecondsSinceEpoch ~/ 1000,
  );
}

final DateTime _maintenant = DateTime(2026, 11, 3, 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await Translations.load('fr');
    setScaleSize(const Size(393, 851));
  });

  group('Le chrono', () {
    test('une enveloppe qui vient d être posée affiche 48h00', () {
      expect(chronoEnveloppe(kEnveloppeVie), '48h00');
      // Et une demi-seconde plus tard aussi : on arrondit vers le haut à la
      // minute, sinon elle naîtrait déjà en retard.
      expect(
        chronoEnveloppe(kEnveloppeVie - const Duration(milliseconds: 500)),
        '48h00',
      );
    });

    test('une minute plus tard, 47h59', () {
      expect(
        chronoEnveloppe(kEnveloppeVie - const Duration(minutes: 1)),
        '47h59',
      );
    });

    test('les minutes prennent deux chiffres, les heures non', () {
      expect(chronoEnveloppe(const Duration(hours: 1, minutes: 5)), '1h05');
      expect(chronoEnveloppe(const Duration(minutes: 59)), '0h59');
      expect(chronoEnveloppe(const Duration(seconds: 30)), '0h01');
    });

    test('au bout, 0h00 — mais l enveloppe est déjà partie', () {
      expect(chronoEnveloppe(Duration.zero), '0h00');
      expect(chronoEnveloppe(const Duration(seconds: -5)), '0h00');
    });
  });

  group('Ce qui s ouvre, et ce qui se balance', () {
    test('celle qu on a reçue s ouvre, la sienne non', () {
      expect(enveloppe(kEnveloppeVie).ouvrable, isTrue);
      expect(enveloppe(kEnveloppeVie, deMoi: true).ouvrable, isFalse);
    });

    test('expirée se reconnaît, et ne reste rien', () {
      final morte = enveloppe(Duration.zero);
      expect(morte.expiree(_maintenant), isTrue);
      expect(morte.restant(_maintenant), Duration.zero);
    });

    Future<void> poser(WidgetTester tester, Enveloppe e) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: EnveloppeJeton(
                enveloppe: e,
                couleur: Colors.orange,
                maintenant: _maintenant,
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    /// Le SINUS de l'angle sous lequel le jeton est dessiné.
    ///
    /// Le sinus plutôt que le cosinus : à trois degrés près de zéro, le
    /// cosinus ne bouge pas du quatrième chiffre, tandis que le sinus suit
    /// l'angle et change même de signe.
    double penche(WidgetTester tester) {
      final t = tester.widget<Transform>(find.byKey(cleDuBalancement));
      return t.transform.storage[1];
    }

    testWidgets('celle qu on peut ouvrir oscille', (tester) async {
      await poser(tester, enveloppe(kEnveloppeVie));
      final depart = penche(tester);

      await tester.pump(kEnveloppeBalancement ~/ 4);
      expect(
        penche(tester),
        isNot(depart),
        reason: 'elle doit se balancer pour appeler l œil',
      );

      // Et elle ne s'arrête pas : un aller-retour plus tard, elle bouge
      // encore.
      final milieu = penche(tester);
      await tester.pump(kEnveloppeBalancement ~/ 2);
      expect(penche(tester), isNot(milieu));
    });

    testWidgets('la sienne se tient droite', (tester) async {
      await poser(tester, enveloppe(kEnveloppeVie, deMoi: true));
      expect(
        find.byKey(cleDuBalancement),
        findsNothing,
        reason: 'aucune rotation : elle n appelle personne',
      );
    });

    testWidgets('le chrono est écrit par-dessus le dessin', (tester) async {
      await poser(tester, enveloppe(const Duration(hours: 12, minutes: 34)));
      expect(find.text('12h34'), findsOneWidget);
    });
  });
}
