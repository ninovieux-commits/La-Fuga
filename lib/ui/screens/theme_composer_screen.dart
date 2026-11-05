/// Composeur de thèmes — portage de `ThemeComposerScreen` (main.py).
///
/// Cinq axes indépendants : on peut prendre les couleurs d'un thème, les
/// pièces d'un autre et le plateau d'un troisième. Chaque axe a son défilement
/// horizontal d'aperçus.
library;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../i18n/translations.dart';
import '../../net/online_service.dart';
import '../../state/settings.dart';
import '../../theme/theme_assets.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import '../suit_les_reglages.dart';
import '../widgets/fuga_background.dart';
import '../widgets/fuga_button.dart';
import '../widgets/fuga_header.dart';
import '../widgets/picto_touche.dart';
import '../widgets/profile_photo.dart';
import '../widgets/theme_preview.dart';

/// Les cinq axes, dans l'ordre de Kivy.
const List<(String, String)> kThemeAxisLabels = [
  ('general', 'Général'),
  ('pieces', 'Pièces'),
  ('logo', 'Logo'),
  ('menu', 'Fond du menu'),
  ('board', 'Plateau'),
];

class ThemeComposerScreen extends StatefulWidget {
  const ThemeComposerScreen({super.key});

  @override
  State<ThemeComposerScreen> createState() => _ThemeComposerScreenState();
}

class _ThemeComposerScreenState extends State<ThemeComposerScreen>
    with SuitLesReglages {
  late ThemeAxes _axes = Settings.instance.themeAxes;

  /// Un contrôleur par axe, pour AMENER LE CHOISI SOUS LES YEUX.
  ///
  /// Les rangées partaient toujours de la gauche : un thème choisi loin dans
  /// la liste — Deep Grey est le dix-septième — restait hors de l'écran, et
  /// le composeur s'ouvrait sans qu'on voie ce qu'on avait déjà.
  final Map<String, ScrollController> _defilements = {
    for (final (axis, _) in kThemeAxisLabels) axis: ScrollController(),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _montreLesChoisis());
  }

  @override
  void dispose() {
    for (final c in _defilements.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Largeur d'une vignette, marges comprises.
  static double get _pasDuDefilement => S(78) + 2 * S(4);

  /// Place chaque rangée sur son thème choisi, sans animation : à
  /// l'ouverture, il n'y a rien à suivre des yeux.
  void _montreLesChoisis() {
    for (final (axis, _) in kThemeAxisLabels) {
      final c = _defilements[axis];
      if (c == null || !c.hasClients) continue;
      final index = kThemeOrder.indexOf(_themeOf(axis));
      if (index < 0) continue;
      // Un peu AVANT lui : on voit qu'il y a de quoi remonter la liste.
      final cible = (index - 1) * _pasDuDefilement;
      c.jumpTo(cible.clamp(0.0, c.position.maxScrollExtent));
    }
  }

  String _themeOf(String axis) => switch (axis) {
    'pieces' => _axes.pieces,
    'logo' => _axes.logo,
    'menu' => _axes.menu,
    'board' => _axes.board,
    _ => _axes.general,
  };

  void _pick(String axis, String theme) => setState(() {
    _axes = ThemeAxes(
      general: axis == 'general' ? theme : _axes.general,
      pieces: axis == 'pieces' ? theme : _axes.pieces,
      logo: axis == 'logo' ? theme : _axes.logo,
      menu: axis == 'menu' ? theme : _axes.menu,
      board: axis == 'board' ? theme : _axes.board,
    );
  });

  /// Applique la composition et la retient, ici et sur le compte.
  Future<void> _apply() async {
    final value = _axes.toString();
    await Settings.instance.setTheme(value);
    final online = OnlineService.instance;
    if (online.isLoggedIn) await online.client.setTheme(value);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(_axes.general);

    // LE FOND SUIT CE QU'ON COMPOSE, pas ce qui est enregistré. Sans cela
    // l'axe « Fond du menu » ne se voyait qu'après avoir appliqué.
    return FugaScaffold(
      theme: _axes.menu,
      body: SafeArea(
        child: Column(
          children: [
            FugaHeader(
              back: T('< Retour'),
              title: T('Composer le thème'),
              titleSize: 17,
              titleColor: Colors.white,
              bold: true,
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.all(S(8)),
                children: [
                  for (final (axis, label) in kThemeAxisLabels)
                    _section(axis, label),
                  _apercuVivant(),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(S(10), S(6), S(10), S(10)),
              child: FugaButton(
                text: T('Appliquer'),
                color: palette.clair,
                fontSize: SF(16),
                onPressed: _apply,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String axis, String label) {
    final selected = _themeOf(axis);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(S(16), S(12), S(16), S(4)),
          child: Text(
            T(label),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: S(104),
          child: ListView(
            controller: _defilements[axis],
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: S(12)),
            children: [
              for (final theme in kThemeOrder)
                _cell(axis, theme, chosen: theme == selected),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cell(String axis, String theme, {required bool chosen}) {
    return GestureDetector(
      onTap: () => _pick(axis, theme),
      child: Container(
        width: S(78),
        margin: EdgeInsets.symmetric(horizontal: S(4), vertical: S(6)),
        padding: EdgeInsets.all(S(4)),
        decoration: BoxDecoration(
          color: chosen
              ? paletteOf(_axes.general).clair
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(S(10)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: S(54), child: _preview(axis, theme)),
            SizedBox(height: S(4)),
            // CERNÉ, comme toute écriture de l'application. Nu, il
            // disparaissait sur une vignette choisie dont la couleur 1 est
            // le blanc — c'est le cas de Deep Grey.
            //
            // ET ENTIER : « Arc-en-ciel » et « Médiéval » sortaient coupés.
            // Un nom rapetissé se lit encore ; un nom tranché, non.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: MotTouche(
                texte: T(kThemeLabels[theme] ?? theme),
                couleur: Colors.white,
                style: TextStyle(fontSize: SF(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// CE QUE ÇA DONNE, tout de suite et pour de vrai.
  ///
  /// Nino : « le composeur de thème a des défauts. Par exemple, le plateau
  /// ne se met pas bien à jour. » Le composeur ne montrait que cinq rangées
  /// de vignettes et une touche « Appliquer » : pour voir sa composition, il
  /// fallait l'appliquer, sortir, et aller ouvrir une partie. La moitié
  /// basse de l'écran était vide.
  ///
  /// Les quatre pièces sur leur damier répondent à trois axes à la fois — le
  /// général pour les couleurs 1 et 2, les pièces pour leur dessin, le
  /// plateau pour le damier — et le logo au sien. Le fond de la page, lui,
  /// répond déjà à l'axe « Fond du menu ».
  Widget _apercuVivant() => Padding(
    padding: EdgeInsets.fromLTRB(S(16), S(16), S(16), S(4)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MotTouche(
          texte: T('Aperçu'),
          couleur: Colors.white,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: SF(13)),
        ),
        SizedBox(height: S(8)),
        Row(
          children: [
            ProfilePhoto(photo: 'logo|${_axes.logo}', size: S(72)),
            SizedBox(width: S(10)),
            // QUATRE CASES CARRÉES, ET RIEN AUTOUR. L'aperçu dessine ses
            // pièces dans des cases hautes comme la boîte ; étiré sur toute
            // la largeur, le damier ne remplissait que le milieu et l'image
            // du plateau débordait des deux côtés.
            Expanded(
              child: SizedBox(
                height: S(72),
                child: ThemePreview(
                  theme: _axes.pieces,
                  themeDuPlateau: _axes.board,
                  themeGeneral: _axes.general,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  /// Aperçu d'un axe : ce que l'axe change, et rien d'autre.
  Widget _preview(String axis, String theme) {
    switch (axis) {
      case 'pieces':
        return ProfilePhoto(
          photo: '$theme|${PieceType.heritier.wire}',
          size: S(54),
        );
      case 'logo':
        return ProfilePhoto(photo: 'logo|$theme', size: S(54));
      case 'menu':
      case 'board':
        final images = imagesFor(theme);
        final asset = axis == 'menu' ? images?.background : images?.board;
        final palette = paletteOf(theme);
        return ClipRRect(
          borderRadius: BorderRadius.circular(S(8)),
          child: asset == null
              // Sans image, l'axe ne change qu'une couleur : on la montre.
              ? Container(color: axis == 'menu' ? palette.menu : palette.board)
              // SANS LARGEUR IMPOSÉE : la vignette d'un thème à image
              // sortait plus étroite que celle d'un thème à couleur, et la
              // rangée paraissait bancale.
              : SizedBox.expand(child: Image.asset(asset, fit: BoxFit.cover)),
        );
      default:
        return _colorPreview(paletteOf(theme));
    }
  }

  /// Aperçu « général » : le foncé du thème, avec son clair au centre.
  Widget _colorPreview(ThemePalette palette) => Container(
    decoration: BoxDecoration(
      color: palette.fonce,
      borderRadius: BorderRadius.circular(S(8)),
    ),
    child: Center(
      child: Container(
        width: S(24),
        height: S(24),
        decoration: BoxDecoration(
          color: palette.clair,
          borderRadius: BorderRadius.circular(S(5)),
        ),
      ),
    ),
  );
}
