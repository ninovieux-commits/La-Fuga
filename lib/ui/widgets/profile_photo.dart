/// Photo de profil — portage de `parse_photo`, `PiecePhoto` et
/// `draw_profile_piece` (main.py).
///
/// Une photo est un mot : `thème|Type`, `thème|Type|Noir`, `logo|thème`, ou
/// `deepgrey` pour l'image dédiée de l'IA. Rien de tout cela n'est un fichier
/// envoyé au serveur : on n'échange qu'un identifiant, et chaque appareil
/// dessine la pièce avec ses propres images.
library;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../theme/themes.dart';
import 'logo_painter.dart';
import 'piece_painter.dart';
import 'theme_image_cache.dart';

/// Photo par défaut : le logo du thème original.
const String kDefaultPhoto = 'logo|original';

/// Photo de Deep Grey, qui a son image à elle.
const String kDeepGreyPhoto = 'deepgrey';

/// Les pièces qu'on peut prendre comme photo.
const List<PieceType> kProfilePieces = [
  PieceType.heritier,
  PieceType.nurse,
  PieceType.garde,
  PieceType.soldat,
  PieceType.chevalier,
];

/// Quelques thèmes ont un logo au nom différent du leur.
const Map<String, String> _logoAliases = {
  'medieval': 'bataille',
  'fleur': 'fleurs',
  'insectes': 'foret',
};

/// Chemin du logo d'un thème.
String logoAssetOf(String theme) =>
    'assets/logos/logo_${_logoAliases[theme] ?? theme}.webp';

/// Une photo lue : un thème, une pièce, un camp.
typedef PhotoParts = ({String theme, PieceType piece, Camp camp});

/// Lit une photo. Tout ce qui n'est pas reconnu retombe sur l'Héritier blanc
/// du thème original — jamais d'erreur, jamais de trou à l'écran.
PhotoParts parsePhoto(String? photo) {
  var theme = kDefaultTheme;
  var piece = PieceType.heritier;
  var camp = Camp.blanc;

  final parts = (photo ?? '').split('|');
  if (parts.length >= 2) {
    if (kThemes.containsKey(parts[0])) theme = parts[0];
    for (final p in kProfilePieces) {
      if (p.wire == parts[1]) piece = p;
    }
    if (parts.length >= 3 && parts[2] == 'Noir') camp = Camp.noir;
  }
  return (theme: theme, piece: piece, camp: camp);
}

/// Vrai si la photo est un logo de thème (`logo|<thème>`).
bool isLogoPhoto(String? photo) => (photo ?? '').startsWith('logo|');

/// Le thème d'une photo de logo.
String logoThemeOf(String photo) {
  final name = photo.split('|').elementAtOrNull(1) ?? kDefaultTheme;
  return kThemes.containsKey(name) ? name : kDefaultTheme;
}

/// Affiche une photo de profil, carrée.
///
/// Portage de `PiecePhoto._redraw`. Les trois cas de Kivy, dans le même ordre
/// et avec le même décor :
///  - `deepgrey` : l'image dédiée de l'IA, plein cadre ;
///  - `logo|<thème>` : un carré arrondi à la couleur **menu** du thème, le logo
///    par-dessus ;
///  - `<thème>|<Type>` : un carré arrondi à la couleur **plateau** du thème, la
///    pièce par-dessus.
///
/// Le carré arrondi n'est pas un ornement : sans lui la pièce flotte sur le
/// fond de la page, et c'est exactement ce qui faisait « mal s'afficher ».
class ProfilePhoto extends StatelessWidget {
  const ProfilePhoto({super.key, required this.photo, this.size = 64});

  final String? photo;
  final double size;

  /// Arrondi du carré : `sz * 0.12`, comme le `radius=[sz * 0.12]` de Kivy.
  static const double _radiusFraction = 0.12;

  @override
  Widget build(BuildContext context) {
    final value = (photo == null || photo!.isEmpty) ? kDefaultPhoto : photo!;

    if (value == kDeepGreyPhoto) {
      return SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          'assets/images/deepgrey.webp',
          width: size,
          height: size,
          fit: BoxFit.contain,
          // Image absente : le carré gris de repli de Kivy, pas un logo.
          errorBuilder: (_, __, ___) => _plate(const Color(0xFF4D4D57)),
        ),
      );
    }

    if (isLogoPhoto(value)) {
      final theme = logoThemeOf(value);
      final palette = paletteOf(theme);
      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _plate(palette.menu),
            Image.asset(
              logoAssetOf(theme),
              fit: BoxFit.contain,
              // Logo absent : la rosace dessinée tient sa place.
              errorBuilder: (_, __, ___) =>
                  CustomPaint(painter: _LogoPhotoPainter(palette)),
            ),
          ],
        ),
      );
    }

    final parts = parsePhoto(value);
    final palette = paletteOf(parts.theme);
    // Les thèmes à images décodent leurs fichiers une fois ; tant que ce n'est
    // pas fait, la pièce se dessine géométriquement plutôt que de clignoter.
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _plate(palette.board),
          ThemeImagesBuilder(
            theme: parts.theme,
            builder: (context, images) => CustomPaint(
              painter: _PiecePhotoPainter(
                piece: Piece(parts.piece, parts.camp),
                palette: palette,
                images: images,
                // Sans le thème, les rendus spéciaux — le corps gris de
                // deepgrey, les accents de l'arc-en-ciel — étaient perdus :
                // la photo sortait aux couleurs d'un thème quelconque.
                theme: parts.theme,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Le carré arrondi du fond.
  Widget _plate(Color color) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(size * _radiusFraction),
    ),
  );
}

class _PiecePhotoPainter extends CustomPainter {
  const _PiecePhotoPainter({
    required this.piece,
    required this.palette,
    this.images,
    this.theme,
  });

  final Piece piece;
  final ThemePalette palette;
  final LoadedThemeImages? images;

  /// Thème de la photo — `deepgrey` et `arcenciel` ont leur propre rendu.
  final String? theme;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    paintPiece(
      canvas,
      Rect.fromLTWH(
        (size.width - side) / 2,
        (size.height - side) / 2,
        side,
        side,
      ),
      piece,
      palette,
      images: images,
      theme: theme,
    );
  }

  @override
  bool shouldRepaint(_PiecePhotoPainter old) =>
      old.piece != piece ||
      old.palette != palette ||
      old.images != images ||
      old.theme != theme;
}

class _LogoPhotoPainter extends CustomPainter {
  const _LogoPhotoPainter(this.palette);

  final ThemePalette palette;

  @override
  void paint(Canvas canvas, Size size) => paintLogo(
    canvas,
    size.width / 2,
    size.height / 2,
    size.shortestSide / 2,
    clair: palette.clair,
    fonce: palette.fonce,
  );

  @override
  bool shouldRepaint(_LogoPhotoPainter old) => old.palette != palette;
}
