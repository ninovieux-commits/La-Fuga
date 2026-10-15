/// Profil d'un joueur — portage d'`AccountScreen` (main.py).
///
/// Le même écran sert pour soi et pour les autres : sur son propre profil, la
/// photo, la description, l'adresse mail et les notifications deviennent
/// modifiables, et la liste des joueurs bloqués apparaît.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../game/correspondence.dart';
import '../../game/defi_relais.dart';
import '../../i18n/translations.dart';
import '../../net/notification_permission.dart';
import '../../net/favoris_connus.dart';
import '../../net/online_service.dart';
import '../../net/profile.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import '../widgets/fuga_background.dart';
import '../widgets/corr_slot.dart';
import '../widgets/entete_profil.dart';
import '../widgets/fuga_button.dart';
import '../widgets/game_layout.dart';
import '../widgets/player_card.dart';
import 'corr_game_screen.dart';
import 'history_screen.dart';
import 'photo_picker.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.online,
    this.pseudo,
    this.permission = const AndroidNotificationPermission(),
  });

  final OnlineService online;

  /// Profil à afficher ; `null` pour le sien.
  final String? pseudo;

  /// Autorisation d'afficher les notifications. Injectable pour les tests.
  final NotificationPermission permission;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  /// Les trois notifications secondaires, dans l'ordre de Kivy.
  static const List<(String, String)> _subNotifs = [
    ('turn', "quand c'est à moi de jouer (corresp.)"),
    ('msg', 'quand je reçois un message'),
    ('defi_corr', 'quand quelqu un me défie (corresp.)'),
  ];

  Profile? _profile;

  /// Ses parties de correspondance en cours ; `null` tant qu'on ne les a pas.
  List<CorrGame>? _corrEnCours;

  NotifPrefs _notif = const NotifPrefs();
  bool _loading = true;
  String? _error;

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

    final r = await widget.online.client.getProfile(widget.pseudo);
    if (!mounted) return;
    if (!r.isOk) {
      setState(() {
        _loading = false;
        _error = T('Profil indisponible.');
      });
      return;
    }

    final profile = Profile.fromJson(r.data!);
    setState(() {
      _loading = false;
      _profile = profile;
    });

    unawaited(_chargerParties(profile));

    // Les préférences de notification ne sont pas dans le profil : elles
    // viennent d'`/account_info`, et seulement pour soi.
    if (profile.isSelf) {
      final info = await widget.online.client.accountInfo();
      if (!mounted || !info.isOk) return;
      final raw = info.get<Map<String, dynamic>>('notif');
      setState(() => _notif = NotifPrefs.fromJson(raw));
    }
  }

  /// Ses parties de correspondance en cours.
  ///
  /// Les miennes par `corr_list` ; les siennes par une route que le serveur
  /// n'a pas encore, et qui répond alors 404 — sans bruit, la section dira
  /// « pas de partie en cours ».
  Future<void> _chargerParties(Profile profile) async {
    final r = profile.isSelf
        ? await widget.online.client.corrList()
        : await widget.online.client.corrListPublic(profile.pseudo);
    if (!mounted) return;
    final jeux = [
      for (final g in r.get<List<dynamic>>('games') ?? const [])
        if (g is Map) CorrGame.fromJson(Map<String, dynamic>.from(g)),
    ];
    setState(
      () => _corrEnCours = [
        for (final g in jeux)
          if (g.status == CorrStatus.enCours) g,
      ],
    );
  }

  Future<void> _toggleNotif(String key) async {
    // L'interrupteur général éteint : les autres cases ne répondent plus.
    if (key != 'mail' && !_notif.mail) return;
    final next = _notif.toggled(key);
    setState(() => _notif = next);
    await widget.online.client.setNotifPrefs(next.toJson());

    // Notifications rallumées, mais le téléphone les bloque : Kivy demande la
    // permission, puis explique où la donner si elle a été refusée.
    if (!next.mail) return;
    if (await widget.permission.granted()) return;
    await widget.permission.request();
    if (await widget.permission.granted()) return;
    if (mounted) await _promptNotifPermission();
  }

  /// « Pour recevoir des notifications, autorisez La Fuga… » —
  /// `_prompt_notif_permission`.
  Future<void> _promptNotifPermission() async {
    final palette = paletteOf(Settings.instance.themeAxes.general);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kFugaGrey,
        title: Text(
          T('Notifications'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          T(
            'Pour recevoir des notifications, autorisez La Fuga dans les réglages de votre téléphone.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: SF(14)),
        ),
        actions: [
          FugaButton(
            text: T('Plus tard'),
            fontSize: SF(15),
            onPressed: () => Navigator.of(context).pop(),
          ),
          FugaButton(
            text: T('Ouvrir les réglages'),
            color: palette.clair,
            fontSize: SF(15),
            onPressed: () {
              Navigator.of(context).pop();
              widget.permission.openSettings();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _editText({
    required String title,
    required String initial,
    required String hint,
    required int maxLength,
    required Future<void> Function(String) save,
    bool multiline = false,
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: maxLength,
          maxLines: multiline ? 5 : 1,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(T('Annuler')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(T('Enregistrer')),
          ),
        ],
      ),
    );
    if (value == null) return;
    await save(value);
    if (mounted) await _load();
  }

  Future<void> _pickPhoto() async {
    final photo = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const PhotoPickerScreen()),
    );
    if (photo == null) return;
    await widget.online.client.setPhoto(photo);
    if (mounted) await _load();
  }

  Future<void> _unblock(String pseudo) async {
    await widget.online.client.unblockUser(pseudo);
    if (mounted) await _load();
  }

  Future<void> _logout() async {
    await widget.online.logout();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _push(Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));

  Future<void> _openHistory(String mode) async {
    final profile = _profile;
    if (profile == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HistoryScreen(
          online: widget.online,
          opponent: profile.isSelf ? null : profile.pseudo,
          h2hMode: mode,
        ),
      ),
    );
  }

  /// LES AXES DE LA PERSONNE, pas les miens.
  ///
  /// Nino : « quand on va sur le profil d'une personne, tout doit être monté
  /// selon le thème choisi par la personne. » Le fond, les couleurs des
  /// touches, les aperçus de plateau : tout vient d'ici. Les miens en
  /// secours, tant que le profil n'est pas arrivé — et sur le mien, ce sont
  /// les mêmes.
  ThemeAxes get _axes {
    final theme = _profile?.theme ?? '';
    return theme.isEmpty ? Settings.instance.themeAxes : ThemeAxes.parse(theme);
  }

  /// L'encre lisible sur SON fond : noire sur les thèmes clairs, qui portent
  /// un voile blanc, blanche partout ailleurs.
  Color get _encre => encreSurFond(_axes.menu);

  @override
  Widget build(BuildContext context) {
    final axes = _axes;
    final palette = paletteOf(axes.general);
    final profile = _profile;

    return FugaScaffold(
      theme: axes.menu,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(S(10)),
          child: SizedBox(
            height: touchHeight(),
            child: Row(
              children: [
                Expanded(
                  flex: (profile?.isSelf ?? false) ? 6 : 10,
                  child: FugaButton(
                    // « RETOUR », et non « revenir au menu » : cette touche
                    // rend l'écran d'où l'on vient, qui n'est le menu que
                    // lorsqu'on y est entré par le menu. La fiche d'un joueur
                    // ouvre ce profil depuis une partie, une conversation,
                    // l'historique — y promettre le menu serait faux.
                    text: T('Retour'),
                    color: palette.clair,
                    fontSize: SF(15),
                    height: double.infinity,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                if (profile?.isSelf ?? false) ...[
                  SizedBox(width: S(8)),
                  Expanded(
                    flex: 4,
                    child: FugaButton(
                      text: T('Se déconnecter'),
                      fontSize: SF(14),
                      height: double.infinity,
                      onPressed: _logout,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : profile == null
          ? Center(child: Text(_error ?? T('Profil indisponible.')))
          // LE MÊME ÉCRAN POUR SOI ET POUR LES AUTRES.
          //
          // Nino : « le profil perso et le profil d'autrui doivent être
          // construits de la même façon et avec les mêmes proportions. » Les
          // seules différences sont celles qu'il a nommées : la photo et la
          // devise se touchent pour les changer, le « moi contre » disparaît,
          // les joueurs bloqués et la déconnexion apparaissent.
          //
          // Le fond de la page est SON fond de menu, d'un bord à l'autre :
          // le bandeau du haut n'a plus de décor à lui, et se range donc
          // dans les mêmes marges que le reste.
          : ListView(
              // Nino : « le tout doit être décalé vers le bas de la taille
              // des bandeaux dans les parties », puis, l'ayant vu : « moins
              // grand l'espace au-dessus du profil, tu peux le diviser par
              // 3. » Un bandeau entier dégageait bien plus que ce que le haut
              // de l'écran mange ; le tiers suffit à sortir le pseudo de
              // dessous la barre d'état.
              padding: EdgeInsets.only(top: hauteurBandeauJoueur() / 3),
              children: [
                _entete(profile, palette),
                Padding(
                  padding: EdgeInsets.fromLTRB(S(16), S(12), S(16), S(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!profile.isSelf) ..._moiContre(profile),
                      _title(T('Parties :')),
                      _parties(profile),
                      _title(
                        profile.isSelf ? T('Me suivent :') : T('Le suivent :'),
                      ),
                      ..._gens(
                        profile.followers,
                        T('Personne ne le suit encore.'),
                        palette,
                      ),
                      _title(profile.isSelf ? T('Je suis :') : T('Suivis :')),
                      ..._gens(
                        profile.following,
                        T('Ne suit personne.'),
                        palette,
                      ),
                      if (profile.isSelf) ...[
                        _title(T('Joueurs bloqués :')),
                        ..._gens(
                          profile.blocked,
                          T('Aucun joueur bloqué.'),
                          palette,
                          debloquer: true,
                        ),
                        ..._selfSettings(profile),
                      ],
                      SizedBox(height: S(14)),
                      Row(
                        children: [
                          Expanded(
                            child: _action(
                              T('Historique local'),
                              () => _push(
                                HistoryScreen(
                                  online: widget.online,
                                  mode: HistoryMode.local,
                                  target: _historyTarget(profile),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: S(8)),
                          Expanded(
                            child: _action(
                              T('Historique en ligne'),
                              () => _push(
                                HistoryScreen(
                                  online: widget.online,
                                  target: _historyTarget(profile),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Nino : « ajoute juste entre les boutons historique
                      // local / historique en ligne et le bouton revenir au
                      // menu les boutons retirer/favori et bloquer ».
                      if (!profile.isSelf)
                        Row(
                          children: [
                            Expanded(
                              child: _action(
                                _favori ? T('Retirer') : T('Favori'),
                                _basculerFavori,
                                couleur: palette.fonce,
                              ),
                            ),
                            SizedBox(width: S(8)),
                            Expanded(
                              child: _action(
                                _bloque ? T('Débloquer') : T('Bloquer'),
                                _basculerBlocage,
                                couleur: kRougeBloquer,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// Le haut du profil : sa photo, son pseudo étoilé, ses mélos, sa devise.
  Widget _entete(Profile profile, ThemePalette palette) {
    return EnteteProfil(
      pseudo: profile.pseudo,
      photo: profile.photo,
      devise: profile.description,
      melo: profile.melo,
      meloRandom: profile.meloRandom,
      theme: _axes.menu,
      palette: palette,
      favori: !profile.isSelf && _favori,
      onPhoto: profile.isSelf ? _pickPhoto : null,
      onDevise: profile.isSelf
          ? () => _editText(
              title: T('Devise'),
              initial: profile.description,
              hint: T('Écris ta devise…'),
              maxLength: 500,
              multiline: true,
              save: widget.online.client.setDescription,
            )
          : null,
    );
  }

  /// Les deux scores en tête-à-tête, côte à côte, qui ouvrent l'historique
  /// filtré — tels que Nino les dessine.
  List<Widget> _moiContre(Profile profile) => [
    _title(T('Moi contre :')),
    Row(
      children: [
        Expanded(
          child: _action(
            '${T("Direct")} : ${profile.direct.mine}/${profile.direct.theirs}',
            () => _openHistory('direct'),
          ),
        ),
        SizedBox(width: S(8)),
        Expanded(
          child: _action(
            '${T("Corresp")} : '
            '${profile.correspondence.mine}/${profile.correspondence.theirs}',
            () => _openHistory('corr'),
          ),
        ),
      ],
    ),
  ];

  /// Ses parties de correspondance EN COURS, aux aperçus du menu.
  ///
  /// Sur mon profil, elles viennent de `corr_list`, qui ne rend que les
  /// miennes. Sur celui d'un autre, il faut une route que le serveur n'a pas
  /// encore : tant qu'elle manque, la section dit « pas de partie en cours »,
  /// ce que le dessin de Nino prévoit comme l'un des deux états.
  Widget _parties(Profile profile) {
    final parties = _corrEnCours;
    if (parties == null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: S(8)),
        child: Center(
          child: SizedBox(
            width: S(20),
            height: S(20),
            child: CircularProgressIndicator(strokeWidth: S(2)),
          ),
        ),
      );
    }
    if (parties.isEmpty) {
      return Text(
        T('Pas de partie en cours'),
        style: TextStyle(
          color: _encre.withValues(alpha: 0.5),
          fontSize: SF(13),
        ),
      );
    }

    final axes = _axes;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // La MÊME grille qu'au menu : deux colonnes, la forme du plateau.
      // Nino : « les plateaux d'aperçus doivent faire la même taille que ceux
      // du menu ».
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: S(10),
        crossAxisSpacing: S(10),
        childAspectRatio: 7 / 8,
      ),
      itemCount: parties.length,
      itemBuilder: (context, i) => CorrSlot(
        game: parties[i],
        // Sur le profil de quelqu'un d'autre, la case porte les DEUX noms et
        // dit lequel des deux doit jouer.
        proprietaire: profile.isSelf ? '' : profile.pseudo,
        palette: paletteOf(axes.general),
        boardTheme: axes.board,
        pieceTheme: axes.pieces,
        onTap: () => _ouvrirPartie(parties[i]),
        onShow: (g) => _ouvrirPartie(g),
        onAccept: (_) {},
        onRefuse: (_) {},
        onCancel: (_) {},
        onRematch: (_) {},
        onClose: (_) {},
        onShowChallenge: (_) {},
      ),
    );
  }

  /// Ouvre une partie de correspondance depuis le profil.
  ///
  /// Les miennes s'ouvrent comme au menu. Celles d'un autre s'ouvrent en
  /// VISITEUR — Nino : « donner sur la partie de la personne en mode visiteur
  /// (ne peut pas intervenir ni voir la boîte de message) ». L'écran est le
  /// même ; c'est le drapeau qui éteint le doigt, le ½, le X et le Chat.
  Future<void> _ouvrirPartie(CorrGame game) async {
    final profile = _profile;
    if (profile == null) return;
    await _push(
      CorrGameScreen(
        game: game,
        service: CorrespondenceService(widget.online.client),
        // En visite, c'est SON nom qui va sous le plateau : la partie est
        // rendue de son point de vue.
        myPseudo: profile.isSelf
            ? (widget.online.pseudo ?? T('Moi'))
            : profile.pseudo,
        visiteur: !profile.isSelf,
      ),
    );
    if (mounted) await _load();
  }

  List<Widget> _selfSettings(Profile profile) => [
    _title(T('Adresse mail')),
    Text(
      profile.email.isEmpty ? T('Aucune adresse mail') : profile.email,
      style: TextStyle(color: _encre),
    ),
    _action(
      T("Renseigner ou changer l'adresse mail"),
      () => _editText(
        title: T('Adresse mail'),
        initial: profile.email,
        hint: T('Nouvelle adresse mail'),
        maxLength: 120,
        save: widget.online.client.setEmail,
      ),
    ),
    _checkbox('mail', T('Recevoir des notifications :'), sub: false),
    for (final (key, label) in _subNotifs) _checkbox(key, T(label)),
  ];

  /// Historique de qui : le mien sur mon profil, le sien sur celui d'un
  /// tiers — le `target_pseudo` d'`_open_history` chez Kivy.
  String? _historyTarget(Profile profile) =>
      profile.isSelf ? null : profile.pseudo;

  Widget _checkbox(String key, String label, {bool sub = true}) {
    final enabled = key == 'mail' || _notif.mail;
    return Padding(
      padding: EdgeInsets.only(left: sub ? 24 : 0),
      child: CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: _notif[key] && enabled,
        onChanged: enabled ? (_) => _toggleNotif(key) : null,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          label,
          style: TextStyle(
            color: enabled ? _encre : _encre.withValues(alpha: 0.5),
            fontSize: SF(13),
          ),
        ),
      ),
    );
  }

  /// Une liste de gens : chaque nom est une TOUCHE qui ouvre LA fiche.
  ///
  /// Nino : « les noms des "le suivent" et "suivis" doivent être des boutons
  /// cliquables affichant le popup qu'on a branché partout tout à l'heure. »
  /// Ils menaient jusqu'ici à leur profil, ce qui empilait les profils les uns
  /// sur les autres ; la fiche, elle, y mène par sa touche « Profil » et offre
  /// le reste au passage.
  List<Widget> _gens(
    List<Person> gens,
    String vide,
    ThemePalette palette, {
    bool debloquer = false,
  }) {
    if (gens.isEmpty) {
      return [
        Text(
          vide,
          style: TextStyle(color: Colors.white38, fontSize: SF(12)),
        ),
      ];
    }
    return [
      for (final p in gens)
        Padding(
          padding: EdgeInsets.symmetric(vertical: S(3)),
          child: Row(
            children: [
              Icon(
                p.online ? Icons.circle : Icons.circle_outlined,
                size: S(12),
                color: p.online
                    ? Colors.greenAccent
                    : _encre.withValues(alpha: 0.4),
              ),
              SizedBox(width: S(8)),
              Expanded(
                child: FugaButton(
                  text: '${p.pseudo}   ${p.melo}',
                  fontSize: SF(14),
                  height: touchHeight() * 0.8,
                  onPressed: () => _fiche(p.pseudo, palette),
                ),
              ),
              if (debloquer) ...[
                SizedBox(width: S(8)),
                SizedBox(
                  width: S(96),
                  child: FugaButton(
                    text: T('Débloquer'),
                    fontSize: SF(13),
                    height: touchHeight() * 0.8,
                    onPressed: () => _unblock(p.pseudo),
                  ),
                ),
              ],
            ],
          ),
        ),
    ];
  }

  /// LA fiche, celle qui s'ouvre partout ailleurs — et le défi qu'elle peut
  /// lancer.
  Future<void> _fiche(String pseudo, ThemePalette palette) async {
    final cible = await showPlayerCard(
      context,
      online: widget.online,
      palette: palette,
      pseudo: pseudo,
    );
    if (cible != null) await DefiRelais.defier(cible);
  }

  Widget _title(String text) => Padding(
    padding: EdgeInsets.only(top: S(18), bottom: S(6)),
    child: Text(
      text,
      style: TextStyle(
        color: _encre,
        fontWeight: FontWeight.bold,
        fontSize: SF(15),
      ),
    ),
  );

  /// Est-il dans mes favoris ? Suit l'état du profil chargé, puis mes
  /// propres bascules.
  bool get _favori => _favoriLocal ?? (_profile?.isFavorite ?? false);
  bool? _favoriLocal;

  /// Ajoute ou retire des favoris, et le dit.
  Future<void> _basculerFavori() async {
    final profile = _profile;
    if (profile == null || profile.isSelf) return;
    final etait = _favori;
    final r = etait
        ? await widget.online.client.removeFavorite(profile.pseudo)
        : await widget.online.client.addFavorite(profile.pseudo);
    if (!mounted) return;
    if (r.isOk) {
      setState(() => _favoriLocal = !etait);
      // Le cache apprend : l'étoile du bandeau d'une partie en cours suit.
      FavorisConnus.instance.retiens(profile.pseudo, !etait);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          r.isOk
              ? (etait
                        ? T('%s retiré des favoris.')
                        : T('%s ajouté aux favoris.'))
                    .replaceFirst('%s', profile.pseudo)
              : T('Erreur : %s').replaceFirst('%s', r.error ?? ''),
        ),
      ),
    );
  }

  /// Est-il bloqué ? Comme pour l'étoile : l'état du profil chargé, puis mes
  /// propres bascules.
  bool get _bloque => _bloqueLocal ?? (_profile?.isBlocked ?? false);
  bool? _bloqueLocal;

  /// Bloque ou débloque, et le dit.
  Future<void> _basculerBlocage() async {
    final profile = _profile;
    if (profile == null || profile.isSelf) return;
    final etait = _bloque;
    final r = etait
        ? await widget.online.client.unblockUser(profile.pseudo)
        : await widget.online.client.blockUser(profile.pseudo);
    if (!mounted) return;
    if (r.isOk) setState(() => _bloqueLocal = !etait);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          r.isOk
              ? (etait ? T('%s débloqué.') : T('%s bloqué.')).replaceFirst(
                  '%s',
                  profile.pseudo,
                )
              : T('Erreur : %s').replaceFirst('%s', r.error ?? ''),
        ),
      ),
    );
  }

  /// Les boutons du profil, tels que Kivy les dessine : pleins, gris, sans
  /// icône.
  Widget _action(
    String label,
    VoidCallback onTap, {
    Color couleur = kFugaGrey,
  }) => Padding(
    padding: EdgeInsets.symmetric(vertical: S(4)),
    child: FugaButton(
      text: label,
      color: couleur,
      fontSize: SF(14),
      onPressed: onTap,
    ),
  );
}
