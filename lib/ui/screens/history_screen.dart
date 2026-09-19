/// Historique : les parties du compte et celles enregistrées sur l'appareil.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../net/online_service.dart';
import '../../state/local_games.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import 'replay_screen.dart';

class HistoryScreen extends StatefulWidget {
  HistoryScreen({
    super.key,
    required this.online,
    LocalGamesStore? local,
    this.opponent,
    this.mode,
  }) : local = local ?? LocalGamesStore();

  final OnlineService online;

  /// Ne montrer que les parties jouées contre ce joueur.
  final String? opponent;

  /// Avec [opponent] : `direct` ou `corr`, pour ne garder qu'un seul mode.
  final String? mode;

  /// Magasin des parties locales. Injectable pour les tests.
  final LocalGamesStore local;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  List<Map<String, dynamic>>? _accountGames;
  List<LocalGame>? _localGames;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final local = await widget.local.list();
    List<Map<String, dynamic>>? account;
    if (widget.online.isLoggedIn) {
      final r = await widget.online.client.listGames();
      if (r.isOk) {
        account = [
          for (final g in r.get<List<dynamic>>('games') ?? const [])
            if (g is Map)
              if (_keep(Map<String, dynamic>.from(g)))
                Map<String, dynamic>.from(g),
        ];
      }
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _localGames = local;
      _accountGames = account;
    });
  }

  /// Filtre tête-à-tête : les parties contre un adversaire donné, dans un
  /// mode donné. Le mode se lit dans l'identifiant, comme en Kivy :
  /// `online_corr…` pour la correspondance, `online_…` pour le direct.
  bool _keep(Map<String, dynamic> game) {
    final opponent = widget.opponent;
    if (opponent == null) return true;

    final uid = '${game['game_uid'] ?? ''}';
    final isCorr = uid.startsWith('online_corr');
    if (widget.mode == 'corr' && !isCorr) return false;
    if (widget.mode == 'direct' && isCorr) return false;

    final lower = opponent.toLowerCase();
    return '${game['joueur1'] ?? ''}'.toLowerCase() == lower ||
        '${game['joueur2'] ?? ''}'.toLowerCase() == lower;
  }

  Future<void> _openAccountGame(Map<String, dynamic> game) async {
    final uid = (game['game_uid'] ?? '').toString();
    final r = await widget.online.client.getGame(uid);
    if (!mounted) return;
    final nmc = r.get<String>('nmc_text');
    if (nmc == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(T('Partie introuvable.'))));
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ReplayScreen(nmc: nmc)));
  }

  Future<void> _openLocalGame(LocalGame game) async {
    final nmc = await widget.local.read(game.file);
    if (!mounted || nmc == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReplayScreen(nmc: nmc, title: game.name),
      ),
    );
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
        title: Text(
          widget.opponent == null
              ? T('Historique')
              : '${T("Historique")} · ${widget.opponent}',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: T('Actualiser'),
            onPressed: _loading ? null : _load,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: T('Mon compte')),
            Tab(text: T('Sur cet appareil')),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [_accountTab(palette), _localTab(palette)],
            ),
    );
  }

  Widget _accountTab(ThemePalette palette) {
    if (!widget.online.isLoggedIn) {
      return Center(child: Text(T('Connexion requise')));
    }
    final games = _accountGames;
    if (games == null) {
      return Center(
        child: Text(T('Erreur : %s').replaceAll('%s', T('réseau'))),
      );
    }
    if (games.isEmpty) {
      return Center(child: Text(T('Aucune partie enregistrée.')));
    }

    return ListView.separated(
      itemCount: games.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final g = games[i];
        return ListTile(
          title: Text('${g['joueur1'] ?? '?'} – ${g['joueur2'] ?? '?'}'),
          subtitle: Text(
            [
              if (g['date'] != null) '${g['date']}',
              if (g['resultat'] != null) '${g['resultat']}',
              if (g['methode'] != null) '${g['methode']}',
            ].join('  ·  '),
          ),
          trailing: Icon(Icons.play_arrow, color: palette.clair),
          onTap: () => _openAccountGame(g),
        );
      },
    );
  }

  Widget _localTab(ThemePalette palette) {
    final games = _localGames ?? const <LocalGame>[];
    if (games.isEmpty) {
      return Center(child: Text(T('Aucune partie sur cet appareil.')));
    }

    return ListView.separated(
      itemCount: games.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final g = games[i];
        return Dismissible(
          key: ValueKey(g.file.path),
          background: Container(color: FugaColors.immobile),
          onDismissed: (_) async {
            await widget.local.delete(g.file);
            await _load();
          },
          child: ListTile(
            title: Text('${g.meta.player1} – ${g.meta.player2}'),
            subtitle: Text(
              [
                g.meta.date,
                g.meta.result,
                g.meta.method,
              ].where((s) => s.isNotEmpty).join('  ·  '),
            ),
            trailing: Icon(Icons.play_arrow, color: palette.clair),
            onTap: () => _openLocalGame(g),
          ),
        );
      },
    );
  }
}
