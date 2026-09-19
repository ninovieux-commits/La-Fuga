/// Traductions — portage de `T()` et `set_language()` (main.py).
///
/// Le **français est la clé**, pas une valeur : `T("Se connecter")` renvoie la
/// chaîne française telle quelle quand la langue courante est le français, et
/// sa traduction sinon. Une clé sans traduction retombe sur le français, comme
/// en Kivy — un texte non traduit s'affiche, il ne disparaît jamais.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Langues proposées, dans l'ordre du menu Kivy.
const Map<String, String> kLanguageLabels = {
  'fr': 'Français',
  'en': 'English',
  'de': 'Deutsch',
  'es': 'Español',
  'it': 'Italiano',
  'zh': '中文',
  'ja': '日本語',
  'ko': '한국어',
  'ru': 'Русский',
  'pt': 'Português',
};

/// Langue source : ses clés sont les chaînes elles-mêmes.
const String kSourceLanguage = 'fr';

/// Dictionnaire de la langue courante.
class Translations {
  Translations._(this.language, this._entries, this._story);

  final String language;
  final Map<String, String> _entries;
  final String _story;

  /// Français : aucun fichier à charger, les clés sont les valeurs.
  static Translations get french =>
      Translations._(kSourceLanguage, const {}, _frenchStory);

  static Translations? _current;

  /// Traductions actuellement chargées (français tant que rien n'est chargé).
  static Translations get current => _current ??= french;

  /// Charge une langue depuis les ressources. Repli silencieux sur le français
  /// si la langue est inconnue ou le fichier illisible : mieux vaut une
  /// interface en français qu'une interface vide.
  static Future<Translations> load(String language) async {
    if (language == kSourceLanguage || !kLanguageLabels.containsKey(language)) {
      return _current = french;
    }
    try {
      final raw = await rootBundle.loadString('assets/i18n/$language.json');
      final entries = (jsonDecode(raw) as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v as String),
      );
      final storyRaw = await rootBundle.loadString('assets/i18n/story.json');
      final stories = jsonDecode(storyRaw) as Map<String, dynamic>;
      return _current = Translations._(
        language,
        entries,
        (stories[language] as String?) ?? _frenchStory,
      );
    } catch (_) {
      return _current = french;
    }
  }

  /// Traduction d'une chaîne française.
  String call(String source) {
    if (language == kSourceLanguage) return source;
    return _entries[source] ?? source;
  }

  /// L'histoire du jeu, affichée au clic sur le logo du menu.
  String get story => _story;

  /// Nombre de clés chargées, utile aux tests et au diagnostic.
  int get length => _entries.length;
}

/// Raccourci global, à l'image du `T()` de Kivy.
String T(String source) => Translations.current(source);

const String _frenchStory =
    "Deux frères perdirent la vie dans un duel à mort. Ils régnaient sur le "
    "royaume ensemble jusqu'à ce qu'un désaccord les pousse à s'affronter. "
    "Chacun avait un fils, aujourd'hui prétendant au trône.\n\n"
    "Les sujets des deux partis opposés décidèrent de pousser les deux cousins "
    "héritiers dans une course mortelle pour désigner lequel des deux prendrait "
    "le pouvoir et ainsi profiter du jeune âge de ceux-ci afin de les manipuler "
    "à leur avantage.\n\n"
    "Les deux rivaux involontaires, épaulés par les nurses les ayant élevés et "
    "tenant à eux plus qu'à leur propre vie, se virent obligés d'entrer dans une "
    "poursuite sans merci, et seront peut-être même contraints d'assassiner leur "
    "seule famille restante afin de survivre et de s'asseoir sur le trône.";
