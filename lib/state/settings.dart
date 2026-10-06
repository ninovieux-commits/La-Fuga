/// Réglages persistants — portage de `load_config` / `save_config` (main.py).
///
/// Kivy stocke un `config.txt` en `clé=valeur`. Ici, `SharedPreferences` : le
/// support change, les clés restent les mêmes, pour qu'un réglage garde le
/// même nom d'un bout à l'autre du projet.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../game/sound_plan.dart';
import '../i18n/translations.dart';
import '../net/api_client.dart';
import '../theme/themes.dart';

/// Clés de configuration, telles que `config.txt` les nomme.
/// Lien de soutien aux développeurs — repris de `SUPPORT_LINKS` (main.py).
///
/// Les autres plateformes n'ont pas de compte ouvert : Kivy n'en propose
/// qu'une, on n'en propose qu'une.
const String kSupportLink = 'https://paypal.me/lafugaonline';

/// Crédit des enregistrements d'instruments.
///
/// Les quatre instruments ne sont plus synthétisés mais enregistrés : une
/// synthèse écrite à la main, si soignée soit-elle, sonne comme un
/// synthétiseur. Leur licence — Creative Commons Attribution 3.0 — demande
/// que la source soit nommée, et c'est la contrepartie de pouvoir s'en
/// servir. Ce texte s'affiche sous le choix de l'instrument.
const String kCreditSons = 'Instruments : FluidR3_GM (CC BY 3.0)';

/// Durée par défaut de la glissée d'une pièce, en secondes.
///
/// Ce n'est pas un chiffre rond par hasard : c'est le réglage de Nino, relevé
/// sur sa capture d'écran.
const double kGlisseeDefaut = 0.10;

abstract final class SettingsKeys {
  static const theme = 'theme';
  static const volume = 'volume';
  static const lang = 'lang';
  static const instrument = 'instrument';
  static const serverUrl = 'server_url';
  static const slideSpeed = 'slide_speed';

  /// Premier lancement : la langue a-t-elle été choisie, le tuto vu ?
  static const langChosen = 'lang_chosen';
  static const tutoSeen = 'tuto_seen';
  static const onlineToken = 'online_token';
  static const onlinePseudo = 'online_pseudo';
  static const onlineMelo = 'online_melo';
  static const onlineMeloRandom = 'online_melo_random';
}

/// Réglages de l'application.
class Settings {
  Settings._(this._prefs);

  final SharedPreferences _prefs;

  static Settings? _instance;

  /// Réglages chargés. À appeler une fois au démarrage.
  static Future<Settings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return _instance = Settings._(prefs);
  }

  /// Instance déjà chargée. Lance une erreur si [load] n'a pas été appelé :
  /// mieux vaut un plantage net au démarrage qu'un réglage silencieusement
  /// perdu.
  static Settings get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('Settings.load() doit être appelé avant instance');
    }
    return i;
  }

  // ── Thème ────────────────────────────────────────────────────────────────

  /// Thème composite `general|pieces|logo|menu|board`, ou un nom simple.
  String get theme => _prefs.getString(SettingsKeys.theme) ?? kDefaultTheme;

  Future<void> setTheme(String value) =>
      _prefs.setString(SettingsKeys.theme, value);

  /// Les cinq axes du thème courant.
  ///
  /// Un nom sans barre verticale s'applique aux cinq axes : c'est
  /// l'ancien format, et il reste valide.
  ThemeAxes get themeAxes => ThemeAxes.parse(theme);

  // ── Son ──────────────────────────────────────────────────────────────────

  double get volume => _prefs.getDouble(SettingsKeys.volume) ?? 1.0;

  Future<void> setVolume(double value) =>
      _prefs.setDouble(SettingsKeys.volume, value.clamp(0.0, 1.0));

  /// L'instrument choisi, et toujours un instrument QUI EXISTE.
  ///
  /// Un nom inconnu reviendrait au premier. Sans ce garde-fou, retirer un
  /// instrument de la liste rendait muet tout téléphone qui l'avait choisi :
  /// la banque de sons cherchait des fichiers absents, chaque note était
  /// sautée en silence, et les réglages affichaient « Piano » par-dessus le
  /// marché — on n'aurait rien compris.
  String get instrument {
    final enregistre = _prefs.getString(SettingsKeys.instrument);
    return kInstruments.contains(enregistre) ? enregistre! : kInstruments.first;
  }

  Future<void> setInstrument(String value) async {
    if (!kInstruments.contains(value)) return;
    await _prefs.setString(SettingsKeys.instrument, value);
  }

  /// Durée de l'animation de glissement, en secondes. 0 = instantané.
  ///
  /// Le défaut est celui que Nino a réglé sur son téléphone : mesuré à 0,101 s
  /// au pixel près sur sa capture d'écran — pouce à 238, piste de 84 à 995, sur
  /// un curseur qui monte à 0,6 — et arrondi à la demi-centième. L'ancien
  /// défaut, 0,18 s, était presque deux fois plus lent.
  double get slideSpeed =>
      _prefs.getDouble(SettingsKeys.slideSpeed) ?? kGlisseeDefaut;

  Future<void> setSlideSpeed(double value) =>
      _prefs.setDouble(SettingsKeys.slideSpeed, value.clamp(0.0, 1.0));

  // ── Langue ───────────────────────────────────────────────────────────────

  String get language => _prefs.getString(SettingsKeys.lang) ?? kSourceLanguage;

  Future<void> setLanguage(String code) async {
    if (!kLanguageLabels.containsKey(code)) return;
    await _prefs.setString(SettingsKeys.lang, code);
    await Translations.load(code);
  }

  // ── Serveur ──────────────────────────────────────────────────────────────

  /// Permet de viser un autre serveur sans recompiler, comme la clé
  /// `server_url` de `config.txt`.
  String get serverUrl =>
      _prefs.getString(SettingsKeys.serverUrl) ?? kDefaultServerUrl;

  /// Au tout premier lancement, Kivy demande la langue puis lance le tuto.
  bool get languageChosen => _prefs.getBool(SettingsKeys.langChosen) ?? false;

  Future<void> markLanguageChosen() =>
      _prefs.setBool(SettingsKeys.langChosen, true);

  bool get tutorialSeen => _prefs.getBool(SettingsKeys.tutoSeen) ?? false;

  Future<void> markTutorialSeen() =>
      _prefs.setBool(SettingsKeys.tutoSeen, true);

  Future<void> setServerUrl(String value) =>
      _prefs.setString(SettingsKeys.serverUrl, value.trim());

  // ── Session en ligne ─────────────────────────────────────────────────────

  String? get onlineToken => _prefs.getString(SettingsKeys.onlineToken);
  String? get onlinePseudo => _prefs.getString(SettingsKeys.onlinePseudo);
  int get onlineMelo => _prefs.getInt(SettingsKeys.onlineMelo) ?? 1500;
  int get onlineMeloRandom =>
      _prefs.getInt(SettingsKeys.onlineMeloRandom) ?? 1500;

  Future<void> saveOnlineSession({
    required String token,
    required String pseudo,
    int melo = 1500,
    int meloRandom = 1500,
  }) async {
    await _prefs.setString(SettingsKeys.onlineToken, token);
    await _prefs.setString(SettingsKeys.onlinePseudo, pseudo);
    await _prefs.setInt(SettingsKeys.onlineMelo, melo);
    await _prefs.setInt(SettingsKeys.onlineMeloRandom, meloRandom);
  }

  /// Efface vraiment la session : une déconnexion doit ne rien laisser.
  Future<void> clearOnlineSession() async {
    await _prefs.remove(SettingsKeys.onlineToken);
    await _prefs.remove(SettingsKeys.onlinePseudo);
    await _prefs.remove(SettingsKeys.onlineMelo);
    await _prefs.remove(SettingsKeys.onlineMeloRandom);
    // Le thème appartient au COMPTE : le serveur le garde avec le profil et
    // le rend à la connexion. Le laisser en place faisait suivre celui du
    // compte précédent — et le compte suivant héritait de ses couleurs.
    //
    // Le volume, la langue, l'instrument et la vitesse de glissée restent :
    // ce sont des réglages de l'APPAREIL, les mêmes pour qui s'en sert.
    await _prefs.remove(SettingsKeys.theme);
  }
}

/// Les cinq axes composant un thème.
final class ThemeAxes {
  const ThemeAxes({
    required this.general,
    required this.pieces,
    required this.logo,
    required this.menu,
    required this.board,
  });

  /// Couleurs d'interface : touches, bandeaux, accents, grille.
  final String general;

  /// Rendu des pièces.
  final String pieces;

  /// Logo du menu.
  final String logo;

  /// Fond du menu.
  final String menu;

  /// Plateau.
  final String board;

  /// Applique un même thème aux cinq axes.
  factory ThemeAxes.uniform(String name) {
    final t = kThemes.containsKey(name) ? name : kDefaultTheme;
    return ThemeAxes(general: t, pieces: t, logo: t, menu: t, board: t);
  }

  /// Analyse `general|pieces|logo|menu|board`.
  ///
  /// Un nom seul, sans barre verticale, applique le même thème partout :
  /// c'est l'ancien format, resté valide.
  factory ThemeAxes.parse(String? source) {
    final s = (source ?? kDefaultTheme).trim();
    if (!s.contains('|')) return ThemeAxes.uniform(s);
    final parts = [...s.split('|'), ...List.filled(5, kDefaultTheme)].take(5);
    final v = parts
        .map((p) => kThemes.containsKey(p) ? p : kDefaultTheme)
        .toList();
    return ThemeAxes(
      general: v[0],
      pieces: v[1],
      logo: v[2],
      menu: v[3],
      board: v[4],
    );
  }

  @override
  String toString() => [general, pieces, logo, menu, board].join('|');
}
