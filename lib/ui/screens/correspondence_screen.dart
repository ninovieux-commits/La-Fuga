/// Parties par correspondance : la liste des parties en cours, des défis
/// reçus et des résultats pas encore refermés.
library;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../game/correspondence.dart';
import '../../i18n/translations.dart';
import '../../net/online_service.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import 'corr_game_screen.dart';
import 'login_screen.dart';

class CorrespondenceScreen extends StatefulWidget {
  const CorrespondenceScreen({super.key, required this.online});

  final OnlineService online;

  @override
  State<CorrespondenceScreen> createState() => _CorrespondenceScreenState();
}

class _CorrespondenceScreenState extends State<CorrespondenceScreen> {
  late CorrespondenceService _corr;
  List<CorrGame>? _games;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _corr = CorrespondenceService(widget.online.client);
    if (widget.online.isLoggedIn) _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final games = await _corr.list();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _games = games;
      if (games == null) {
        _error = T('Erreur : %s').replaceAll('%s', T('réseau'));
      }
    });
  }

  Future<void> _connect() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LoginScreen(online: widget.online)),
    );
    if (ok == true && mounted) {
      _corr = CorrespondenceService(widget.online.client);
      await _refresh();
    }
  }

  Future<void> _challenge() async {
    final pseudo = TextEditingController();
    var objectif = 'partie';
    var random = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(T('Défier')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pseudo,
                autocorrect: false,
                decoration: InputDecoration(labelText: T('Pseudo')),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final o in ['partie', '3', '5'])
                    ChoiceChip(
                      label: Text(o == 'partie' ? T('Partie unique') : o),
                      selected: objectif == o,
                      onSelected: (_) => setDialogState(() => objectif = o),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(T('Aléatoire')),
                value: random,
                onChanged: (v) => setDialogState(() => random = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(T('Annuler')),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(T('Défier')),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    final error = await _corr.challenge(pseudo.text, objectif, random: random);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(T('Défi envoyé à %s !').replaceAll('%s', pseudo.text)),
      ),
    );
    await _refresh();
  }

  Future<void> _answer(CorrGame game, bool accept) async {
    await _corr.answerChallenge(game.id, accept);
    await _refresh();
  }

  Future<void> _open(CorrGame game) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CorrGameScreen(
          game: game,
          service: _corr,
          myPseudo: widget.online.pseudo ?? T('Moi'),
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _close(CorrGame game) async {
    await _corr.close(game.id);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final axes = Settings.instance.themeAxes;
    final palette = paletteOf(axes.general);

    return Scaffold(
      backgroundColor: paletteOf(axes.menu).menu,
      appBar: AppBar(
        backgroundColor: palette.clair,
        foregroundColor: Colors.white,
        title: Text(T('Parties par correspondance')),
        actions: [
          if (widget.online.isLoggedIn)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: T('Actualiser'),
              onPressed: _loading ? null : _refresh,
            ),
        ],
      ),
      floatingActionButton: widget.online.isLoggedIn
          ? FloatingActionButton.extended(
              backgroundColor: palette.clair,
              onPressed: _challenge,
              icon: const Icon(Icons.add),
              label: Text(T('Défier')),
            )
          : null,
      body: !widget.online.isLoggedIn
          ? _notConnected(palette)
          : RefreshIndicator(onRefresh: _refresh, child: _list(palette)),
    );
  }

  Widget _notConnected(ThemePalette palette) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(T('Connexion requise')),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: palette.clair),
          onPressed: _connect,
          child: Text(T('Se connecter')),
        ),
      ],
    ),
  );

  Widget _list(ThemePalette palette) {
    if (_loading && _games == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final games = _games ?? const <CorrGame>[];
    if (games.isEmpty) {
      // Une liste vide se dit : sans message, on croirait à un chargement
      // qui n'aboutit pas.
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Text(
              _error ?? T('Aucune partie par correspondance.'),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: games.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) => _slot(palette, games[i]),
    );
  }

  Widget _slot(ThemePalette palette, CorrGame game) {
    final camp = game.myCamp == Camp.blanc ? T('Blanc') : T('Noir');

    return switch (game.status) {
      CorrStatus.defi => ListTile(
        leading: Icon(Icons.mail_outline, color: palette.clair),
        title: Text(game.opponent),
        subtitle: Text(
          game.isChallenger
              ? T('En attente de sa réponse.')
              : '${T("vous défie !\nMélo %d%s").split("\n").first} '
                    'Mélo ${game.opponentMelo}',
        ),
        trailing: game.isChallenger
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => _answer(game, true),
                    child: Text(T('Accepter')),
                  ),
                  TextButton(
                    onPressed: () => _answer(game, false),
                    child: Text(T('Refuser')),
                  ),
                ],
              ),
      ),
      CorrStatus.enCours => ListTile(
        leading: CircleAvatar(
          backgroundColor: game.myCamp == Camp.blanc
              ? palette.clair
              : palette.fonce,
          child: Text(
            camp.characters.first,
            style: const TextStyle(color: Colors.white),
          ),
        ),
        title: Text(game.opponent),
        subtitle: Text(
          [
            game.myTurn ? T('À vous de jouer') : T('En attente…'),
            '${game.myScore} - ${game.opponentScore}',
            if (game.drawToAnswer) T('Nulle'),
          ].join('  ·  '),
        ),
        trailing: game.unreadChat > 0
            ? Badge(label: Text('${game.unreadChat}'))
            : (game.myTurn
                  ? Icon(Icons.play_arrow, color: palette.clair)
                  : null),
        onTap: () => _open(game),
      ),
      CorrStatus.termine => ListTile(
        leading: Icon(
          game.won == null
              ? Icons.remove
              : (game.won! ? Icons.emoji_events : Icons.close),
          color: game.won == true ? palette.clair : Colors.white54,
        ),
        title: Text(game.opponent),
        subtitle: Text(
          game.won == null
              ? T('Nulle')
              : (game.won! ? T('Gagné !') : T('Perdu')),
        ),
        trailing: TextButton(
          onPressed: () => _close(game),
          child: Text(T('Fermer')),
        ),
        onTap: () => _open(game),
      ),
    };
  }
}
