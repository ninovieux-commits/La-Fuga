/// Le haut du profil : la photo, le pseudo étoilé, la devise.
///
/// Nino, dessin à l'appui : « la partie du haut (photo pseudo étoile devise)
/// doit avoir comme fond la partie correspondante du fond du menu choisi par
/// la personne. Le pseudo doit occuper l'espace (plus grand si pseudo court).
/// La devise doit être dans une bulle qui pointe vers l'image de profil à
/// gauche (comme dans les chats). »
///
/// « La partie correspondante » : pas l'image entière écrasée dans un
/// bandeau, mais la TRANCHE que ce bandeau occuperait si le fond était posé
/// en plein écran. On dessine donc l'image à la taille de l'écran, alignée en
/// haut, et on coupe à la hauteur du bandeau — le haut du décor de la
/// personne, exactement comme elle le voit sur son menu.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../theme/theme_assets.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'bulle_devise.dart';
import 'fuga_background.dart';
import 'etoile_favori.dart';
import 'profile_photo.dart';
import 'texte_remplissant.dart';

/// Côté de la photo. Le reste du bandeau s'organise autour.
double hauteurPhotoProfil() => S(116);

/// Hauteur du bandeau : la photo et ses marges.
double hauteurEnteteProfil() => hauteurPhotoProfil() + 2 * S(12);

class EnteteProfil extends StatelessWidget {
  const EnteteProfil({
    super.key,
    required this.pseudo,
    required this.photo,
    required this.devise,
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

  /// Le thème de MENU de la personne : c'est son décor qu'on montre.
  final String theme;

  final ThemePalette palette;
  final bool favori;

  /// Sur MON profil, la photo et la devise se touchent pour les changer.
  final VoidCallback? onPhoto;
  final VoidCallback? onDevise;

  @override
  Widget build(BuildContext context) {
    final hauteur = hauteurEnteteProfil();
    return SizedBox(
      height: hauteur,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _tranche(context, hauteur),
          Padding(
            padding: EdgeInsets.all(S(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _photo(),
                SizedBox(width: S(12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: S(34), child: _nom()),
                      SizedBox(height: S(8)),
                      Expanded(child: _devise()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// La tranche du haut de SON fond de menu.
  Widget _tranche(BuildContext context, double hauteur) {
    final image = imagesFor(theme)?.background;
    if (image == null) return ColoredBox(color: palette.menu);
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: MediaQuery.sizeOf(context).height,
            maxHeight: MediaQuery.sizeOf(context).height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(image),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          // Le même voile qu'au menu sur les thèmes clairs, sans quoi la
          // tranche ne ressemblerait pas à ce que la personne voit chez elle.
          if (kThemesVoiles.contains(theme))
            ColoredBox(color: Colors.white.withValues(alpha: 0.45)),
        ],
      ),
    );
  }

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

  Widget _devise() {
    final vide = devise.trim().isEmpty;
    final texte = vide ? _sansDevise : devise.trim();
    final bulle = BulleDevise(
      couleur: palette.fonce,
      child: Stack(
        children: [
          TexteRemplissant(
            texte,
            style: TextStyle(
              color: vide ? Colors.white54 : Colors.white,
              fontStyle: vide ? FontStyle.italic : FontStyle.normal,
            ),
            tailleMin: SF(10),
            tailleMax: SF(20),
            maxLignes: 3,
          ),
          if (onDevise != null) Positioned(top: 0, left: 0, child: _crayon()),
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
