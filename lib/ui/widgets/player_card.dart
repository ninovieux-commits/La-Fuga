/// LA fiche d'un joueur — le seul popup qui s'ouvre sur un nom, où qu'il soit.
///
/// Portage du popup de `_show_player_card` (main.py) : pseudo, mélos, état en
/// ligne, score en tête-à-tête, puis les gestes — profil, défi, favori,
/// blocage.
///
/// Nino : « ce même popup doit également apparaître si on clique sur le nom ou
/// l'image de profil où qu'ils soient (en partie, boîte de dialogue etc.), à
/// part sur le profil ou le popup en question. Ainsi il n'y a qu'un seul
/// popup, toujours le même. » Le menu déroulant qui s'ouvrait en partie
/// (`name_menu.dart`, portage de `_show_name_menu`) n'existe donc plus : il
/// disait moins et ne ressemblait à rien d'autre.
library;

import 'package:flutter/material.dart';

import '../../game/defi_relais.dart';
import '../../i18n/translations.dart';
import '../../net/avatar_photos.dart';
import '../../net/decors_connus.dart';
import '../../net/favoris_connus.dart';
import '../../net/online_service.dart';
import '../../net/profile.dart';
import '../../net/scores_directs.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'etoile_favori.dart';
import 'fuga_button.dart';
import '../screens/account_screen.dart';
import '../screens/history_screen.dart';

/// Rouge du blocage.
const Color kRougeBloquer = Color(0xFFB84343);

/// Les noms qui ne désignent personne — `_is_real_player` (main.py).
///
/// La fiche ne s'ouvre que sur un VRAI joueur, et seulement si l'on est
/// connecté : sans compte, rien de tout cela n'existe.
bool isRealPlayer(String? pseudo) {
  if (pseudo == null || pseudo.trim().isEmpty) return false;
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
  return !placeholders.contains(pseudo.trim());
}

/// Affiche la fiche et renvoie le pseudo à défier, ou `null`.
///
/// Deux façons d'appeler : avec le [player] déjà en main — c'est le cas de la
/// recherche du menu, qui vient de le recevoir — ou avec le seul [pseudo], et
/// la fiche va alors chercher le profil pendant qu'elle est déjà à l'écran.
///
/// La touche « Défier » suit UNE règle, et la fiche l'applique elle-même :
/// elle sert partout tant qu'aucune partie en direct n'est en cours et que le
/// menu est à l'écoute pour mener le défi (voir [DefiRelais]). Aucun appelant
/// n'a à la désactiver — donc aucun ne peut oublier de le faire.
Future<String?> showPlayerCard(
  BuildContext context, {
  required OnlineService online,
  required ThemePalette palette,
  Profile? player,
  String? pseudo,
}) {
  final nom = player?.pseudo ?? pseudo ?? '';
  if (!online.isLoggedIn || !isRealPlayer(nom)) return Future.value();
  return showDialog<String>(
    context: context,
    builder: (_) => _PlayerCard(
      online: online,
      player: player,
      pseudo: nom,
      palette: palette,
    ),
  );
}

class _PlayerCard extends StatefulWidget {
  const _PlayerCard({
    required this.online,
    required this.player,
    required this.pseudo,
    required this.palette,
  });

  final OnlineService online;

  /// Le profil quand on l'a déjà. Sinon `null`, et il arrive par le réseau.
  final Profile? player;

  final String pseudo;
  final ThemePalette palette;

  @override
  State<_PlayerCard> createState() => _PlayerCardState();
}

class _PlayerCardState extends State<_PlayerCard> {
  late Profile? _p = widget.player;
  late bool _favorite =
      widget.player?.isFavorite ??
      (FavorisConnus.instance.connu(widget.pseudo) ?? false);
  late bool _blocked = widget.player?.isBlocked ?? false;
  bool _busy = false;

  /// Le profil n'est pas venu : on le dit au lieu de tourner sans fin.
  bool _echec = false;

  /// Est-ce MOI ?
  ///
  /// Le serveur le dit (`is_self`), mais on le sait déjà sans lui : c'est mon
  /// pseudo. La fiche est donc juste dès la première image, avant même que le
  /// profil arrive — et on ne se propose jamais de se défier, de se mettre en
  /// favori ou de se bloquer soi-même.
  bool get _moi =>
      (_p?.isSelf ?? false) ||
      widget.pseudo == (widget.online.pseudo ?? '\u0000');

  @override
  void initState() {
    super.initState();
    if (_p == null) {
      _charger();
    } else {
      // La fiche arrive avec un profil frais du serveur : il fait autorité, et
      // les écrans restés DESSOUS doivent en profiter — c'est leur étoile.
      //
      // À la fin de la frame, et pas tout de suite : prévenir les caches
      // réveille leurs auditeurs, or la fiche se construit par-dessus un écran
      // en cours de construction, et Flutter refuse un `setState` à ce
      // moment-là.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _retenir(_p!);
      });
    }
  }

  /// Va chercher le profil, la fiche étant DÉJÀ à l'écran.
  ///
  /// L'ouvrir après la réponse aurait fait un temps mort sous le doigt : on
  /// touche un nom, rien ne se passe, puis le popup paraît. Il paraît tout de
  /// suite, avec le nom, et se remplit.
  Future<void> _charger() async {
    final r = await widget.online.client.getProfile(widget.pseudo);
    if (!mounted) return;
    if (!r.isOk || r.data == null) {
      setState(() => _echec = true);
      return;
    }
    final profil = Profile.fromJson(r.data!);
    setState(() {
      _p = profil;
      _favorite = profil.isFavorite;
      _blocked = profil.isBlocked;
    });
    _retenir(profil);
  }

  /// Ce que la réponse apprend aux caches partagés : la photo, le décor,
  /// l'étoile et le score des parties en direct. Une requête, quatre écrans
  /// qui se mettent à jour.
  void _retenir(Profile profil) {
    if (_moi) return;
    AvatarPhotos.remember(profil.pseudo, profil.photo);
    DecorsConnus.remember(profil.pseudo, profil.theme);
    FavorisConnus.instance.retiens(profil.pseudo, profil.isFavorite);
    ScoresDirects.remember(profil.pseudo, profil.direct);
  }

  Future<void> _toggleFavorite() async {
    setState(() => _busy = true);
    final client = widget.online.client;
    final r = _favorite
        ? await client.removeFavorite(widget.pseudo)
        : await client.addFavorite(widget.pseudo);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.isOk) _favorite = !_favorite;
    });
    // L'étoile du bandeau derrière la fiche suit la touche, sans attendre un
    // retour à l'écran.
    if (r.isOk) FavorisConnus.instance.retiens(widget.pseudo, _favorite);
  }

  Future<void> _toggleBlock() async {
    setState(() => _busy = true);
    final client = widget.online.client;
    final r = _blocked
        ? await client.unblockUser(widget.pseudo)
        : await client.blockUser(widget.pseudo);
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
          opponent: widget.pseudo,
          h2hMode: mode,
        ),
      ),
    );
  }

  void _openProfile() {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AccountScreen(
          online: widget.online,
          pseudo: _moi ? null : widget.pseudo,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    // La fiche de Kivy commence par le pseudo seul : elle ne montre pas
    // d'avatar. L'étoile, elle, se range devant le nom, et change avec la
    // touche « Enregistrer / Retirer » plus bas.
    //
    // Taille en dur : le titre d'un `AlertDialog` prend le `titleLarge` du
    // thème, qui ne passe pas par `SF`. L'étoile suit ses lettres.
    title: Text.rich(nomEtoile(widget.pseudo, favori: _favorite, taille: 18)),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _p == null ? _attente() : _fiche(_p!),
    ),
  );

  /// Le profil n'est pas encore là : le popup existe, et on voit qu'il
  /// travaille.
  List<Widget> _attente() => [
    SizedBox(height: S(16)),
    Center(
      child: _echec
          ? Text(T('Joueur introuvable'), textAlign: TextAlign.center)
          : const CircularProgressIndicator(),
    ),
    SizedBox(height: S(16)),
    _touche(texte: T('Fermer'), onPressed: () => Navigator.of(context).pop()),
  ];

  List<Widget> _fiche(Profile p) => [
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
    if (!_moi) ...[
      SizedBox(height: S(12)),
      Text(
        T('Moi contre %s :').replaceAll('%s', widget.pseudo),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      // Les scores mènent à l'historique des parties jouées entre nous. Ils
      // restent du texte touchable — ce ne sont pas des actions — mais plus
      // en violet d'usine.
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
    // Nino : « j'aimerai que les boutons bloquer retirer et fermer soient
    // centrés et élargis ». Elles étaient des touches plates de Material,
    // alignées à droite et VIOLETTES — la graine d'usine de Material 3, que
    // `ThemeData` laisse par défaut faute de jeu de couleurs. Elles
    // descendent du bandeau d'actions dans le corps, dont le `Column` est en
    // `stretch` : c'est lui qui les élargit, et le centrage vient de là.
    _touche(texte: T('Profil'), onPressed: _openProfile),
    if (!_moi && !_blocked)
      _touche(
        texte: T('Défier'),
        couleur: widget.palette.clair,
        encre: Colors.black,
        horsService: !DefiRelais.pret,
        onPressed: () => Navigator.of(context).pop(widget.pseudo),
      ),
    if (!_moi)
      _touche(
        texte: _favorite ? T('Retirer') : T('Enregistrer'),
        couleur: widget.palette.fonce,
        onPressed: _busy ? null : _toggleFavorite,
      ),
    if (!_moi)
      _touche(
        texte: _blocked ? T('Débloquer') : T('Bloquer'),
        couleur: kRougeBloquer,
        onPressed: _busy ? null : _toggleBlock,
      ),
    _touche(texte: T('Fermer'), onPressed: () => Navigator.of(context).pop()),
  ];

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
    bool horsService = false,
  }) {
    final bouton = FugaButton(
      text: texte,
      color: couleur,
      textColor: encre,
      fontSize: SF(15),
      onPressed: horsService ? null : onPressed,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: S(8)),
      // Hors service, la touche PÂLIT — comme les flèches du bandeau des
      // coups, et comme tout ce qui est hors d'usage dans l'application.
      // Elle s'est hachurée le temps d'un essai ; Nino, les hachures vues en
      // vrai : « on vire tout, on remet comme c'était avant, partout. »
      child: horsService ? Opacity(opacity: 0.35, child: bouton) : bouton,
    );
  }
}
