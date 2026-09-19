/// Salon en ligne : connexion, recherche d'adversaire, lancement de la partie.
library;

import 'package:flutter/material.dart';

import '../../game/clock.dart';
import '../../game/online_game.dart';
import '../../i18n/translations.dart';
import '../../net/online_service.dart';
import '../../net/socket_client.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import 'login_screen.dart';
import 'online_game_screen.dart';

class OnlineLobbyScreen extends StatefulWidget {
  const OnlineLobbyScreen({super.key, required this.online});

  final OnlineService online;

  @override
  State<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends State<OnlineLobbyScreen> {
  Cadence _cadence = Cadence.blitz5;

  /// `partie` pour une partie unique, sinon un nombre de points.
  String _objectif = 'partie';

  bool _randomFuga = false;
  bool _searching = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _bindSocket();
  }

  @override
  void dispose() {
    final s = widget.online.socket;
    s
      ?..off(FugaEvents.partieTrouvee)
      ..off(FugaEvents.rechercheEnCours)
      ..off(FugaEvents.rechercheTimeout);
    super.dispose();
  }

  void _bindSocket() {
    final socket = widget.online.socket;
    if (socket == null) return;
    socket
      ..on(FugaEvents.partieTrouvee, _onGameFound)
      ..on(FugaEvents.rechercheEnCours, (_) {
        if (mounted) setState(() => _searching = true);
      })
      ..on(FugaEvents.rechercheTimeout, (_) {
        if (!mounted) return;
        // Le serveur ne retire pas de la file : il suggère juste d'essayer
        // une autre cadence. On reste donc en recherche.
        setState(() => _notice = T('Essayez une autre cadence'));
      });
  }

  void _onGameFound(Map<String, dynamic> data) {
    final socket = widget.online.socket;
    if (socket == null || !mounted) return;

    final info = OnlineGameInfo.fromEvent(data);
    final cadence = _cadenceFromLabel(info.cadence);
    final game = OnlineGame(socket: socket, info: info, cadence: cadence);

    setState(() {
      _searching = false;
      _notice = null;
    });

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OnlineGameScreen(
          game: game,
          myPseudo: widget.online.pseudo ?? T('Moi'),
        ),
      ),
    );
  }

  /// Retrouve la cadence à partir du libellé renvoyé par le serveur.
  ///
  /// C'est le serveur qui fait foi : il peut apparier deux joueurs sur une
  /// cadence qui n'est pas exactement celle demandée.
  Cadence _cadenceFromLabel(String label) {
    for (final c in Cadence.toutes) {
      if (c.label == label) return c;
    }
    return _cadence;
  }

  Future<void> _connect() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LoginScreen(online: widget.online)),
    );
    if (ok == true && mounted) {
      _bindSocket();
      setState(() {});
    }
  }

  void _search() {
    final socket = widget.online.socket;
    if (socket == null) return;
    socket.chercherPartie(
      objectif: _objectif,
      cadence: _cadence.label,
      random: _randomFuga,
    );
    setState(() {
      _searching = true;
      _notice = null;
    });
  }

  void _cancelSearch() {
    widget.online.socket?.annulerRecherche();
    setState(() {
      _searching = false;
      _notice = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final axes = Settings.instance.themeAxes;
    final palette = paletteOf(axes.general);
    final session = widget.online.session;

    return Scaffold(
      backgroundColor: paletteOf(axes.menu).menu,
      appBar: AppBar(
        backgroundColor: palette.clair,
        foregroundColor: Colors.white,
        title: Text(T('Jouer en ligne')),
      ),
      body: session == null
          ? _notConnected(palette)
          : _lobby(palette, session.melo, session.meloRandom),
    );
  }

  Widget _notConnected(ThemePalette palette) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(T('Connexion requise'), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: palette.clair),
            onPressed: _connect,
            child: Text(T('Se connecter')),
          ),
        ],
      ),
    ),
  );

  Widget _lobby(ThemePalette palette, int melo, int meloRandom) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${widget.online.pseudo}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        Text('Mélo : $melo   ·   Random : $meloRandom'),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              widget.online.isSocketConnected
                  ? Icons.cloud_done
                  : Icons.cloud_off,
              size: 16,
              color: widget.online.isSocketConnected
                  ? palette.clair
                  : FugaColors.immobile,
            ),
            const SizedBox(width: 6),
            Text(
              widget.online.isSocketConnected
                  ? T('  ·  en ligne').trim()
                  : T('Hors ligne'),
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),

        const SizedBox(height: 24),
        Text(
          T('Cadence (min / joueur)'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final c in Cadence.toutes)
              ChoiceChip(
                label: Text(
                  c == Cadence.illimitee ? T('Zen (illimité)') : c.label,
                ),
                selected: _cadence == c,
                onSelected: _searching
                    ? null
                    : (_) => setState(() => _cadence = c),
              ),
          ],
        ),

        const SizedBox(height: 20),
        Text(
          T('Objectif'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final o in ['partie', '3', '5', '10'])
              ChoiceChip(
                label: Text(
                  o == 'partie' ? T('Partie unique') : '$o ${T('points')}',
                ),
                selected: _objectif == o,
                onSelected: _searching
                    ? null
                    : (_) => setState(() => _objectif = o),
              ),
          ],
        ),

        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(T('Aléatoire')),
          subtitle: Text(
            T('Position de départ tirée au sort, classement séparé'),
            style: const TextStyle(fontSize: 12),
          ),
          value: _randomFuga,
          onChanged: _searching ? null : (v) => setState(() => _randomFuga = v),
        ),

        const SizedBox(height: 24),
        if (_searching) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(T('Recherche')),
            ],
          ),
          if (_notice != null) ...[
            const SizedBox(height: 8),
            Text(
              _notice!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _cancelSearch, child: Text(T('Annuler'))),
        ] else
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: palette.clair,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: widget.online.isSocketConnected ? _search : null,
            child: Text(T('Chercher une partie')),
          ),
      ],
    );
  }
}
