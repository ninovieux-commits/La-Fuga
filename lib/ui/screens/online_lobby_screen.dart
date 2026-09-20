/// Salon en ligne : connexion, recherche d'adversaire, lancement de la partie.
library;

import 'package:flutter/material.dart';

import '../../game/clock.dart';
import '../../game/online_game.dart';
import '../../game/challenges.dart';
import '../../i18n/translations.dart';
import '../../net/profile.dart';
import '../widgets/player_card.dart';
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

  final TextEditingController _searchField = TextEditingController();
  ChallengeService? _challenges;

  /// Joueur défié, tant qu'on attend sa réponse.
  String? _challenged;

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
    _challenges?.unbind();
    _searchField.dispose();
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
    _bindChallenges(socket);
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

  /// Défis : envoi, refus, et défi reçu pendant qu'on est dans le salon.
  void _bindChallenges(ChallengeSocket socket) {
    final challenges = ChallengeService(socket);
    _challenges = challenges;
    challenges.bind(
      onReceived: _onChallengeReceived,
      onFailed: (reason) {
        _closeWaiting();
        _say(switch (reason) {
          ChallengeFailure.self => T(
            'Vous ne pouvez pas vous défier vous-même.',
          ),
          ChallengeFailure.blocked => T(
            'Défi impossible : un blocage est en place entre vous.',
          ),
          ChallengeFailure.unavailable => T(
            "Désolé, cet adversaire n'est pas disponible.",
          ),
        });
      },
      onRefused: (opponent) {
        _closeWaiting();
        _say(
          T(
            '%s a refusé votre défi.',
          ).replaceAll('%s', opponent.isEmpty ? (_challenged ?? '') : opponent),
        );
      },
    );
  }

  /// Contexte du popup « défi envoyé », tant qu'il est ouvert.
  ///
  /// On retient le contexte du popup lui-même plutôt que celui de l'écran :
  /// fermer par `Navigator.of(context).pop()` fermerait ce qui se trouve au
  /// sommet, qui n'est pas forcément ce popup.
  BuildContext? _waitingContext;

  void _closeWaiting() {
    final dialog = _waitingContext;
    _waitingContext = null;
    if (dialog == null || !dialog.mounted) return;
    Navigator.of(dialog).pop();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Cherche un joueur, puis montre sa fiche.
  Future<void> _searchPlayer() async {
    final pseudo = _searchField.text.trim();
    if (pseudo.isEmpty) return;

    final r = await widget.online.client.searchUser(pseudo);
    if (!mounted) return;
    if (!r.isOk) {
      _say(T('Joueur introuvable'));
      return;
    }

    final target = await showPlayerCard(
      context,
      online: widget.online,
      player: Profile.fromJson(r.data!),
      palette: paletteOf(Settings.instance.themeAxes.general),
    );
    if (target != null) await _challenge(target);
  }

  /// Envoie un défi et attend la réponse.
  Future<void> _challenge(String pseudo) async {
    final challenges = _challenges;
    if (challenges == null) {
      _say(T('Hors ligne'));
      return;
    }

    _challenged = pseudo;
    challenges.challenge(
      pseudo,
      objectif: _objectif,
      cadence: _cadence.label,
      random: _randomFuga,
    );

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _waitingContext = dialogContext;
        return AlertDialog(
          title: Text(T('Défier')),
          content: Text(
            '${T("Défi envoyé à %s…").replaceAll('%s', pseudo)}\n\n'
            '${T("En attente de sa réponse.")}',
          ),
          actions: [
            TextButton(
              onPressed: () {
                challenges.cancel();
                _waitingContext = null;
                Navigator.of(dialogContext).pop();
              },
              child: Text(T('Annuler')),
            ),
          ],
        );
      },
    );
    _waitingContext = null;
  }

  /// Un joueur nous défie : accepter démarre la partie par `partie_trouvee`.
  Future<void> _onChallengeReceived(IncomingChallenge defi) async {
    final challenges = _challenges;
    if (challenges == null || !mounted) return;

    final cadence = defi.cadence == 'zen'
        ? T('Zen (illimité)')
        : '${defi.cadence} min';
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(T('Défi')),
        content: Text(
          '${defi.from} (${T("Mélo : %d").replaceAll('%d', '${defi.melo}')})\n'
          '${T("vous défie !")}\n\n'
          '${T("Cadence")} : $cadence'
          '${defi.random ? '\nRandom Fuga' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(T('Refuser')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(T('Accepter')),
          ),
        ],
      ),
    );
    challenges.respond(defi, accept: accepted ?? false);
  }

  /// Mes favoris : on peut les défier directement.
  Future<void> _openFavorites() async {
    final r = await widget.online.client.listFavorites();
    if (!mounted) return;
    final favorites = [
      for (final f in r.get<List<dynamic>>('favorites') ?? const [])
        if (f is Map) Person.fromJson(Map<String, dynamic>.from(f)),
    ];

    final target = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(T('Mes favoris')),
        content: favorites.isEmpty
            ? Text(T('Aucun favori.\nAjoutez des favoris via la recherche.'))
            : SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final f in favorites)
                      ListTile(
                        leading: Icon(
                          f.online ? Icons.circle : Icons.circle_outlined,
                          size: 12,
                          color: f.online ? Colors.green : Colors.grey,
                        ),
                        title: Text(f.pseudo),
                        subtitle: Text(
                          T('Mélo : %d').replaceAll('%d', '${f.melo}'),
                        ),
                        trailing: Text(T('Défier')),
                        onTap: () => Navigator.of(context).pop(f.pseudo),
                      ),
                  ],
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(T('Fermer')),
          ),
        ],
      ),
    );
    if (target != null) await _challenge(target);
  }

  /// Partie en cours, tant que son écran est ouvert.
  OnlineGame? _openGame;

  Future<void> _onGameFound(Map<String, dynamic> data) async {
    final socket = widget.online.socket;
    if (socket == null || !mounted) return;

    // Un défi accepté arrive ici aussi : on referme son popup d'attente.
    _closeWaiting();

    final info = OnlineGameInfo.fromEvent(data);

    // Partie SUIVANTE d'un match : l'écran est déjà ouvert, et c'est lui qui
    // enchaîne. En empiler un second laisserait la partie précédente dessous.
    final open = _openGame;
    if (open != null) {
      open.startNextGame(info);
      return;
    }

    final game = OnlineGame(
      socket: socket,
      info: info,
      cadence: _cadenceFromLabel(info.cadence),
    );
    _openGame = game;

    setState(() {
      _searching = false;
      _notice = null;
    });

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OnlineGameScreen(
          game: game,
          myPseudo: widget.online.pseudo ?? T('Moi'),
        ),
      ),
    );
    _openGame = null;
    // L'écran de partie a repris les événements à son compte : on récupère
    // les nôtres, sans quoi le salon resterait sourd au matchmaking.
    if (mounted) setState(_bindSocket);
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

        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchField,
                decoration: InputDecoration(
                  hintText: T('Rechercher un joueur…'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _searchPlayer(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: T('Rechercher un joueur…'),
              onPressed: _searchPlayer,
            ),
            IconButton(
              icon: const Icon(Icons.star_outline),
              tooltip: T('Mes favoris'),
              onPressed: _openFavorites,
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
