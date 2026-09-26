/// Historique des parties — portage d'`OnlineHistoryScreen`, de
/// `HistoryScreen` et de `render_account_entry` (main.py).
///
/// Deux listes, chacune son écran comme en Kivy : « En ligne » montre les
/// parties du compte (identifiant préfixé `online_`), « En local » celles
/// jouées sur l'appareil. **Connecté**, les parties locales viennent elles
/// aussi du serveur, qui les synchronise entre appareils ; sinon on lit les
/// fichiers `.nmc` de l'appareil.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/translations.dart';
import '../../net/messages.dart';
import '../../net/online_service.dart';
import '../../state/local_games.dart';
import '../scale.dart';
import '../widgets/fuga_background.dart';
import '../widgets/fuga_button.dart';
import '../widgets/fuga_header.dart';
import '../widgets/profile_photo.dart';
import 'replay_screen.dart';

/// Laquelle des deux listes de Kivy.
enum HistoryMode { online, local }

class HistoryScreen extends StatefulWidget {
  HistoryScreen({
    super.key,
    required this.online,
    this.mode = HistoryMode.online,
    LocalGamesStore? store,
    this.target,
    this.opponent,
    this.h2hMode,
  }) : store = store ?? LocalGamesStore();

  final OnlineService online;
  final HistoryMode mode;

  /// Magasin des parties de l'appareil. Injectable pour les tests.
  final LocalGamesStore store;

  /// Historique de QUI. Nul : le mien. C'est le `target_pseudo` de Kivy,
  /// transmis au serveur ; depuis le profil d'un tiers, on lit le sien.
  final String? target;

  /// Tête-à-tête : ne montrer que les parties contre ce joueur.
  final String? opponent;

  /// Avec [opponent] : `direct` ou `corr`, pour ne garder qu'un seul mode.
  final String? h2hMode;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>>? _accountGames;
  List<LocalGame>? _localFiles;
  bool _loading = true;
  String? _error;

  bool get _fromServer =>
      widget.mode == HistoryMode.online || widget.online.isLoggedIn;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (widget.mode == HistoryMode.online && !widget.online.isLoggedIn) {
      setState(() => _loading = false);
      return;
    }

    if (!_fromServer) {
      final files = await widget.store.list();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _localFiles = files;
      });
      return;
    }

    // Tête-à-tête : on lit MON historique puis on filtre sur l'adversaire —
    // `if h2h_opp: target = None` chez Kivy. Sinon, l'historique demandé.
    final r = await widget.online.client.listGames(
      widget.opponent != null ? null : widget.target,
    );
    if (!mounted) return;
    if (!r.isOk) {
      setState(() {
        _loading = false;
        _error = r.error ?? T('réseau');
      });
      return;
    }

    // Le préfixe de l'identifiant sépare les deux historiques.
    final prefix = widget.mode == HistoryMode.online ? 'online_' : 'local_';
    setState(() {
      _loading = false;
      _accountGames = [
        for (final g in r.get<List<dynamic>>('games') ?? const [])
          if (g is Map)
            if ('${g['game_uid'] ?? ''}'.startsWith(prefix) &&
                _keep(Map<String, dynamic>.from(g)))
              Map<String, dynamic>.from(g),
      ];
    });
  }

  /// Filtre tête-à-tête : le mode se lit dans l'identifiant, comme en Kivy —
  /// `online_corr…` pour la correspondance, `online_…` pour le direct.
  bool _keep(Map<String, dynamic> game) {
    final opponent = widget.opponent;
    if (opponent == null) return true;

    final uid = '${game['game_uid'] ?? ''}';
    final isCorr = uid.startsWith('online_corr');
    if (widget.h2hMode == 'corr' && !isCorr) return false;
    if (widget.h2hMode == 'direct' && isCorr) return false;

    final lower = opponent.toLowerCase();
    return '${game['joueur1'] ?? ''}'.toLowerCase() == lower ||
        '${game['joueur2'] ?? ''}'.toLowerCase() == lower;
  }

  // ── Ouverture d'une partie ────────────────────────────────────────────────

  Future<void> _openAccountGame(Map<String, dynamic> game) async {
    final r = await widget.online.client.getGame('${game['game_uid'] ?? ''}');
    if (!mounted) return;
    final nmc = r.get<String>('nmc_text');
    if (nmc == null) {
      await _showError(T('Impossible de charger la partie.'));
      return;
    }
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ReplayScreen(nmc: nmc)));
  }

  Future<void> _openLocalGame(LocalGame game) async {
    final nmc = await widget.store.read(game.file);
    if (!mounted) return;
    if (nmc == null) {
      await _showError(
        T(
          'désolé, le fichier nmc est invalide,\nla lecture ne peut pas s effectuer',
        ),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ReplayScreen(nmc: nmc)));
  }

  Future<void> _showError(String message) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: kFugaGrey,
      title: Text(T('Erreur'), style: const TextStyle(color: Colors.white)),
      content: Text(
        message,
        style: TextStyle(color: Colors.white, fontSize: SF(13)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(T('OK')),
        ),
      ],
    ),
  );

  /// Le bouton « Copier » : Kivy montre le contenu dans une zone de texte
  /// qu'on sélectionne à la main. Ici le presse-papiers fait le travail, et la
  /// popup reste pour ceux qui veulent relire avant de coller.
  Future<void> _copyNmc(LocalGame game) async {
    final content = await widget.store.read(game.file);
    if (content == null || !mounted) return;
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kFugaGrey,
        title: Text(
          T('Contenu .nmc'),
          style: const TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              content,
              style: TextStyle(color: Colors.white, fontSize: SF(13)),
            ),
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
  }

  // ── Affichage ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return FugaScaffold(
      body: SafeArea(
        child: Column(
          children: [
            FugaHeader(
              back: T('< Historique'),
              title: widget.mode == HistoryMode.online
                  ? T('En ligne')
                  : T('En local'),
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (widget.mode == HistoryMode.online && !widget.online.isLoggedIn) {
      return _notice(T('Connectez-vous pour voir vos parties en ligne.'));
    }
    if (_loading) {
      return _notice(
        widget.mode == HistoryMode.online
            ? T('Chargement des parties en ligne…')
            : T('Chargement…'),
      );
    }
    final error = _error;
    if (error != null) {
      return _notice(
        T("Impossible de charger l'historique\n(%s)").replaceAll('%s', error),
        color: const Color.fromRGBO(153, 51, 51, 1),
      );
    }

    final empty = widget.mode == HistoryMode.online
        ? T(
            'Aucune partie en ligne.\nJouez une partie en ligne pour la voir ici !',
          )
        : T(
            "Aucune partie locale.\nJouez en local ou contre l'IA pour la voir ici !",
          );

    if (_fromServer) {
      final games = _accountGames ?? const [];
      if (games.isEmpty) return _notice(empty);
      return ListView.separated(
        padding: EdgeInsets.fromLTRB(S(12), S(8), S(12), S(12)),
        itemCount: games.length,
        separatorBuilder: (_, __) => SizedBox(height: S(8)),
        itemBuilder: (context, i) => _accountEntry(games[i]),
      );
    }

    final files = _localFiles ?? const <LocalGame>[];
    if (files.isEmpty) return _notice(empty);
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(S(12), S(8), S(12), S(12)),
      itemCount: files.length,
      separatorBuilder: (_, __) => SizedBox(height: S(8)),
      itemBuilder: (context, i) => _fileEntry(files[i]),
    );
  }

  Widget _notice(String text, {Color color = const Color(0xFF4D4D4D)}) =>
      Padding(
        padding: EdgeInsets.all(S(24)),
        child: Align(
          alignment: Alignment.topCenter,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: SF(15),
              fontStyle: FontStyle.italic,
              color: color,
            ),
          ),
        ),
      );

  /// Une partie du compte : symbole, noms encadrés des deux avatars, date,
  /// cadence et méthode.
  Widget _accountEntry(Map<String, dynamic> g) {
    final method = '${g['methode'] ?? '?'}';
    final result = '${g['resultat'] ?? '?'}';
    final player1 = '${g['joueur1'] ?? 'Joueur 1'}';
    final player2 = '${g['joueur2'] ?? 'Joueur 2'}';

    // Le serveur date les parties en secondes depuis l'époque.
    var date = '';
    final ts = int.tryParse('${g['played_at'] ?? ''}');
    if (ts != null) {
      final t = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      date =
          '${t.year}-${_two(t.month)}-${_two(t.day)} '
          '${_two(t.hour)}:${_two(t.minute)}';
    }

    // Vert si j'ai gagné, rouge si j'ai perdu, gris pour une nulle : le point
    // de vue est celui du joueur connecté, pas celui des Blancs.
    final (String sym, Color symColor) = switch (result) {
      '1-0' || '0-1' => (
        _kDoubleMethods.contains(method) ? '*' : '#',
        _iWon(result, player2)
            ? const Color.fromRGBO(77, 217, 77, 1)
            : const Color.fromRGBO(255, 84, 84, 1),
      ),
      _ => ('½', const Color.fromRGBO(191, 191, 191, 1)),
    };

    return _card(
      onTap: () => _openAccountGame(g),
      sym: sym,
      symColor: symColor,
      names: Row(
        children: [
          ProfilePhoto(
            photo: avatarPhotoFor(player1, '${g['joueur1_photo'] ?? ''}'),
            size: S(22),
          ),
          SizedBox(width: S(4)),
          Expanded(child: _names(player1, player2)),
          SizedBox(width: S(4)),
          ProfilePhoto(
            photo: avatarPhotoFor(player2, '${g['joueur2_photo'] ?? ''}'),
            size: S(22),
          ),
        ],
      ),
      date: date,
      info: '${_cadenceLabel('${g['cadence'] ?? '?'}')}  •  ${T(method)}',
    );
  }

  /// Une partie lue sur l'appareil. Le symbole vient du résultat et des
  /// points : `*` pour une victoire à deux points, `#` sinon.
  Widget _fileEntry(LocalGame game) {
    final meta = game.meta;
    final (String sym, Color symColor) = switch (meta.result) {
      '1-0' => (
        meta.points == '2' ? '*' : '#',
        const Color.fromRGBO(77, 217, 77, 1),
      ),
      '0-1' => (
        meta.points == '2' ? '*' : '#',
        const Color.fromRGBO(255, 84, 84, 1),
      ),
      _ => ('½', const Color.fromRGBO(191, 191, 191, 1)),
    };

    return Row(
      children: [
        Expanded(
          child: _card(
            onTap: () => _openLocalGame(game),
            sym: sym,
            symColor: symColor,
            names: _names(meta.player1, meta.player2),
            date: meta.date,
            info: '${_cadenceLabel(meta.cadence)}  •  ${T(meta.method)}',
          ),
        ),
        SizedBox(width: S(8)),
        SizedBox(
          width: S(76),
          // L'épaisseur d'une touche, comme partout : une fraction de la
          // HAUTEUR de l'écran. Elle était calculée sur la LARGEUR — S(90) —
          // et c'est passé inaperçu parce que sur un téléphone les deux se
          // ressemblent à 4 % près. Sur une tablette, la touche sortait 56 %
          // trop épaisse.
          height: touchHeight(),
          child: FugaButton(
            text: T('Copier'),
            fontSize: SF(13),
            radius: S(8),
            height: double.infinity,
            onPressed: () => _copyNmc(game),
          ),
        ),
      ],
    );
  }

  Widget _names(String player1, String player2) => Text(
    '$player1  vs  $player2',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: SF(14),
      fontWeight: FontWeight.bold,
      color: Colors.white,
    ),
  );

  Widget _card({
    required VoidCallback onTap,
    required String sym,
    required Color symColor,
    required Widget names,
    required String date,
    required String info,
  }) {
    const secondary = Color.fromRGBO(217, 217, 217, 1);
    return Material(
      color: kFugaGrey,
      borderRadius: BorderRadius.circular(S(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(S(10)),
        onTap: onTap,
        child: SizedBox(
          height: S(90),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: S(12), vertical: S(6)),
            child: Row(
              children: [
                SizedBox(
                  width: S(40),
                  child: Text(
                    sym,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: SF(26),
                      fontWeight: FontWeight.bold,
                      color: symColor,
                    ),
                  ),
                ),
                SizedBox(width: S(10)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 4, child: Center(child: names)),
                      Expanded(
                        flex: 3,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            date,
                            style: TextStyle(
                              fontSize: SF(11),
                              color: secondary,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            info,
                            style: TextStyle(
                              fontSize: SF(11),
                              fontStyle: FontStyle.italic,
                              color: secondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _iWon(String result, String player2) {
    final me = widget.online.pseudo ?? '';
    // joueur1 tient les Blancs : « 1-0 » me fait gagner sauf si je suis le
    // second joueur.
    return (me.isNotEmpty && me == player2) ? result == '0-1' : result == '1-0';
  }

  String _cadenceLabel(String cadence) => switch (cadence) {
    'corr' => T('Corresp'),
    'zen' => T('Zen'),
    '' || '?' => '?',
    _ => '${cadence}min',
  };

  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// Les fins qui valent deux points — elles portent l'étoile du logo.
const Set<String> _kDoubleMethods = {'fugue', 'abandon', 'temps'};
