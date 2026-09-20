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
import '../widgets/game_board_view.dart';
import '../widgets/tuto_overlay.dart';

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

    return Scaffold(
      backgroundColor: paletteOf(axes.menu).menu,
      appBar: AppBar(
        backgroundColor: palette.clair,
        foregroundColor: Colors.white,
        title: Text(T(_tuto.step.title)),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '${_tuto.index + 1} / ${_tuto.stepCount}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: banner == null
                  ? _board(palette, axes)
                  : _banner(banner, palette),
            ),
            _textBox(),
            _nav(palette),
          ],
        ),
      ),
    );
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

  /// Grand texte de transition, à la place du plateau.
  Widget _banner(String text, ThemePalette palette) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        T(text),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: palette.clair,
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

  Widget _nav(ThemePalette palette) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _tuto.atFirst ? null : () => setState(_tuto.previous),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white24),
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(T('< Précédent')),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: FilledButton(
            onPressed: !_tuto.canGoNext
                ? null
                : _tuto.atLast
                // La dernière touche rend la main au menu en demandant sa
                // visite guidée, comme en Kivy.
                ? () => Navigator.of(context).pop(true)
                : () => setState(_tuto.next),
            style: FilledButton.styleFrom(
              backgroundColor: palette.clair,
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(_tuto.atLast ? T('Le menu >') : T('Suivant >')),
          ),
        ),
      ],
    ),
  );
}
