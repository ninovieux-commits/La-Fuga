/// La photo d'avatar d'un joueur, retrouvée par son pseudo — portage de
/// `resolve_avatar_photo` et `avatar_photo_for` (main.py).
///
/// Le serveur ne renvoie PAS la photo de l'adversaire avec une partie : ni
/// `corr_list` ni `partie_trouvee` ne la portent. Kivy va donc la chercher
/// par `get_profile`, la garde en mémoire, et rafraîchit l'avatar quand elle
/// arrive. Sans ce détour, l'adversaire n'a jamais de photo en partie — c'est
/// exactement ce qui manquait au portage.
library;

import 'online_service.dart';
import 'profile.dart';

/// Marqueur de l'IA : ce n'est pas une pièce de thème mais son portrait.
const String kDeepGreyPhoto = 'deepgrey';

class AvatarPhotos {
  AvatarPhotos._();

  /// pseudo en minuscules -> photo connue. Partagé par tous les écrans : une
  /// partie ouverte après une autre n'interroge pas deux fois le serveur.
  static final Map<String, String> _cache = {};

  /// Deep Grey n'est pas un compte : son portrait ne s'interroge pas.
  static bool isDeepGrey(String pseudo) {
    final p = pseudo.trim().toLowerCase();
    return p == 'deep grey' || p == 'deepgrey';
  }

  /// Ce qu'on peut afficher TOUT DE SUITE, sans attendre le réseau : le
  /// portrait de l'IA, ma propre photo, ou ce que le cache connaît déjà.
  /// Chaîne vide = la pièce par défaut, en attendant mieux.
  static String known(String pseudo, {OnlineService? online}) {
    if (pseudo.trim().isEmpty) return '';
    if (isDeepGrey(pseudo)) return kDeepGreyPhoto;
    final service = online ?? OnlineService.instance;
    if (pseudo == service.pseudo) {
      return service.session?.photo ?? '';
    }
    return _cache[pseudo.trim().toLowerCase()] ?? '';
  }

  /// Va chercher la photo si elle manque, et renvoie ce qu'on sait à l'arrivée.
  ///
  /// À appeler à l'ouverture d'une partie : le résultat sert à redessiner
  /// l'avatar. Ne demande rien au serveur si la réponse est déjà connue.
  static Future<String> resolve(String pseudo, {OnlineService? online}) async {
    if (pseudo.trim().isEmpty) return '';
    if (isDeepGrey(pseudo)) return kDeepGreyPhoto;
    final service = online ?? OnlineService.instance;
    final cle = pseudo.trim().toLowerCase();

    if (pseudo == service.pseudo) {
      final mienne = service.session?.photo ?? '';
      if (mienne.isNotEmpty) return mienne;
      // Le login ne renvoie pas toujours ma photo.
      await service.fetchMyPhoto();
      return service.session?.photo ?? '';
    }
    final connue = _cache[cle];
    if (connue != null) return connue;
    if (!service.isLoggedIn) return '';

    final r = await service.client.getProfile(pseudo);
    final photo = r.isOk && r.data != null
        ? Profile.fromJson(r.data!).photo
        : '';
    // On retient même une photo vide : inutile de redemander à chaque coup.
    _cache[cle] = photo;
    return photo;
  }

  /// Retient une photo déjà connue, sans rien demander au serveur : quand un
  /// écran l'a reçue par ailleurs, ou dans un test.
  static void remember(String pseudo, String photo) {
    if (pseudo.trim().isEmpty) return;
    _cache[pseudo.trim().toLowerCase()] = photo;
  }

  /// Oublie ce qu'on sait — à la déconnexion, et dans les tests.
  static void clear() => _cache.clear();
}
