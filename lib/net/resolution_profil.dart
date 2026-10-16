/// Aller chercher une information de profil, une seule fois.
///
/// Deux caches — le décor et la devise — avaient le MÊME `resolve`, au nom de
/// leur table près : vingt lignes recopiées. Ce n'est pas anodin, parce que
/// ces vingt lignes portent deux pièges déjà payés :
///
///   — **chaque cache a besoin de SA PROPRE trace de demandes.** Se fier à
///     celle d'à côté laisse passer le cas « thème déjà connu, devise pas
///     encore » — qui arrive tout le temps, la liste des correspondances
///     retenant le décor sans jamais lire un profil. La devise n'apparaissait
///     alors jamais en correspondance. Mesuré, puis corrigé.
///   — **la trace sert même quand la réponse est vide.** Un joueur sans
///     devise, ou un serveur qui ne renvoie pas la clé, ferait sinon
///     redemander son profil à chaque ouverture.
///
/// En passant la table et la trace en paramètres, les deux restent séparées —
/// c'est le but — mais la mécanique n'est plus écrite qu'une fois.
library;

import 'online_service.dart';
import 'profile.dart';
import 'profils_connus.dart';

/// Rend ce qu'on sait de [pseudo] dans [cache], en le demandant au besoin.
///
/// Chaîne vide quand on ne sait pas : l'appelant décide si cela veut dire
/// « pas encore » ou « il n'y en a pas ».
Future<String> resoudreDepuisLeProfil(
  String pseudo, {
  required Map<String, String> cache,
  required Set<String> demandes,
  OnlineService? online,
}) async {
  final cle = pseudo.trim().toLowerCase();
  if (cle.isEmpty) return '';
  final connu = cache[cle];
  if (connu != null) return connu;
  if (demandes.contains(cle)) return '';

  final service = online ?? OnlineService.instance;
  if (!service.isLoggedIn) return '';
  demandes.add(cle);

  final r = await service.client.getProfile(pseudo);
  if (!r.isOk || r.data == null) return '';
  // UNE requête, plusieurs réponses : tout ce que le profil porte est retenu
  // d'un coup, et au même endroit pour toutes les résolutions.
  retiensProfil(pseudo, Profile.fromJson(r.data!));
  return cache[cle] ?? '';
}

/// Relit le profil de [pseudo] MAINTENANT, qu'on le connaisse ou non.
///
/// Les `resolve` ne demandent qu'une fois par session : c'est ce qu'il faut
/// pour ne pas réinterroger le serveur à chaque image, et c'est aussi ce qui
/// faisait tenir une devise périmée jusqu'au redémarrage de l'application.
///
/// Appelée à l'OUVERTURE d'un écran qui montre quelque chose d'un autre
/// joueur, elle ne coûte rien de plus : l'écran lisait déjà un profil par ses
/// `resolve`, qui trouvent ensuite tout en cache. Une requête par ouverture,
/// comme avant — mais à jour.
///
/// Silencieuse en cas d'échec : garder l'ancienne valeur vaut mieux que vider
/// l'écran parce que le réseau a toussé.
Future<void> rafraichisProfil(String pseudo, {OnlineService? online}) async {
  if (pseudo.trim().isEmpty) return;
  final service = online ?? OnlineService.instance;
  if (!service.isLoggedIn) return;
  final r = await service.client.getProfile(pseudo);
  if (!r.isOk || r.data == null) return;
  // Une réponse qui ne porte AUCUN champ de profil n'est pas un profil, et
  // `Profile.fromJson` en tirerait des chaînes vides qui effaceraient ce
  // qu'on savait. Le serveur d'aujourd'hui répond `ok: false` quand le
  // joueur est introuvable, donc le cas ne se présente pas — mais effacer
  // une devise sur une réponse muette serait un défaut silencieux, et la
  // garde coûte une ligne.
  //
  // Une devise VIDÉE par son auteur, elle, arrive bien avec sa clé : elle
  // passe, et l'écran l'oublie comme il faut.
  const champs = ['description', 'photo', 'theme'];
  if (!champs.any(r.data!.containsKey)) return;
  retiensProfil(pseudo, Profile.fromJson(r.data!));
}
