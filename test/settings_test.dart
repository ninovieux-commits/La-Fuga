/// Réglages : valeurs par défaut, persistance, et composition des thèmes.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/state/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prefs d'une appli déjà lancée une fois : ni choix de langue, ni tuto —
/// ils n'apparaissent qu'au tout premier démarrage.
const Map<String, Object> _launched = {'lang_chosen': true, 'tuto_seen': true};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(_launched));

  group('Valeurs par défaut', () {
    test('un premier lancement part sur des réglages sains', () async {
      final s = await Settings.load();
      expect(s.theme, 'original');
      expect(s.language, 'fr');
      expect(s.volume, 1.0);
      expect(s.instrument, 'piano');
      expect(s.slideSpeed, 0.18);
      expect(s.serverUrl, 'https://fuga-online.fr');
      expect(s.onlineToken, isNull);
    });
  });

  group('Persistance', () {
    test('les réglages survivent à un rechargement', () async {
      final s = await Settings.load();
      await s.setVolume(0.4);
      await s.setInstrument('orgue');
      await s.setLanguage('en');
      await s.setTheme('dragon');

      final again = await Settings.load();
      expect(again.volume, 0.4);
      expect(again.instrument, 'orgue');
      expect(again.language, 'en');
      expect(again.theme, 'dragon');
    });

    test('le volume reste entre 0 et 1', () async {
      final s = await Settings.load();
      await s.setVolume(2.5);
      expect(s.volume, 1.0);
      await s.setVolume(-1);
      expect(s.volume, 0.0);
    });

    test('un instrument inconnu est refusé', () async {
      final s = await Settings.load();
      await s.setInstrument('kazoo');
      expect(s.instrument, 'piano', reason: 'on garde le précédent');
    });

    test('une langue inconnue est refusée', () async {
      final s = await Settings.load();
      await s.setLanguage('xx');
      expect(s.language, 'fr');
    });
  });

  group('Session en ligne', () {
    test('une session se sauvegarde et se relit', () async {
      final s = await Settings.load();
      await s.saveOnlineSession(
        token: 'jeton',
        pseudo: 'Nino',
        melo: 1620,
        meloRandom: 1480,
      );
      final again = await Settings.load();
      expect(again.onlineToken, 'jeton');
      expect(again.onlinePseudo, 'Nino');
      expect(again.onlineMelo, 1620);
      expect(again.onlineMeloRandom, 1480);
    });

    test('la déconnexion ne laisse rien derrière elle', () async {
      final s = await Settings.load();
      await s.saveOnlineSession(token: 'jeton', pseudo: 'Nino');
      await s.clearOnlineSession();

      final again = await Settings.load();
      expect(again.onlineToken, isNull);
      expect(again.onlinePseudo, isNull);
      expect(again.onlineMelo, 1500, reason: 'retour au mélo par défaut');
    });
  });

  group('Composition de thème', () {
    test('un nom seul s applique aux cinq axes', () {
      final axes = ThemeAxes.parse('dragon');
      expect(axes.general, 'dragon');
      expect(axes.pieces, 'dragon');
      expect(axes.logo, 'dragon');
      expect(axes.menu, 'dragon');
      expect(axes.board, 'dragon');
    });

    test('un composite répartit les cinq axes', () {
      final axes = ThemeAxes.parse('ocean|dragon|etoile|foret|medieval');
      expect(axes.general, 'ocean');
      expect(axes.pieces, 'dragon');
      expect(axes.logo, 'etoile');
      expect(axes.menu, 'foret');
      expect(axes.board, 'medieval');
    });

    test('un axe inconnu retombe sur le thème par défaut', () {
      final axes = ThemeAxes.parse('ocean|inexistant|etoile|foret|medieval');
      expect(axes.general, 'ocean');
      expect(axes.pieces, 'original');
    });

    test('un composite incomplet est complété', () {
      final axes = ThemeAxes.parse('ocean|dragon');
      expect(axes.general, 'ocean');
      expect(axes.pieces, 'dragon');
      expect(axes.logo, 'original');
    });

    test('aller-retour texte', () {
      const source = 'ocean|dragon|etoile|foret|medieval';
      expect(ThemeAxes.parse(source).toString(), source);
    });

    test('une valeur absente donne le thème par défaut', () {
      expect(ThemeAxes.parse(null).general, 'original');
      expect(ThemeAxes.parse('').general, 'original');
    });
  });
}
