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
import '../screens/account_screen.dart';
import '../screens/history_screen.dart';

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
            TextButton(
              onPressed: () => _openHistory('direct'),
              child: Text(
                '${T("En direct")} : ${p.direct.mine} - ${p.direct.theirs}',
              ),
            ),
            TextButton(
              onPressed: () => _openHistory('corr'),
              child: Text(
                '${T("Correspondance")} : '
                '${p.correspondence.mine} - ${p.correspondence.theirs}',
              ),
            ),
          ],
          SizedBox(height: S(8)),
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      AccountScreen(online: widget.online, pseudo: p.pseudo),
                ),
              );
            },
            icon: Icon(Icons.person_outline, size: S(18)),
            label: Text(T('Profil')),
          ),
        ],
      ),
      actions: [
        if (!p.isSelf)
          TextButton(
            onPressed: _busy ? null : _toggleBlock,
            child: Text(
              _blocked ? T('Débloquer') : T('Bloquer'),
              style: const TextStyle(color: Color(0xFFB84343)),
            ),
          ),
        if (!p.isSelf)
          TextButton(
            onPressed: _busy ? null : _toggleFavorite,
            child: Text(_favorite ? T('Retirer') : T('Enregistrer')),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(T('Fermer')),
        ),
        if (!p.isSelf && !_blocked)
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: widget.palette.clair,
            ),
            onPressed: () => Navigator.of(context).pop(p.pseudo),
            child: Text(T('Défier')),
          ),
      ],
    );
  }
}
