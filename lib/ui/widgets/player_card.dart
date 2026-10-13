/// Fiche d'un joueur — portage du popup de `_show_player_card` (main.py).
///
/// Pseudo, mélos, état en ligne, score en tête-à-tête, puis les trois gestes
/// possibles : défier, mettre en favori, bloquer.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../net/online_service.dart';
import '../../net/profile.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'fuga_button.dart';
import '../screens/account_screen.dart';
import '../screens/history_screen.dart';

/// Rouge du blocage — le même que dans le menu du nom.
const Color kRougeBloquer = Color(0xFFB84343);

/// Affiche la fiche et renvoie le pseudo à défier, ou `null`.
Future<String?> showPlayerCard(
  BuildContext context, {
  required OnlineService online,
  required Profile player,
  required ThemePalette palette,
}) => showDialog<String>(
  context: context,
  builder: (_) => _PlayerCard(online: online, player: player, palette: palette),
);

class _PlayerCard extends StatefulWidget {
  const _PlayerCard({
    required this.online,
    required this.player,
    required this.palette,
  });

  final OnlineService online;
  final Profile player;
  final ThemePalette palette;

  @override
  State<_PlayerCard> createState() => _PlayerCardState();
}

class _PlayerCardState extends State<_PlayerCard> {
  late bool _favorite = widget.player.isFavorite;
  late bool _blocked = widget.player.isBlocked;
  bool _busy = false;

  Future<void> _toggleFavorite() async {
    setState(() => _busy = true);
    final client = widget.online.client;
    final r = _favorite
        ? await client.removeFavorite(widget.player.pseudo)
        : await client.addFavorite(widget.player.pseudo);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.isOk) _favorite = !_favorite;
    });
  }

  Future<void> _toggleBlock() async {
    setState(() => _busy = true);
    final client = widget.online.client;
    final r = _blocked
        ? await client.unblockUser(widget.player.pseudo)
        : await client.blockUser(widget.player.pseudo);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.isOk) _blocked = !_blocked;
    });
  }

  void _openHistory(String mode) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HistoryScreen(
          online: widget.online,
          opponent: widget.player.pseudo,
          h2hMode: mode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.player;

    return AlertDialog(
      // La fiche de Kivy (`_show_player_card`) commence par le pseudo seul :
      // elle ne montre pas d'avatar.
      title: Text(p.pseudo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${T("Mélo : %d").replaceAll('%d', '${p.melo}')}'
            '   ·   '
            '${T("Random : %d").replaceAll('%d', '${p.meloRandom}')}',
            textAlign: TextAlign.center,
          ),
          SizedBox(height: S(6)),
          Text(
            p.online ? T('En ligne') : T('Hors ligne'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: p.online ? Colors.green : Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (!p.isSelf) ...[
            SizedBox(height: S(12)),
            Text(
              T('Moi contre %s :').replaceAll('%s', p.pseudo),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            // Les scores ouvrent l'historique des parties jouées entre nous.
            // Les scores mènent à l'historique des parties jouées entre
            // nous. Ils restent du texte touchable — ce ne sont pas des
            // actions — mais plus en violet d'usine.
            TextButton(
              onPressed: () => _openHistory('direct'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: Text(
                '${T("En direct")} : ${p.direct.mine} - ${p.direct.theirs}',
              ),
            ),
            TextButton(
              onPressed: () => _openHistory('corr'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: Text(
                '${T("Correspondance")} : '
                '${p.correspondence.mine} - ${p.correspondence.theirs}',
              ),
            ),
          ],
          SizedBox(height: S(12)),
          // LES TOUCHES SONT DES TOUCHES, CENTRÉES ET LARGES.
          //
          // Nino : « j'aimerai que les boutons bloquer retirer et fermer
          // soient centrés et élargis ». Elles étaient des touches plates de
          // Material, alignées à droite et VIOLETTES — la graine d'usine de
          // Material 3, que `ThemeData` laisse par défaut faute de jeu de
          // couleurs. Elles descendent donc du bandeau d'actions dans le
          // corps, dont le `Column` est en `stretch` : c'est lui qui les
          // élargit, et le centrage vient de là aussi.
          _touche(
            texte: T('Profil'),
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      AccountScreen(online: widget.online, pseudo: p.pseudo),
                ),
              );
            },
          ),
          if (!p.isSelf && !_blocked)
            _touche(
              texte: T('Défier'),
              couleur: widget.palette.clair,
              encre: Colors.black,
              onPressed: () => Navigator.of(context).pop(p.pseudo),
            ),
          if (!p.isSelf)
            _touche(
              texte: _favorite ? T('Retirer') : T('Enregistrer'),
              couleur: widget.palette.fonce,
              onPressed: _busy ? null : _toggleFavorite,
            ),
          if (!p.isSelf)
            _touche(
              texte: _blocked ? T('Débloquer') : T('Bloquer'),
              couleur: kRougeBloquer,
              onPressed: _busy ? null : _toggleBlock,
            ),
          _touche(
            texte: T('Fermer'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// Une touche de la fiche : pleine largeur, centrée, sous les autres.
  ///
  /// Sa largeur lui vient du `Column` du corps, en `CrossAxisAlignment
  /// .stretch` : il impose la largeur à ses enfants. Un `SizedBox` autour ne
  /// servirait à rien — vérifié en lui donnant une largeur étroite, les
  /// touches ne bougent pas d'un pixel.
  Widget _touche({
    required String texte,
    required VoidCallback? onPressed,
    Color couleur = kFugaGrey,
    Color encre = Colors.white,
  }) => Padding(
    padding: EdgeInsets.only(bottom: S(8)),
    child: FugaButton(
      text: texte,
      color: couleur,
      textColor: encre,
      fontSize: SF(15),
      onPressed: onPressed,
    ),
  );
}
