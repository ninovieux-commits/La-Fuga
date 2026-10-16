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

import 'package:flutter/foundation.dart';

import 'avatar_photos.dart';
import 'decors_connus.dart';
import 'devises_connues.dart';
import 'favoris_connus.dart';
import 'profile.dart';
import 'scores_directs.dart';

/// Prévient quand un profil déjà connu a CHANGÉ.
///
/// Nino : « si un adversaire change sa devise, je dois relancer mon app pour
/// que ça m'affiche la nouvelle dans les parties. Tout doit être en direct
/// dans l'app. »
///
/// Les caches ne se trompaient pas, ils ne se remettaient jamais en
/// question : une valeur lue une fois tenait jusqu'à la fermeture de
/// l'application. Relire ne suffit pourtant pas — encore faut-il que les
/// écrans déjà dessinés l'apprennent, et un écran ne se redessine pas parce
/// qu'une variable statique a changé ailleurs.
///
/// Ne sonne QUE sur un vrai changement : un profil relu à l'identique — le
/// cas courant — ne redessine rien.
final ChangeNotifier profilsConnus = _Profils();

class _Profils extends ChangeNotifier {
  void previens() => notifyListeners();
}

void retiensProfil(String pseudo, Profile profil) {
  final avant = _empreinte(pseudo);
  AvatarPhotos.remember(pseudo, profil.photo);
  DecorsConnus.remember(pseudo, profil.theme);
  DevisesConnues.retiens(pseudo, profil.description);
  FavorisConnus.instance.retiens(pseudo, profil.isFavorite);
  ScoresDirects.remember(pseudo, profil.direct);
  if (_empreinte(pseudo) != avant) (profilsConnus as _Profils).previens();
}

/// De quoi reconnaître un profil qui a bougé, sans comparer cinq fois.
String _empreinte(String pseudo) {
  final direct = ScoresDirects.connu(pseudo);
  return [
    AvatarPhotos.enCache(pseudo),
    DecorsConnus.known(pseudo),
    DevisesConnues.connue(pseudo),
    FavorisConnus.instance.connu(pseudo),
    direct == null ? '' : '${direct.mine}-${direct.theirs}',
  ].join('\u0000');
}
