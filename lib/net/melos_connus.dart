/// Les DEUX classements d'un joueur : standard et Random Fuga.
///
/// Nino : « il faudrait que le mélo indiqué durant une partie soit le mélo du
/// mode correspondant (soit standard soit random) ».
///
/// Le serveur fait déjà la distinction pour une partie EN DIRECT : le mélo
/// qu'il met dans `partie_trouvee` est celui du mode joué, choisi au moment
/// d'entrer dans la file. En CORRESPONDANCE il envoie toujours le standard,
/// même sur une partie Random — d'où ce cache, qui tient les deux et laisse
/// l'écran prendre celui du mode.
///
/// Il se remplit du MÊME `/get_profile` qui porte déjà la photo, le thème,
/// l'étoile, le score en tête-à-tête et la devise.
library;

/// Les deux classements d'une personne.
typedef Melos = ({int standard, int random});

class MelosConnus {
  MelosConnus._();

  static final Map<String, Melos> _cache = {};

  static String _cle(String pseudo) => pseudo.trim().toLowerCase();

  /// Ce qu'on sait TOUT DE SUITE, ou `null`. L'écran n'écrit alors aucun
  /// classement plutôt qu'un chiffre faux — celui de l'autre mode.
  static Melos? connus(String pseudo) =>
      pseudo.trim().isEmpty ? null : _cache[_cle(pseudo)];

  /// Le classement du mode demandé, ou `null` si on ne le sait pas encore.
  static int? pourLeMode(String pseudo, {required bool random}) {
    final m = connus(pseudo);
    return m == null ? null : (random ? m.random : m.standard);
  }

  static void retiens(String pseudo, int standard, int random) {
    if (pseudo.trim().isEmpty) return;
    _cache[_cle(pseudo)] = (standard: standard, random: random);
  }

  static void clear() => _cache.clear();
}
