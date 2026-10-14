/// Le haut du profil : la photo, le pseudo étoilé, les mélos, la devise.
///
/// Nino, dessin à l'appui : « le pseudo doit occuper l'espace (plus grand si
/// pseudo court). La devise doit être dans une bulle qui pointe vers l'image
/// de profil à gauche (comme dans les chats). »
///
/// ## Pas de fond à lui
///
/// Le bandeau a d'abord porté une TRANCHE du fond de menu de la personne,
/// découpée à sa hauteur. Deux cadrages de la même image se touchaient alors
/// au milieu de l'écran, et la couture se voyait. Nino : « la partie du haut
/// ne doit pas avoir une partie de fond séparée : on met carrément le fond de
/// menu choisi par la personne en fond de son profil. » C'est `FugaScaffold`
/// qui s'en charge, pour la page entière ; ici il ne reste que le contenu.
///
/// ## Et plus aucune hauteur fixe
///
/// Le bandeau faisait une hauteur calculée, et chaque ligne vivait dans sa
/// boîte : `S(34)` pour le nom, `S(16)` pour les mélos. Or les boîtes se
/// mesurent en `S` et les polices en `SF`, qui vaut **1,70 fois plus**. Une
/// police dont le minimum est `SF(9)` fait 15,3 avant même l'interligne : elle
/// ne pouvait pas tenir dans 16, et la ligne des mélos sortait coupée en deux
/// sur tous les téléphones. Tout se mesure maintenant sur son contenu — le
/// bandeau est aussi haut qu'il le faut, et rien n'est jamais tranché.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'bulle_devise.dart';
import 'fuga_background.dart';
import 'etoile_favori.dart';
import 'profile_photo.dart';
import 'texte_remplissant.dart';

/// Côté de la photo. Le reste du bandeau s'organise autour.
double hauteurPhotoProfil() => S(116);

class EnteteProfil extends StatelessWidget {
  const EnteteProfil({
    super.key,
    required this.pseudo,
    required this.photo,
    required this.devise,
    required this.melo,
    required this.meloRandom,
    required this.theme,
    required this.palette,
    required this.favori,
    this.onPhoto,
    this.onDevise,
  });

  final String pseudo;
  final String photo;

  /// Sa devise — la `description` du serveur. Vide : la bulle le dit.
  final String devise;

  /// Ses deux classements, écrits sous le pseudo.
  final int melo;
  final int meloRandom;

  /// Le thème de MENU de la personne : c'est son décor qui est derrière, et
  /// c'est lui qui décide de la couleur de l'encre.
  final String theme;

  final ThemePalette palette;
  final bool favori;

  /// Sur MON profil, la photo et la devise se touchent pour les changer.
  final VoidCallback? onPhoto;
  final VoidCallback? onDevise;

  @override
  Widget build(BuildContext context) => Padding(
    // Les mêmes marges que le reste de la page : sans décor à lui, le
    // bandeau n'a plus de raison de toucher les bords.
    padding: EdgeInsets.fromLTRB(S(16), S(12), S(16), 0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _photo(),
        SizedBox(width: S(12)),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _nom(),
              SizedBox(height: S(4)),
              _melos(),
              SizedBox(height: S(6)),
              _devise(),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _photo() {
    final cote = hauteurPhotoProfil();
    final image = ProfilePhoto(photo: photo, size: cote);
    if (onPhoto == null) return image;
    return GestureDetector(
      onTap: onPhoto,
      child: SizedBox(
        width: cote,
        height: cote,
        child: Stack(
          children: [
            image,
            Positioned(top: 0, left: 0, child: _crayon()),
          ],
        ),
      ),
    );
  }

  /// Le petit crayon qui dit « ceci se change ».
  Widget _crayon() => Container(
    padding: EdgeInsets.all(S(3)),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(S(6)),
    ),
    child: Icon(Icons.edit, size: SF(14), color: Colors.white),
  );

  /// Noire sur un fond clair voilé, blanche ailleurs.
  Color get _encre => encreSurFond(theme);

  Widget _nom() => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      // L'étoile garde sa taille : un pseudo court grandit, elle non — une
      // étoile géante prendrait toute la place du nom.
      if (favori) ...[
        Icon(Icons.star, size: SF(22), color: kEtoileFavori),
        SizedBox(width: S(6)),
      ],
      Expanded(
        child: TexteRemplissant(
          pseudo,
          style: TextStyle(color: _encre, fontWeight: FontWeight.bold),
          tailleMin: SF(14),
          tailleMax: SF(34),
        ),
      ),
    ],
  );

  /// Les deux classements, sous le pseudo — comme sur la fiche du joueur.
  Widget _melos() => TexteRemplissant(
    '${T("Mélo : %d").replaceAll('%d', '$melo')}'
    '   ·   '
    '${T("Random : %d").replaceAll('%d', '$meloRandom')}',
    style: TextStyle(
      color: _encre.withValues(alpha: 0.85),
      fontWeight: FontWeight.bold,
    ),
    tailleMin: SF(9),
    tailleMax: SF(14),
  );

  Widget _devise() {
    final vide = devise.trim().isEmpty;
    final texte = vide ? _sansDevise : devise.trim();
    final corps = TexteRemplissant(
      texte,
      style: TextStyle(
        color: vide ? Colors.white54 : Colors.white,
        fontStyle: vide ? FontStyle.italic : FontStyle.normal,
      ),
      tailleMin: SF(10),
      tailleMax: SF(20),
      maxLignes: 3,
    );
    final bulle = BulleDevise(
      couleur: palette.fonce,
      // Le crayon est À CÔTÉ du texte, pas dessus : posé en surimpression
      // dans le coin, il masquait le premier mot de la devise.
      child: onDevise == null
          ? corps
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _crayon(),
                SizedBox(width: S(6)),
                Expanded(child: corps),
              ],
            ),
    );
    return onDevise == null
        ? bulle
        : GestureDetector(onTap: onDevise, child: bulle);
  }

  /// Ce qu'on écrit quand il n'y a pas de devise. Sur son propre profil, la
  /// phrase invite à en mettre une ; sur celui d'un autre, elle constate.
  String get _sansDevise =>
      onDevise == null ? T('Pas de devise') : T('Ajoute ta devise…');
}
