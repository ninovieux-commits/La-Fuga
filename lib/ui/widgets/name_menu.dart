/// Menu déroulant sur le nom d'un joueur, en partie — portage de
/// `_show_name_menu`, `_name_profile`, `_name_favorite`, `_name_block` et
/// `_name_message` (main.py).
///
/// Il ne s'ouvre que sur un VRAI joueur (ni « Joueur 1 », ni Deep Grey) et
/// seulement si l'on est connecté : sans compte, rien de tout cela n'existe.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../net/online_service.dart';
import '../screens/account_screen.dart';
import '../screens/conversations_screen.dart';
import 'fuga_button.dart';

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

  final choice = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: kFugaGrey,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            pseudo,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          for (final (label, value, color) in <(String, String, Color)>[
            (T('Profil'), 'profil', kFugaGrey),
            if (!isMe) ...[
              (T('Favori'), 'favori', kFugaGrey),
              (T('Message'), 'message', kFugaGrey),
              (T('Bloquer'), 'bloquer', const Color.fromRGBO(184, 66, 66, 1)),
            ],
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FugaButton(
                text: label,
                color: color,
                fontSize: 14,
                onPressed: () => Navigator.of(context).pop(value),
              ),
            ),
          FugaButton(
            text: T('Fermer'),
            fontSize: 12,
            height: 40,
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
    case 'message':
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ConversationScreen(online: online, pseudo: pseudo),
        ),
      );
    case 'favori':
      final r = await online.client.addFavorite(pseudo);
      if (!context.mounted) return;
      _say(
        context,
        r.isOk
            ? T('%s ajouté aux favoris.').replaceFirst('%s', pseudo)
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
