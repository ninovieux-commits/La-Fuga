/// Le classement : les trente meilleurs mélos, dans un volet qui défile.
///
/// Nino : « on doit créer un classement qui liste les trente meilleurs
/// mélos. Je voudrais pour ça un volet qui défile dans un popup. [...] Les
/// noms des comptes et leurs images de profil ainsi que leur mélo
/// apparaissent sur chaque ligne avec une numérotation de 1 à 30. Cliquer
/// dessus envoie sur le profil de la personne. Logiquement ça devrait
/// rappeler un peu le popup favoris. »
///
/// IL SUIT LE MODE DE L'APPLICATION. La touche « standard / random » du
/// bandeau reste accessible pendant que le volet est ouvert, et le volet
/// change de classement avec elle — « quand elle fait passer l'App en mode
/// random, le popup se met à afficher les meilleurs mélos de random, et vice
/// et versa ». C'est [random] qui porte cette bascule ; le volet recharge
/// quand il change, et garde les deux listes pour que l'aller-retour soit
/// immédiat.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../net/avatar_photos.dart';
import '../../net/classement.dart';
import '../../net/online_service.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'fuga_button.dart';
import 'picto_touche.dart';
import 'profile_photo.dart';

/// Hauteur d'une ligne : celle d'une touche, comme la fiche d'un favori.
double get hauteurDUneLigneDuClassement => touchHeight();

class ClassementVolet extends StatefulWidget {
  const ClassementVolet({
    super.key,
    required this.random,
    required this.online,
    required this.palette,
    required this.surJoueur,
  });

  /// Le mode en cours dans l'application : Random Fuga, ou standard.
  final bool random;

  final OnlineService online;
  final ThemePalette palette;

  /// Ce qu'on fait d'un nom touché : son profil.
  final void Function(String pseudo) surJoueur;

  @override
  State<ClassementVolet> createState() => _ClassementVoletState();
}

class _ClassementVoletState extends State<ClassementVolet> {
  /// Les deux classements déjà reçus, par mode. Repasser de l'un à l'autre
  /// ne redemande rien au serveur : la touche du bandeau se bascule vite, et
  /// une liste qui clignote à chaque aller-retour serait pénible.
  final Map<bool, List<RangClassement>> _connus = {};

  /// MA ligne, par mode, telle que le serveur la calcule : mon rang vrai,
  /// même au-delà du trentième. Nino : « le classement doit afficher une
  /// ligne fixe en bas, qui est la ligne de l'utilisateur, pour pouvoir
  /// comparer son propre mélo avec celui des 30 meilleurs joueurs du volet
  /// défilant juste au-dessus. »
  final Map<bool, RangClassement?> _mienne = {};

  bool _charge = false;
  String _erreur = '';

  @override
  void initState() {
    super.initState();
    _demande();
  }

  @override
  void didUpdateWidget(ClassementVolet vieux) {
    super.didUpdateWidget(vieux);
    if (vieux.random != widget.random) _demande();
  }

  Future<void> _demande() async {
    final mode = widget.random;
    if (_connus.containsKey(mode)) {
      setState(() => _erreur = '');
      return;
    }
    setState(() {
      _charge = true;
      _erreur = '';
    });
    final r = await widget.online.client.leaderboard(random: mode);
    if (!mounted) return;
    setState(() {
      _charge = false;
      if (!r.isOk) {
        _erreur = T('Classement indisponible');
        return;
      }
      _connus[mode] = [
        for (final j in r.get<List<dynamic>>('joueurs') ?? const [])
          if (j is Map) RangClassement.fromJson(Map<String, dynamic>.from(j)),
      ];
      final moi = r.get<Map<String, dynamic>>('moi');
      _mienne[mode] = moi == null
          ? null
          : RangClassement.fromJson(Map<String, dynamic>.from(moi));
    });
  }

  @override
  Widget build(BuildContext context) {
    final lignes = _connus[widget.random];
    if (lignes == null) {
      return SizedBox(
        height: touchHeight() * 2,
        child: Center(
          child: _charge
              ? const CircularProgressIndicator()
              : MotTouche(
                  texte: _erreur.isEmpty
                      ? T('Classement indisponible')
                      : _erreur,
                  couleur: Colors.white,
                  style: TextStyle(fontSize: SF(15)),
                ),
        ),
      );
    }
    if (lignes.isEmpty) {
      return SizedBox(
        height: touchHeight() * 2,
        child: Center(
          child: MotTouche(
            texte: T("Personne au classement pour l'instant."),
            couleur: Colors.white,
            maxLines: 2,
            style: TextStyle(fontSize: SF(14)),
          ),
        ),
      );
    }
    final moi = _mienne[widget.random];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // LES TRENTE DÉFILENT, MA LIGNE NON : elle reste sous les yeux
        // pendant qu'on parcourt la liste, sans quoi la comparaison
        // demanderait de se souvenir d'un nombre en défilant.
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: lignes.length,
            separatorBuilder: (_, _) => SizedBox(height: S(6)),
            itemBuilder: (context, i) => _ligne(lignes[i]),
          ),
        ),
        if (moi != null) ...[
          // Un trait, pour qu'on voie tout de suite que cette ligne-là
          // n'appartient pas à la liste qui défile au-dessus.
          Container(
            height: kTraitPicto * 2,
            margin: EdgeInsets.symmetric(vertical: S(8)),
            color: Colors.white54,
          ),
          _ligne(moi),
        ],
      ],
    );
  }

  Widget _ligne(RangClassement j) {
    final cote = hauteurDUneLigneDuClassement;
    final photo = j.photo.isNotEmpty
        ? j.photo
        : AvatarPhotos.known(j.pseudo, online: widget.online);
    return SizedBox(
      height: cote,
      child: Material(
        color: kGrisTouche,
        // PRESQUE CARRÉE. Nino : « les lignes doivent être plus larges et
        // carrées, comme sur ce popup » — celui des favoris, dont les
        // fiches sont longues et à peine arrondies. Une ligne très arrondie
        // se lit comme une touche à part ; à peine arrondie, elle se lit
        // comme une ligne d'un tableau, ce qu'elle est.
        shape: formeDeTouche(BorderRadius.circular(S(6))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => widget.surJoueur(j.pseudo),
          child: Row(
            children: [
              // LE RANG, dans une colonne de largeur fixe : les pseudos
              // commencent tous au même endroit, que le rang s'écrive en un
              // chiffre ou en deux. Et il RÉTRÉCIT plutôt que d'être coupé —
              // le « 10 » sortait « 1 » sur le premier aperçu.
              SizedBox(
                width: cote,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: S(4)),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: MotTouche(
                        texte: '${j.rang}',
                        couleur: widget.palette.clair,
                        style: TextStyle(
                          fontSize: SF(16),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: S(3)),
                child: ProfilePhoto(photo: photo, size: cote - S(6)),
              ),
              SizedBox(width: S(8)),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: MotTouche(
                      texte: j.pseudo,
                      couleur: Colors.white,
                      style: TextStyle(
                        fontSize: SF(15),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: S(8)),
              Padding(
                padding: EdgeInsets.only(right: S(10)),
                child: MotTouche(
                  texte: '${j.melo}',
                  couleur: widget.palette.fonce,
                  style: TextStyle(
                    fontSize: SF(15),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
