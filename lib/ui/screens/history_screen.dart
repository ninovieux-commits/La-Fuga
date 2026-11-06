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

import '../../i18n/translations.dart';
import '../../net/messages.dart';
import '../../net/online_service.dart';
import '../../game/nmc.dart';
import '../../state/local_games.dart';
import '../scale.dart';
import '../widgets/fuga_background.dart';
import '../widgets/fuga_button.dart';
import '../widgets/nmc_dialog.dart';
import '../widgets/picto_touche.dart';
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
    setState(() {
      _loading = false;
      _accountGames = [
        for (final g in r.get<List<dynamic>>('games') ?? const [])
          if (g is Map)
            if (_inThisTab('${g['game_uid'] ?? ''}') &&
                _keep(Map<String, dynamic>.from(g)))
              Map<String, dynamic>.from(g),
      ];
    });
  }

  /// Cette partie appartient-elle à l'onglet affiché ?
  ///
  /// Le préfixe de l'identifiant le dit : `online_` pour les parties du compte,
  /// `local_` pour celles de l'appareil. Une exception, et c'était un trou :
  /// le serveur archivait les parties de correspondance sous `corr_<id>`, qui
  /// ne commence ni par l'un ni par l'autre. Elles étaient bien enregistrées
  /// et n'apparaissaient NULLE PART. Le serveur les nomme désormais
  /// `online_corr<id>` ; celles d'avant sont rattachées ici à « En ligne », là
  /// où elles ont toujours eu leur place.
  bool _inThisTab(String uid) {
    if (uid.startsWith('local_')) return widget.mode == HistoryMode.local;
    if (uid.startsWith('online_') || _isLegacyCorr(uid)) {
      return widget.mode == HistoryMode.online;
    }
    return false;
  }

  /// Identifiant de correspondance d'avant la correction du serveur.
  static bool _isLegacyCorr(String uid) => uid.startsWith('corr_');

  /// Filtre tête-à-tête : le mode se lit dans l'identifiant —
  /// `online_corr…` pour la correspondance, `online_…` pour le direct.
  bool _keep(Map<String, dynamic> game) {
    final opponent = widget.opponent;
    if (opponent == null) return true;

    final uid = '${game['game_uid'] ?? ''}';
    final isCorr = uid.startsWith('online_corr') || _isLegacyCorr(uid);
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
    await showNmcDialog(context, content);
  }

  /// Le .nmc d'une partie EN LIGNE. Le fichier n'est pas sur le téléphone :
  /// le serveur le rend par `get_game`, à partir du `game_uid`.
  Future<void> _copyAccountNmc(Map<String, dynamic> game) async {
    final r = await widget.online.client.getGame('${game['game_uid'] ?? ''}');
    if (!mounted) return;
    final content = r.get<String>('nmc_text');
    if (content == null || content.isEmpty) {
      await _showError(T('Impossible de charger la partie.'));
      return;
    }
    await showNmcDialog(context, content);
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

    // Vert s'il a gagné, rouge s'il a perdu, gris sinon : le point de vue est
    // celui du joueur DONT ON LIT L'HISTORIQUE, pas celui des Blancs.
    final gagne = _aGagne(result, player1, player2);
    final (String sym, Color symColor) = switch (result) {
      '1-0' || '0-1' => (
        _kDoubleMethods.contains(method) ? '*' : '#',
        switch (gagne) {
          true => _kVertDuGain,
          false => _kRougeDeLaPerte,
          null => _kGrisNeutre,
        },
      ),
      _ => ('½', _kGrisNeutre),
    };

    final carte = _card(
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
          Expanded(
            child: _names(
              player1,
              player2,
              // Le serveur ne les range pas encore ; le jour où il le fera,
              // ces deux lignes les afficheront sans rien changer d'autre.
              melo1: _entier(g['melo1']),
              melo2: _entier(g['melo2']),
              variation1: _entier(g['variation1']),
              variation2: _entier(g['variation2']),
              blancEstLePremier: _blancEstLePremier(g),
            ),
          ),
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

    // Même touche « Copier » que sur l'historique local. Kivy ne l'offre que
    // pour les parties du téléphone, mais rien ne le justifie : une partie en
    // ligne a le même .nmc, le serveur sait le rendre.
    return Row(
      children: [
        Expanded(child: carte),
        SizedBox(width: S(8)),
        SizedBox(
          width: S(76),
          height: touchHeight(),
          child: FugaButton(
            text: T('Copier'),
            fontSize: SF(13),
            radius: S(8),
            height: double.infinity,
            onPressed: () => _copyAccountNmc(g),
          ),
        ),
      ],
    );
  }

  /// Une partie lue sur l'appareil. Le symbole vient du résultat et des
  /// points : `*` pour une victoire à deux points, `#` sinon.
  Widget _fileEntry(LocalGame game) {
    final meta = game.meta;
    final (String sym, Color symColor) = switch (meta.result) {
      '1-0' => (meta.points == '2' ? '*' : '#', _kVertDuGain),
      '0-1' => (meta.points == '2' ? '*' : '#', _kRougeDeLaPerte),
      _ => ('½', _kGrisNeutre),
    };

    return Row(
      children: [
        Expanded(
          child: _card(
            onTap: () => _openLocalGame(game),
            sym: sym,
            symColor: symColor,
            names: _names(
              meta.player1,
              meta.player2,
              melo1: meta.melo1,
              melo2: meta.melo2,
              variation1: meta.variation1,
              variation2: meta.variation2,
              blancEstLePremier: meta.blanc == meta.player1,
            ),
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

  /// Les deux noms, et CE QUE CHACUN A GAGNÉ OU PERDU AU MÉLO.
  ///
  /// Nino : « il faut que les mélos gagnés et perdus durant une partie
  /// soient spécifiés dans l'historique, à côté des noms des joueurs. »
  ///
  /// La variation est écrite PLUS PETITE et en couleur, verte ou rouge, pour
  /// qu'elle se lise comme une annotation du nom et non comme une partie du
  /// nom. Absente, elle ne prend pas de place : une partie locale n'est pas
  /// classée, et une partie en ligne n'a aujourd'hui que la variation du
  /// joueur qui l'a enregistrée — le serveur n'annonce pas encore celle de
  /// l'adversaire.
  Widget _names(
    String player1,
    String player2, {
    int? melo1,
    int? melo2,
    int? variation1,
    int? variation2,
    bool? blancEstLePremier,
  }) {
    final nom = TextStyle(
      fontSize: SF(14),
      fontWeight: FontWeight.bold,
      color: Colors.white,
    );
    // LE CLASSEMENT, PUIS CE QU'IL A FAIT. Nino : « ajoute aussi le mélo
    // des joueurs tel que : mesange 1500 -9 vs nino 1512 +9 ». C'est le
    // classement d'APRÈS la partie — celui que le popup de fin annonce —,
    // et la variation qui l'a amené là.
    TextSpan? classement(int? m) => m == null
        ? null
        : TextSpan(
            text: ' $m',
            style: TextStyle(fontSize: SF(11), fontWeight: FontWeight.normal),
          );
    TextSpan? variation(int? v) => v == null
        ? null
        : TextSpan(
            text: ' ${NmcMeta.signe(v)}',
            style: TextStyle(
              fontSize: SF(11),
              fontWeight: FontWeight.bold,
              // ZÉRO N'EST NI L'UN NI L'AUTRE : une partie classée qui ne
              // déplace rien se dit « +0 », en gris.
              color: switch (v) {
                > 0 => _kVertDuGain,
                < 0 => _kRougeDeLaPerte,
                _ => _kGrisNeutre,
              },
            ),
          );
    // QUI TENAIT QUELLE COULEUR. Nino : « mets aussi un rond noir ou blanc
    // avant le nom pour indiquer qui avait quelle couleur. » Le rond porte
    // le cerne de l'AUTRE couleur, comme les pièces : sur le gris de la
    // carte, un rond noir se perdrait dans le trait de la touche et un rond
    // blanc dans le mot qui le suit.
    //
    // Inconnue — une partie de l'appareil rangée sur le compte, dont la
    // liste du serveur ne dit pas qui était Blanc —, la couleur ne se
    // devine pas : la ligne se passe alors de ronds.
    InlineSpan? rond(bool? blanc) => blanc == null
        ? null
        : WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.only(right: S(4)),
              child: Container(
                width: SF(9),
                height: SF(9),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: blanc ? Colors.white : Colors.black,
                  border: Border.all(
                    color: blanc ? Colors.black : Colors.white,
                    width: S(kTraitPicto * 0.7),
                  ),
                ),
              ),
            ),
          );
    final premier = blancEstLePremier;
    final rond1 = rond(premier);
    final rond2 = rond(premier == null ? null : !premier);

    // SANS RIEN À AJOUTER, LA LIGNE RESTE CE QU'ELLE ÉTAIT : un texte simple.
    if (melo1 == null &&
        melo2 == null &&
        variation1 == null &&
        variation2 == null &&
        rond1 == null) {
      return Text(
        '$player1  vs  $player2',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: nom,
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          ?rond1,
          TextSpan(text: player1),
          ?classement(melo1),
          ?variation(variation1),
          const TextSpan(text: '  vs  '),
          ?rond2,
          TextSpan(text: player2),
          ?classement(melo2),
          ?variation(variation2),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: nom,
    );
  }

  /// Le premier nommé tenait-il les Blancs ?
  ///
  /// Le serveur le dira un jour dans une colonne `blanc` ; en attendant, une
  /// partie JOUÉE CONTRE QUELQU'UN le dit d'elle-même : son archive range
  /// toujours le Blanc en premier (`buildOpponentArchive`). Une partie de
  /// l'appareil, elle, garde l'ordre d'affichage et ne dit rien — on ne
  /// devine pas, on s'abstient.
  static bool? _blancEstLePremier(Map<String, dynamic> g) {
    final dit = g['blanc'];
    if (dit != null && '$dit'.trim().isNotEmpty) {
      return '$dit'.trim().toLowerCase() ==
          '${g['joueur1'] ?? ''}'.trim().toLowerCase();
    }
    final uid = '${g['game_uid'] ?? ''}';
    if (uid.startsWith('online_') || _isLegacyCorr(uid)) return true;
    return null;
  }

  /// Un entier venu du serveur, quelle que soit la façon dont il l'écrit.
  static int? _entier(Object? v) => switch (v) {
    final num n => n.toInt(),
    final String t => int.tryParse(t.trim()),
    _ => null,
  };

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
      color: kGrisTouche,
      // LE TRAIT NOIR DES TOUCHES. Nino, capture de l'historique en ligne à
      // l'appui : « ces boutons là aussi devraient être encadrés. » Une
      // carte de partie se touche pour la rouvrir : c'est une touche, et les
      // cartes de la messagerie l'avaient déjà.
      shape: formeDeTouche(BorderRadius.circular(S(10))),
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

  /// Cette partie est-elle une victoire POUR CELUI DONT ON LIT L'HISTORIQUE ?
  ///
  /// `null` quand la question n'a pas de sens : il ne joue pas cette
  /// partie-là, et le symbole reste gris plutôt que de prendre la couleur de
  /// quelqu'un.
  ///
  /// Nino : « quand je vais sur le profil de mesange et que j'accède à son
  /// historique, les parties affichent qu'elle a gagné. Peut-être que c'est
  /// affiché de mon point de vue, mais du coup qui est-ce que ça considère
  /// comme gagnant si je regarde une partie qu'elle a faite contre quelqu'un
  /// d'autre ? » C'était le PREMIER JOUEUR, donc les Blancs : dès que je
  /// n'étais pas dans la partie, le vert disait « les Blancs ont gagné » sans
  /// que rien ne le dise. Depuis le profil d'un tiers, c'est SON historique
  /// qu'on lit — donc son point de vue.
  bool? _aGagne(String result, String player1, String player2) {
    final cible = widget.target?.trim() ?? '';
    final vu = cible.isNotEmpty ? cible : (widget.online.pseudo ?? '');
    if (vu.isEmpty) return null;
    // Le serveur ne garantit pas la casse des pseudos : elle ne compte pas,
    // ici comme pour les favoris.
    final lui = vu.toLowerCase();
    // joueur1 tient les Blancs.
    if (lui == player1.trim().toLowerCase()) return result == '1-0';
    if (lui == player2.trim().toLowerCase()) return result == '0-1';
    return null;
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

/// Le gris d'un symbole qui ne prend parti pour personne : une nulle, ou une
/// partie où celui dont on lit l'historique n'est pas.
const Color _kGrisNeutre = Color.fromRGBO(191, 191, 191, 1);

/// Le vert d'un gain et le rouge d'une perte — ceux des symboles de
/// résultat, repris par les variations de mélo pour que la carte ne parle
/// que de deux couleurs.
const Color _kVertDuGain = Color.fromRGBO(77, 217, 77, 1);
const Color _kRougeDeLaPerte = Color.fromRGBO(255, 84, 84, 1);
