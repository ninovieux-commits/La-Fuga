/// Revenir AU MENU — et non d'un écran en arrière.
///
/// Nino : « il y a aussi dans l'app des boutons "revenir au menu" qui ne
/// renvoient pas au menu mais juste en arrière ».
///
/// Chez Kivy la question ne se posait pas : un seul gestionnaire d'écrans, et
/// « retour au menu » affichait le menu, point. Le portage a traduit ça par un
/// `pop()`, qui ne revient au menu que si c'est le menu qui a ouvert l'écran.
/// Longtemps c'était vrai. Ça ne l'est plus depuis que le défi s'ouvre de
/// partout : la pile peut être menu → conversation → partie, et quitter la
/// partie rendait la conversation, sous une touche qui promettait le menu.
///
/// Le menu est la PREMIÈRE route de l'application (`home:` dans `main.dart`),
/// donc on dépile jusqu'à elle. Quand l'écran vient du menu — le cas courant —
/// cela revient exactement au `pop()` d'avant.
library;

import 'package:flutter/material.dart';

void retourAuMenu(BuildContext context) =>
    Navigator.of(context).popUntil((route) => route.isFirst);
