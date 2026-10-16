/// Le nom du fond d'un joueur, retrouvé par son pseudo.
///
/// Nino : « quand un joueur ouvre une nouvelle boîte de discussion, son app
/// reçoit le nom du fond. L'app de l'utilisateur a déjà l'image de fond au
/// même nom intégrée, alors elle crée sa boîte de discussion en utilisant
/// directement cette image de fond. »
///
/// Rien ne se télécharge : l'image est dans l'application, c'est le NOM qui
/// vient du serveur (`/get_profile` rend `theme`). Une fois connu, il est
/// gardé ici — la boîte s'ouvre alors du premier coup avec le bon décor, sans
/// passer par le mien.
///
/// Même dessin qu'`AvatarPhotos`, et la même requête les sert tous les deux :
/// `/get_profile` rend la photo ET le thème, on ne demande pas deux fois.
library;

import 'online_service.dart';
import 'resolution_profil.dart';

class DecorsConnus {
  DecorsConnus._();

  /// pseudo en minuscules -> nom du thème. Partagé par tous les écrans.
  static final Map<String, String> _cache = {};

  /// Pseudos pour lesquels on a DÉJÀ posé la question.
  ///
  /// Un serveur pas encore corrigé ne renvoie pas le thème : sans cette
  /// trace, on le redemanderait à chaque ouverture de la conversation, pour
  /// rien. Elle ne vit que le temps de la session — une fois le serveur
  /// corrigé, la question se repose au lancement suivant.
  static final Set<String> _demandes = {};

  /// Ce qu'on peut afficher TOUT DE SUITE, sans attendre le réseau.
  ///
  /// Chaîne vide = on ne sait pas encore. L'appelant doit alors attendre
  /// plutôt que d'afficher un décor qu'il faudrait remplacer.
  static String known(String pseudo) =>
      pseudo.trim().isEmpty ? '' : (_cache[pseudo.trim().toLowerCase()] ?? '');

  /// Retient un nom de thème reçu par ailleurs.
  ///
  /// On ne retient PAS une réponse vide : un serveur pas encore corrigé ne
  /// renvoie pas la clé, et la garder en mémoire interdirait de redemander
  /// une fois qu'il la renvoie.
  static void remember(String pseudo, String theme) {
    if (pseudo.trim().isEmpty || theme.trim().isEmpty) return;
    _cache[pseudo.trim().toLowerCase()] = theme.trim();
  }

  /// Va chercher le nom du fond s'il manque, et rend ce qu'on sait.
  ///
  /// La MÊME requête rend la photo : on la retient au passage, pour que
  /// l'écran n'en redemande pas une seconde. Et c'est bien ce cache-ci qui
  /// décide s'il faut demander : se fier à celui des photos laissait passer
  /// le cas « photo déjà connue, thème pas encore » — la conversation
  /// s'ouvrait alors sans aucun fond, et pour de bon.
  static Future<String> resolve(String pseudo, {OnlineService? online}) =>
      resoudreDepuisLeProfil(
        pseudo,
        cache: _cache,
        demandes: _demandes,
        online: online,
      );

  /// Oublie ce qu'on sait — à la déconnexion, et dans les tests.
  static void clear() {
    _cache.clear();
    _demandes.clear();
  }
}
