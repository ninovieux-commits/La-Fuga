/// Une notification lue dans l'application ne doit pas rester dans le volet.
///
/// Nino : « quand je vois un message sur l'App, des fois la notif est
/// toujours là. Or elle devrait disparaître. »
///
/// Le « des fois » avait une cause exacte : `didChangeAppLifecycleState` ne
/// se déclenche qu'au CHANGEMENT d'état. Au lancement, il ne vient pas — et
/// l'application se croyait donc EN ARRIÈRE-PLAN tant qu'on ne l'avait pas
/// quittée puis rouverte. Un message reçu pendant ce temps s'affichait en
/// notification alors qu'on le lisait à l'écran, et personne ne l'effaçait
/// ensuite, faute de retour au premier plan.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/main.dart';
import 'package:lafuga/net/push_notifications.dart';
import 'package:lafuga/state/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lang_chosen': true,
      'tuto_seen': true,
    });
    await Settings.load();
    await PushNotifications.setForeground(false);
  });

  testWidgets('démarrer l application, c est être devant elle', (tester) async {
    expect(
      PushNotifications.auPremierPlan,
      isFalse,
      reason:
          'le défaut doit rester « derrière » : l isolat des messages '
          'reçus en arrière-plan ne construit aucun écran, et c est lui qui '
          'doit continuer d afficher les notifications',
    );

    await tester.pumpWidget(const FugaApp());
    await tester.pump();

    expect(
      PushNotifications.auPremierPlan,
      isTrue,
      reason:
          'sans ça, un message reçu avant la première mise en veille '
          's affiche en notification pendant qu on le lit',
    );
  });

  testWidgets('revenir efface, partir rétablit', (tester) async {
    await tester.pumpWidget(const FugaApp());
    await tester.pump();

    // Android passe par `inactive` avant `paused`, et Flutter refuse les
    // sauts : on suit le même chemin que l'appareil.
    for (final etat in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(etat);
      await tester.pump();
    }
    expect(PushNotifications.auPremierPlan, isFalse);

    for (final etat in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(etat);
      await tester.pump();
    }
    expect(PushNotifications.auPremierPlan, isTrue);
  });
}
