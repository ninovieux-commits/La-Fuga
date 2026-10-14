/// Le score des parties EN DIRECT entre lui et moi.
///
/// Nino : « le score ne doit plus marquer 4 / ... d'un côté et 15 / ... de
/// l'autre, mais juste 4 et 15. Ce système de score doit aussi marcher pour
/// les parties en direct. »
///
/// En correspondance, ces deux nombres viennent avec la partie (`mon_score` et
/// `score_adverse` : le cumul des parties gagnées entre nous). En direct, le
/// serveur ne les met pas dans `partie_trouvee` — mais il les tient dans le
/// profil, sous `h2h_direct_moi` et `h2h_direct_lui`, et c'est le même
/// `/get_profile` qui porte déjà la photo, le thème et l'étoile. Une requête
/// pour quatre réponses.
///
/// Le compte CHANGE pendant un match : chaque partie gagnée l'incrémente côté
/// serveur. D'où [resolve] avec `force`, qui repose la question en fin de
/// partie plutôt que de laisser un nombre périmé à l'écran.
library;

import 'online_service.dart';
import 'profile.dart';

class ScoresDirects {
  ScoresDirects._();

  /// pseudo en minuscules -> score en tête-à-tête. Partagé par tous les
  /// écrans, comme les photos et les décors.
  static final Map<String, HeadToHead> _cache = {};

  /// Pseudos pour lesquels la question a déjà été posée. Un serveur muet sur
  /// ces clés donne 0 - 0 : sans cette trace, on redemanderait sans fin.
  static final Set<String> _demandes = {};

  static String _cle(String pseudo) => pseudo.trim().toLowerCase();

  /// Ce qu'on sait TOUT DE SUITE, ou `null`. Le bandeau n'écrit alors aucun
  /// score, plutôt qu'un 0 - 0 qui serait faux.
  static HeadToHead? connu(String pseudo) =>
      pseudo.trim().isEmpty ? null : _cache[_cle(pseudo)];

  /// Retient un score lu dans un profil reçu par ailleurs.
  static void remember(String pseudo, HeadToHead score) {
    if (pseudo.trim().isEmpty) return;
    _cache[_cle(pseudo)] = score;
  }

  /// Va chercher le score s'il manque. `force` le redemande même connu : à la
  /// fin d'une partie du match, le serveur en a un nouveau.
  static Future<HeadToHead?> resolve(
    String pseudo, {
    OnlineService? online,
    bool force = false,
  }) async {
    final cle = _cle(pseudo);
    if (cle.isEmpty) return null;
    if (force) {
      _cache.remove(cle);
      _demandes.remove(cle);
    }
    final connu = _cache[cle];
    if (connu != null) return connu;
    if (_demandes.contains(cle)) return null;

    final service = online ?? OnlineService.instance;
    if (!service.isLoggedIn) return null;
    _demandes.add(cle);

    final r = await service.client.getProfile(pseudo);
    if (!r.isOk || r.data == null) return null;
    remember(pseudo, Profile.fromJson(r.data!).direct);
    return _cache[cle];
  }

  /// Oublie ce qu'on sait — à la déconnexion, et dans les tests.
  static void clear() {
    _cache.clear();
    _demandes.clear();
  }
}
