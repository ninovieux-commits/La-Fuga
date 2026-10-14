/// Menu déroulant sur le nom d'un joueur, en partie — portage de
/// `_show_name_menu`, `_name_profile`, `_name_favorite` et `_name_block`
/// (main.py).
///
/// Il ne s'ouvre que sur un VRAI joueur (ni « Joueur 1 », ni Deep Grey) et
/// seulement si l'on est connecté : sans compte, rien de tout cela n'existe.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../net/favoris_connus.dart';
import '../../net/online_service.dart';
import '../scale.dart';
import '../screens/account_screen.dart';
import 'fuga_button.dart';

/// Fond du menu : plus sombre que les touches, sans quoi on ne les voit pas.
const Color kFondMenuNom = Color.fromRGBO(38, 38, 38, 1);

/// Les noms qui ne désignent personne — `_is_real_player`.
bool isRealPlayer(String? pseudo) {
  if (pseudo == null || pseudo.isEmpty) return false;
  final placeholders = {
    'Joueur 1',
    'Joueur 2',
    T('Joueur 1'),
    T('Joueur 2'),
    'deep grey',
    'Deep Grey',
    'IA',
    T('IA'),
  };
  return !placeholders.contains(pseudo);
}

/// Ouvre le menu sur ce nom. Ne fait rien si le joueur n'en est pas un.
Future<void> showNameMenu(
  BuildContext context, {
  required OnlineService online,
  required String pseudo,
}) async {
  if (!online.isLoggedIn || !isRealPlayer(pseudo)) return;
  final isMe = pseudo == (online.pseudo ?? '');

  // Est-il DÉJÀ dans mes favoris ? On le demande avant d'ouvrir le menu, pas
  // après : la touche doit dire la vérité dès la première image, sans quoi
  // elle changerait de nom sous le doigt. Nino : « le bouton favori doit se
  // transformer en retirer quand on a déjà la personne en favori et vice et
  // versa. » Sans réponse, on propose « Favori » — ajouter deux fois ne casse
  // rien, retirer ce qu'on n'a pas serait plus déroutant.
  var estFavori = false;
  if (!isMe) {
    estFavori = await FavorisConnus.instance.demande(pseudo, online: online);
    if (!context.mounted) return;
  }

  final choice = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      // PAS `kFugaGrey` : c'est la couleur des touches elles-mêmes, et le
      // menu était donc gris sur gris — on ne voyait que « Bloquer », qui est
      // rouge. Les touches étaient bien là, elles se confondaient avec le
      // fond. Un panneau sombre les détache.
      backgroundColor: kFondMenuNom,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            pseudo,
            style: TextStyle(
              fontSize: SF(18),
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: S(8)),
          for (final (label, value, color) in <(String, String, Color)>[
            (T('Profil'), 'profil', kFugaGrey),
            if (!isMe) ...[
              (estFavori ? T('Retirer') : T('Favori'), 'favori', kFugaGrey),
              // Pas de « Message » ici : la touche Chat du bandeau du haut
              // ouvre déjà la conversation, et elle porte la pastille des
              // non-lus. Deux chemins pour la même chose encombraient.
              (T('Bloquer'), 'bloquer', const Color.fromRGBO(184, 66, 66, 1)),
            ],
          ])
            Padding(
              padding: EdgeInsets.only(bottom: S(8)),
              child: FugaButton(
                text: label,
                color: color,
                fontSize: SF(16),
                onPressed: () => Navigator.of(context).pop(value),
              ),
            ),
          FugaButton(
            text: T('Fermer'),
            fontSize: SF(14),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    ),
  );

  if (choice == null || !context.mounted) return;

  switch (choice) {
    case 'profil':
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              AccountScreen(online: online, pseudo: isMe ? null : pseudo),
        ),
      );
    case 'favori':
      // La même touche fait les deux sens : elle portait le nom de ce
      // qu'elle allait faire, elle fait maintenant ce qu'elle annonçait.
      final r = estFavori
          ? await online.client.removeFavorite(pseudo)
          : await online.client.addFavorite(pseudo);
      // Le cache apprend le nouvel état : l'étoile du bandeau, derrière ce
      // menu, s'allume ou s'éteint du même coup.
      if (r.isOk) FavorisConnus.instance.retiens(pseudo, !estFavori);
      if (!context.mounted) return;
      _say(
        context,
        r.isOk
            ? (estFavori
                      ? T('%s retiré des favoris.')
                      : T('%s ajouté aux favoris.'))
                  .replaceFirst('%s', pseudo)
            : T('Erreur : %s').replaceFirst('%s', r.error ?? ''),
      );
    case 'bloquer':
      final r = await online.client.blockUser(pseudo);
      if (!context.mounted) return;
      _say(
        context,
        r.isOk
            // Le blocage ne coupe pas la partie en cours : Kivy le dit.
            ? T(
                '%s bloqué. La partie en cours continue ; le blocage prendra effet à la fin.',
              ).replaceFirst('%s', pseudo)
            : T('Erreur : %s').replaceFirst('%s', r.error ?? ''),
      );
  }
}

void _say(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
