/// Ce qu'on retient d'un profil reçu.
///
/// Un `/get_profile` porte la photo, le thème, l'étoile, le score en
/// tête-à-tête et la devise. Cinq caches à garnir, et
/// deux endroits qui demandent le profil — `DecorsConnus.resolve` et
/// `DevisesConnues.resolve`. La liste des six était écrite deux fois, et un
/// cache ajouté d'un côté manquait de l'autre : elle est écrite ici, une
/// fois.
///
/// (Les deux classements y ont figuré une journée, le temps que le serveur
/// apprenne à envoyer celui du mode joué. Il le fait depuis le 15 octobre,
/// et l'écran de jeu reprend le chiffre que la partie porte.)
library;

import 'avatar_photos.dart';
import 'decors_connus.dart';
import 'devises_connues.dart';
import 'favoris_connus.dart';
import 'profile.dart';
import 'scores_directs.dart';

void retiensProfil(String pseudo, Profile profil) {
  AvatarPhotos.remember(pseudo, profil.photo);
  DecorsConnus.remember(pseudo, profil.theme);
  DevisesConnues.retiens(pseudo, profil.description);
  FavorisConnus.instance.retiens(pseudo, profil.isFavorite);
  ScoresDirects.remember(pseudo, profil.direct);
}
