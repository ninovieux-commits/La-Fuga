/// Écran du tutoriel — portage de `TutoScreen` (main.py).
///
/// Plateau en haut, encadré de texte en bas, barre Précédent / Suivant avec la
/// progression. Sur une étape interactive, « Suivant » reste bloqué tant que le
/// coup demandé n'est pas joué : le tuto se fait, il ne se survole pas.
library;

import 'package:flutter/material.dart';

import '../../game/tuto.dart';
import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../widgets/fuga_background.dart';
import '../widgets/fuga_button.dart';
import '../widgets/game_board_view.dart';
import '../widgets/tuto_overlay.dart';
import 'settings_screen.dart';

class TutoScreen extends StatefulWidget {
  const TutoScreen({super.key, this.controller});

  /// Injectable pour les tests.
  final TutoController? controller;

  @override
  State<TutoScreen> createState() => _TutoScreenState();
}

class _TutoScreenState extends State<TutoScreen> {
  late final TutoController _tuto = widget.controller ?? TutoController();

  @override
  Widget build(BuildContext context) {
    final axes = Settings.instance.themeAxes;
    final palette = paletteOf(axes.general);
    final banner = _tuto.step.banner;

    return FugaScaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Kivy : pause à gauche, progression à droite. Pas de titre.
            Expanded(flex: 6, child: _topBar()),
            Expanded(
              flex: 66,
              child: banner == null ? _board(palette, axes) : _banner(banner),
            ),
            Expanded(flex: 17, child: _textBox()),
            Expanded(flex: 11, child: _nav(palette)),
          ],
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 95,
          child: FugaButton(
            text: T('Pause'),
            fontSize: 13,
            height: double.infinity,
            onPressed: _openPause,
          ),
        ),
        const Spacer(),
        Text(
          '${_tuto.index + 1} / ${_tuto.stepCount}',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Color.fromRGBO(38, 38, 38, 1),
          ),
        ),
      ],
    ),
  );

  /// La pause du tuto : réglages, ou fermer — `_open_pause`.
  Future<void> _openPause() async {
    final palette = paletteOf(Settings.instance.themeAxes.general);
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kFugaGrey,
        title: Text(T('Pause'), style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FugaButton(
              text: T('Réglages'),
              fontSize: 16,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(fromMenu: false),
                ),
              ),
            ),
            const SizedBox(height: 10),
            FugaButton(
              text: T('Fermer le tuto'),
              color: palette.clair,
              fontSize: 16,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop(false);
  }

  Widget _board(ThemePalette palette, ThemeAxes axes) => Stack(
    fit: StackFit.expand,
    children: [
      GameBoardView(
        board: _tuto.board,
        palette: palette,
        flipped: true,
        onTapCell: (cell) {
          if (_tuto.tap(cell)) setState(() {});
        },
        selected: _tuto.selected,
        groupSelection: _tuto.groupSelected,
        pieceTheme: axes.pieces,
        boardTheme: axes.board,
      ),
      // Les annotations se posent par-dessus, sans toucher au plateau du jeu :
      // c'est bien le VRAI plateau qu'on montre.
      IgnorePointer(
        child: CustomPaint(
          painter: TutoOverlayPainter(
            annotations: _tuto.annotations,
            fugued: _tuto.fugued,
            mockUi: _tuto.step.mockUi,
            palette: palette,
          ),
        ),
      ),
    ],
  );

  /// Grand texte de transition, à la place du plateau. Le bleu est fixe chez
  /// Kivy : `(0.13, 0.45, 0.85)`.
  Widget _banner(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        T(text),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color.fromRGBO(33, 115, 217, 1),
          fontSize: 30,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );

  Widget _textBox() => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7E6),
      border: Border.all(color: const Color(0xFFD9C7A6), width: 1.4),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      T(_tuto.text),
      textAlign: TextAlign.center,
      style: const TextStyle(color: Color(0xFF1F1F1F), fontSize: 15),
    ),
  );

  /// « < Précédent » en gris, « Suivant > » en foncé — les couleurs de Kivy.
  /// Une touche indisponible s'estompe au lieu de disparaître.
  Widget _nav(ThemePalette palette) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Opacity(
            opacity: _tuto.atFirst ? 0.35 : 1,
            child: FugaButton(
              text: T('< Précédent'),
              fontSize: 15,
              height: double.infinity,
              onPressed: _tuto.atFirst ? null : () => setState(_tuto.previous),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Opacity(
            opacity: _tuto.canGoNext ? 1 : 0.35,
            child: FugaButton(
              text: _tuto.atLast ? T('Le menu >') : T('Suivant >'),
              color: palette.fonce,
              fontSize: 15,
              height: double.infinity,
              onPressed: !_tuto.canGoNext
                  ? null
                  : _tuto.atLast
                  // La dernière touche rend la main au menu en demandant sa
                  // visite guidée, comme en Kivy.
                  ? () => Navigator.of(context).pop(true)
                  : () => setState(_tuto.next),
            ),
          ),
        ),
      ],
    ),
  );
}
