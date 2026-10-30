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
/// ## Les proportions du dessin
///
/// « L'emplacement image mesure 1/3 de la largeur de l'écran. La taille du
/// pseudo va bien mais ils ne doivent plus être mangés. La bulle devise
/// occupe la place qu'il reste. »
///
/// (Le décalage du haut, qu'il demandait dans la même phrase, n'est pas
/// l'affaire du bandeau : c'est la marge de la page, dans `account_screen`.)
///
/// La photo donne donc sa hauteur au bandeau, et la colonne de droite se
/// partage la même : une ligne pour le pseudo, une pour les mélos, et la
/// bulle prend tout le bas.
///
/// Tout le bas, et PLUS si la devise le demande : « la bulle doit pouvoir
/// faire trois lignes, rallonge la zone s'il le faut. Si elle fait plus de
/// trois lignes c'est encore mieux. » La bulle a donc un plancher — descendre
/// jusqu'au bas de la photo quand la devise est courte — mais aucun plafond :
/// au-delà, c'est le bandeau qui s'allonge. Entre écrire plus petit et écrire
/// sur une ligne de plus, la devise prend la ligne de plus.
///
/// ## Des boîtes taillées sur la police, et non l'inverse
///
/// Chaque ligne vivait dans une boîte en `S` — `S(34)` pour le nom, `S(16)`
/// pour les mélos — alors que les polices se mesurent en `SF`, qui vaut
/// **1,70 fois plus**. Une police dont le plancher est `SF(9)` fait 15,3
/// avant même l'interligne : elle ne pouvait pas tenir dans 16, et la ligne
/// des mélos sortait coupée en deux sur tous les téléphones.
///
/// Les deux boîtes font maintenant exactement la hauteur d'une ligne à la
/// PLUS GRANDE taille que la ligne peut prendre. Le texte y tient donc
/// toujours : il n'est ni tranché, ni rapetissé pour y entrer.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'bulle_cri.dart';
import 'bulle_devise.dart';
import 'fuga_background.dart';
import 'etoile_favori.dart';
import 'profile_photo.dart';
import 'texte_remplissant.dart';

/// Côté de la photo : LE TIERS DE LA LARGEUR DE L'ÉCRAN, comme au dessin.
///
/// `S(240)` vaut 240/720 de la largeur, soit exactement un tiers, sur
/// n'importe quel écran.
double hauteurPhotoProfil() => S(240);

/// Hauteur de la ligne du pseudo : une ligne à sa plus grande taille.
double _hauteurNom() => SF(34) * kInterligne;

/// Hauteur de la ligne des mélos, à sa plus grande taille.
double _hauteurMelos() => SF(14) * kInterligne;

/// Écart entre le pseudo et les mélos, et entre les mélos et la bulle.
double _ecartNom() => S(4);
double _ecartMelos() => S(6);

/// Hauteur sous laquelle la bulle ne descend pas : ce qui reste de la photo
/// une fois le pseudo et les mélos posés. C'est elle qui fait que la bulle
/// s'arrête pile au bas de la photo quand la devise est courte.
double _planchersBulle() {
  final reste =
      hauteurPhotoProfil() -
      _hauteurNom() -
      _ecartNom() -
      _hauteurMelos() -
      _ecartMelos();
  return reste > 0 ? reste : 0;
}

/// Nombre de lignes au-delà duquel la devise est abrégée plutôt que
/// rapetissée.
///
/// Trois sont dues, « et plus c'est encore mieux » — la devise prend donc la
/// ligne de plus plutôt que la taille en moins, jusqu'ici.
///
/// Huit, et pas davantage, parce que la bulle prendrait alors plus de place
/// que la photo et le pseudo réunis. Une devise plus longue que ça rapetisse
/// d'abord, puis est abrégée d'un « … » : c'est le seul endroit où du texte
/// peut se perdre, et il faut environ trois cent soixante-dix caractères
/// pour y arriver, sur les cinq cents que le serveur accepte.
const int kLignesDevise = 8;

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
    padding: EdgeInsets.symmetric(horizontal: S(16)),
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
              SizedBox(height: _hauteurNom(), child: _nom()),
              SizedBox(height: _ecartNom()),
              SizedBox(height: _hauteurMelos(), child: _melos()),
              SizedBox(height: _ecartMelos()),
              // « La bulle devise occupe la place qu'il reste » — au moins,
              // et davantage si la devise la demande.
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: _planchersBulle()),
                child: _devise(),
              ),
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
      maxLignes: kLignesDevise,
    );
    final bulle = BulleDevise(
      couleur: palette.fonce,
      // « fais ta prière ! » se crie, comme dans la messagerie : la bulle se
      // hérisse. Une devise vide, elle, ne crie jamais — c'est le texte de
      // remplacement qui s'affiche, et il n'est pas de nous.
      crie: !vide && estUnCri(texte),
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
