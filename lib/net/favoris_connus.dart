/// Qui est dans MES favoris, à l'instant.
///
/// Nino : « il doit y avoir une étoile dans les infos de joueur s'il est
/// favori et cette étoile doit disparaître s'il est retiré. »
///
/// L'étoile doit donc suivre la touche « Favori / Retirer », qui est ailleurs
/// — dans un popup, sur le profil. Un cache partagé fait le lien : celui qui
/// ajoute ou retire le dit ici, et tout écran qui écoute se redessine.
///
/// La relation est à SENS UNIQUE : ce sont MES favoris. Que l'autre m'ait ou
/// non dans les siens ne regarde pas cette étoile.
library;

import 'package:flutter/foundation.dart';

import 'online_service.dart';
import 'profile.dart';

/// Les favoris connus, et qui prévient quand ça change.
class FavorisConnus extends ChangeNotifier {
  FavorisConnus._();

  static final FavorisConnus instance = FavorisConnus._();

  /// pseudo en minuscules -> dans mes favoris ou non.
  final Map<String, bool> _cache = {};

  /// Pseudos pour lesquels la question a déjà été posée.
  ///
  /// Un serveur pas encore corrigé ne renvoie pas la clé : sans cette trace,
  /// on la redemanderait à chaque ouverture d'écran, pour rien.
  final Set<String> _demandes = {};

  static String _cle(String pseudo) => pseudo.trim().toLowerCase();

  /// Ce qu'on sait TOUT DE SUITE. `null` = on ne sait pas encore, et l'étoile
  /// s'abstient plutôt que de mentir dans un sens ou dans l'autre.
  bool? connu(String pseudo) =>
      pseudo.trim().isEmpty ? null : _cache[_cle(pseudo)];

  /// Retient une réponse, et prévient si elle change quelque chose.
  void retiens(String pseudo, bool favori) {
    if (pseudo.trim().isEmpty) return;
    final cle = _cle(pseudo);
    if (_cache[cle] == favori) return;
    _cache[cle] = favori;
    notifyListeners();
  }

  /// Va chercher la réponse si elle manque.
  Future<bool> demande(String pseudo, {OnlineService? online}) async {
    final cle = _cle(pseudo);
    if (cle.isEmpty) return false;
    final su = _cache[cle];
    if (su != null) return su;
    if (_demandes.contains(cle)) return false;

    final service = online ?? OnlineService.instance;
    if (!service.isLoggedIn) return false;
    _demandes.add(cle);

    final r = await service.client.getProfile(pseudo);
    if (!r.isOk || r.data == null) return false;
    // Un serveur qui ne renvoie pas la clé donne faux : on retient cette
    // réponse-là aussi, sinon chaque écran la redemanderait sans fin.
    retiens(pseudo, Profile.fromJson(r.data!).isFavorite);
    return _cache[cle] ?? false;
  }

  /// Oublie tout — à la déconnexion, et dans les tests.
  void oublie() {
    _cache.clear();
    _demandes.clear();
    notifyListeners();
  }
}
