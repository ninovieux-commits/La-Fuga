/// Le catalogue des images du jeu, rangé par thème — et sa grille.
///
/// Deux écrans montrent exactement les mêmes images : la galerie des photos
/// de profil, et le choix d'une image à envoyer dans un message. Elles
/// étaient rangées de deux façons différentes — tous les logos d'abord, puis
/// toutes les pièces, contre un bloc par thème. Nino : « les images doivent
/// être rangées comme sur l'image précédente ». Elles ne sont donc plus
/// rangées qu'ICI, et les deux écrans montrent la même chose.
///
/// Un thème donne son logo, ses cinq pièces blanches et ses cinq noires.
///
/// ## La colonne de gauche est celle des images qui ne sont pas des pièces
///
/// Nino : « les logos doivent être rangés avec les pièces (à gauche de la
/// rangée de pièces blanches à chaque fois). L'image de profil de deepgrey
/// peut logiquement aller à gauche de la rangée de pièces noires de
/// deepgrey, comme ça on est logiques. »
///
/// Chaque rangée commence donc par une case de plus que les cinq pièces :
/// le logo sur la rangée blanche, le portrait de Deep Grey sur la rangée
/// noire de son thème, et rien ailleurs. Les pièces restent ainsi alignées
/// en colonnes d'une rangée à l'autre et d'un thème à l'autre.
library;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'profile_photo.dart';

/// Le thème dont Deep Grey porte les couleurs, et le nom.
const String kThemeDeepGrey = 'deepgrey';

/// Un thème et toutes ses images, dans l'ordre où on les montre.
typedef SectionPhotos = ({
  String theme,
  String label,

  /// En tête de la rangée blanche.
  String logo,
  List<String> blanches,

  /// En tête de la rangée noire : le portrait de Deep Grey dans sa section,
  /// et rien ailleurs.
  String? enTeteNoire,
  List<String> noires,
});

/// Le catalogue, section par section.
///
/// [dabord] met un thème en tête — celui qu'on porte, qu'on cherchera le plus
/// souvent. Les autres gardent l'ordre de `kThemeOrder`.
List<SectionPhotos> cataloguePhotos({String? dabord}) {
  final ordre = dabord == null || !kThemes.containsKey(dabord)
      ? kThemeOrder
      : [dabord, ...kThemeOrder.where((t) => t != dabord)];
  return [
    for (final theme in ordre)
      (
        theme: theme,
        label: kThemeLabels[theme] ?? theme,
        logo: 'logo|$theme',
        blanches: [for (final p in kProfilePieces) '$theme|${p.wire}'],
        noires: [
          for (final p in kProfilePieces) '$theme|${p.wire}|${Camp.noir.wire}',
        ],
        enTeteNoire: theme == kThemeDeepGrey ? kDeepGreyPhoto : null,
      ),
  ];
}

/// Toutes les photos du catalogue, à plat et dans le même ordre.
List<String> photosDuCatalogue({String? dabord}) => [
  for (final s in cataloguePhotos(dabord: dabord)) ...[
    s.logo,
    ...s.blanches,
    if (s.enTeteNoire != null) s.enTeteNoire!,
    ...s.noires,
  ],
];

/// Ce qu'une photo dit d'elle au doigt qui s'attarde.
String infobulleDePhoto(String photo) {
  if (photo == kDeepGreyPhoto) return 'Deep Grey';
  if (isLogoPhoto(photo)) {
    final theme = logoThemeOf(photo);
    return kThemeLabels[theme] ?? theme;
  }
  return parsePhoto(photo).piece.wire;
}

/// La grille des images, rangée par thème : à chaque appui, [onChoisie].
///
/// Elle ne défile pas d'elle-même — c'est à celui qui la pose de l'enfermer
/// dans ce qu'il veut, une page ou un panneau de quelques centimètres.
class GrilleDesPhotos extends StatelessWidget {
  const GrilleDesPhotos({
    super.key,
    required this.cote,
    required this.onChoisie,
    this.themeDabord,
    this.couleurDuNom = const Color.fromRGBO(190, 190, 190, 1),
  });

  /// Côté d'une image, en pixels de référence déjà mis à l'échelle.
  final double cote;

  final void Function(String photo) onChoisie;

  /// Le thème à mettre en tête, ou `null` pour l'ordre du catalogue.
  final String? themeDabord;

  final Color couleurDuNom;

  Widget _image(String photo, {double? taille}) => Padding(
    padding: EdgeInsets.all(S(3)),
    child: Tooltip(
      message: infobulleDePhoto(photo),
      child: InkWell(
        onTap: () => onChoisie(photo),
        child: ProfilePhoto(photo: photo, size: taille ?? cote),
      ),
    ),
  );

  /// Une rangée : la case de tête, puis les cinq pièces.
  ///
  /// La case de tête garde sa place même vide, sans quoi les pièces d'une
  /// rangée à l'autre ne tomberaient plus dans les mêmes colonnes.
  Widget _rangee(String? enTete, List<String> photos) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      if (enTete == null)
        SizedBox(width: cote + 2 * S(3), height: cote + 2 * S(3))
      else
        _image(enTete),
      for (final p in photos) _image(p),
    ],
  );

  /// Le nom du thème, seul au-dessus de ses deux rangées.
  Widget _entete(SectionPhotos s) => Text(
    s.label,
    style: TextStyle(fontSize: SF(12), color: couleurDuNom),
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final s in cataloguePhotos(dabord: themeDabord)) ...[
        _entete(s),
        _rangee(s.logo, s.blanches),
        _rangee(s.enTeteNoire, s.noires),
      ],
    ],
  );
}
