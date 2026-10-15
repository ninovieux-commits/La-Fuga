/// La devise d'un joueur, retenue d'une partie à l'autre.
///
/// Nino : « j'aimerai qu'au début d'une partie direct et à chaque fois qu'une
/// correspondance est ouverte, la devise du joueur apparaisse quelques
/// secondes sur la partie comme les messages. Mais ça ne doit pas apparaître
/// dans la boîte de chat. »
///
/// D'où un cache, et non un message : rien de tout cela ne passe par le
/// serveur de messages. La devise est posée dans la bande des bulles de
/// l'écran de jeu, et nulle part ailleurs — la conversation n'en saura rien.
///
/// Elle sort du MÊME `/get_profile` qui porte déjà la photo, le thème,
/// l'étoile et le score en tête-à-tête : `DecorsConnus.resolve` la retient au
/// passage, et l'écran de jeu la trouve déjà là quand il la demande.
library;

import 'online_service.dart';
import 'profile.dart';
import 'profils_connus.dart';

class DevisesConnues {
  DevisesConnues._();

  /// pseudo en minuscules -> sa devise. Partagé par tous les écrans.
  static final Map<String, String> _cache = {};

  static String _cle(String pseudo) => pseudo.trim().toLowerCase();

  /// Ce qu'on sait TOUT DE SUITE, ou une chaîne vide.
  ///
  /// Vide veut dire deux choses à la fois — « pas encore demandé » et « il
  /// n'en a pas » — et c'est voulu : dans les deux cas il n'y a rien à
  /// montrer, et l'écran de jeu n'a pas à faire la différence.
  static String connue(String pseudo) =>
      pseudo.trim().isEmpty ? '' : (_cache[_cle(pseudo)] ?? '');

  /// Retient une devise lue dans un profil reçu par ailleurs.
  static void retiens(String pseudo, String devise) {
    if (pseudo.trim().isEmpty) return;
    _cache[_cle(pseudo)] = devise.trim();
  }

  /// Sa devise, en la demandant au besoin.
  ///
  /// IL LUI FAUT SA PROPRE TRACE DE DEMANDES, et c'est exactement la leçon
  /// déjà écrite dans `DecorsConnus` : se fier au cache d'à côté laisse
  /// passer le cas « thème déjà connu, devise pas encore ». Il arrive tout
  /// le temps — la liste des parties de correspondance retient le décor de
  /// l'adversaire sans jamais lire son profil —, et la devise n'apparaissait
  /// alors jamais en correspondance. Mesuré.
  static Future<String> resolve(String pseudo, {OnlineService? online}) async {
    final cle = _cle(pseudo);
    if (cle.isEmpty) return '';
    final connu = _cache[cle];
    if (connu != null) return connu;
    if (_demandes.contains(cle)) return '';

    final service = online ?? OnlineService.instance;
    if (!service.isLoggedIn) return '';
    _demandes.add(cle);

    final r = await service.client.getProfile(pseudo);
    if (!r.isOk || r.data == null) return '';
    // UNE requête, plusieurs réponses : tout ce que le profil porte est
    // retenu d'un coup, et au même endroit pour les deux résolutions.
    retiensProfil(pseudo, Profile.fromJson(r.data!));
    return _cache[cle] ?? '';
  }

  /// Pseudos pour lesquels la question a déjà été posée. Sans cette trace, un
  /// joueur sans devise ferait redemander son profil à chaque ouverture.
  static final Set<String> _demandes = {};

  /// Oublie ce qu'on sait — à la déconnexion, et dans les tests.
  static void clear() {
    _cache.clear();
    _demandes.clear();
  }
}
