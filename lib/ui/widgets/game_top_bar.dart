/// Bandeau du haut d'une partie — portage de `top_bar` (main.py).
///
/// Toujours les mêmes touches, dans le même ordre : retourner le plateau et
/// revenir au menu à gauche, puis, poussées à droite, celles que le mode en
/// cours autorise, et la pause tout au bout.
///
/// Comme en Kivy, « Retour au menu » reste caché tant que la partie n'est pas
/// finie : on quitte une partie en cours par la pause, pas par mégarde.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../scale.dart';

/// Fond des touches rondes du bandeau — le `(0.15, 0.15, 0.15)` de Kivy.
const Color kBarButtonDark = Color.fromRGBO(38, 38, 38, 1);

/// Fond de la touche « Deep Grey » — `(0.30, 0.30, 0.34)`.
const Color kBarButtonDeepGrey = Color.fromRGBO(77, 77, 87, 1);

class GameTopBar extends StatelessWidget {
  const GameTopBar({
    super.key,
    required this.palette,
    required this.color,
    required this.onFlip,
    required this.onPause,
    this.pauseLabel = '| |',
    this.onMenu,
    this.onChat,
    this.unreadChat = 0,
    this.onAnalyse,
    this.onDeepGrey,
    this.aiDeepMode,
    this.onToggleAiMode,
  });

  final ThemePalette palette;

  /// Couleur du camp affiché EN HAUT, vive quand il a le trait : chez Kivy,
  /// ce bandeau et celui des coups sont les deux témoins du tour.
  final Color color;

  final VoidCallback onFlip;
  final VoidCallback onPause;

  /// En relecture et en analyse, Kivy remplace la pause par `<<`, qui ramène
  /// d'où l'on vient : il n'y a pas de partie à suspendre.
  final String pauseLabel;

  /// Non nul quand la partie est finie : la touche apparaît alors.
  final VoidCallback? onMenu;

  /// En ligne seulement.
  final VoidCallback? onChat;

  /// Messages non lus : Kivy écrit « Chat (2) ».
  final int unreadChat;

  /// En relecture seulement.
  final VoidCallback? onAnalyse;

  /// En analyse et en relecture : reprendre la position contre Deep Grey.
  final VoidCallback? onDeepGrey;

  /// Contre Deep Grey : `true` en mode profond.
  final bool? aiDeepMode;
  final VoidCallback? onToggleAiMode;

  @override
  Widget build(BuildContext context) => Container(
    // La hauteur vient de la pile (7 % de l'écran), comme le `size_hint` de
    // Kivy : on ne la fixe pas ici.
    color: color,
    // Marge verticale réduite : les touches rondes suivent la hauteur du
    // bandeau, moins de marge veut dire des touches plus grosses.
    padding: EdgeInsets.symmetric(horizontal: S(12), vertical: S(2)),
    child: Row(
      children: [
        _round(
          '< >',
          onFlip,
          fontSize: SF(21),
          tooltip: T('Retourner le plateau'),
        ),
        if (onMenu != null) ...[
          SizedBox(width: S(6)),
          _wide(
            T('Retour au menu'),
            onMenu!,
            width: S(178),
            color: palette.clair,
            fontSize: SF(13),
          ),
        ],
        const Spacer(),
        if (onChat != null) ...[
          _wide(
            unreadChat > 0
                ? T('Chat (%d)').replaceFirst('%d', '$unreadChat')
                : T('Chat'),
            onChat!,
            width: S(104),
            color: kBarButtonDark,
          ),
          SizedBox(width: S(6)),
        ],
        if (onToggleAiMode != null) ...[
          _wide(
            aiDeepMode == true ? T('Profond') : T('Rapide'),
            onToggleAiMode!,
            width: S(128),
            color: kBarButtonDark,
            fontSize: SF(17),
            tooltip: T('Deep Grey'),
          ),
          SizedBox(width: S(6)),
        ],
        if (onAnalyse != null) ...[
          _wide(T('Analyser'), onAnalyse!, width: S(118), color: palette.clair),
          SizedBox(width: S(6)),
        ],
        if (onDeepGrey != null) ...[
          _wide(
            'Deep Grey',
            onDeepGrey!,
            width: S(130),
            color: kBarButtonDeepGrey,
          ),
          SizedBox(width: S(6)),
        ],
        if (pauseLabel == '| |')
          Tooltip(
            message: T('Pause'),
            child: AspectRatio(
              aspectRatio: 1,
              child: Material(
                color: kBarButtonDark,
                borderRadius: BorderRadius.circular(S(20)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(S(20)),
                  onTap: onPause,
                  // Deux barres dessinées plutôt que le texte « | | » : à
                  // cette taille, le glyphe débordait de la touche et
                  // tombait de travers.
                  child: const Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.30,
                      heightFactor: 0.40,
                      child: CustomPaint(painter: _PausePainter()),
                    ),
                  ),
                ),
              ),
            ),
          )
        else
          _round(pauseLabel, onPause, fontSize: SF(25), tooltip: T('Retour')),
      ],
    ),
  );

  /// Touche ronde, carrée : la hauteur du bandeau fait sa largeur —
  /// `bind(height=lambda b, h: setattr(b, "width", h))`.
  Widget _round(
    String label,
    VoidCallback onPressed, {
    required double fontSize,
    required String tooltip,
  }) => _button(
    label,
    onPressed,
    width: null,
    color: kBarButtonDark,
    radius: S(20),
    fontSize: fontSize,
    tooltip: tooltip,
  );

  Widget _wide(
    String label,
    VoidCallback onPressed, {
    required double width,
    required Color color,
    double? fontSize,
    String? tooltip,
  }) => _button(
    label,
    onPressed,
    width: width,
    color: color,
    radius: S(14),
    fontSize: fontSize ?? SF(16),
    tooltip: tooltip,
  );

  /// [width] nul : la touche est carrée et suit la hauteur du bandeau.
  Widget _button(
    String label,
    VoidCallback onPressed, {
    required double? width,
    required Color color,
    required double radius,
    required double fontSize,
    String? tooltip,
  }) {
    final Widget inner = Material(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onPressed,
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
    final button = width == null
        ? AspectRatio(aspectRatio: 1, child: inner)
        : SizedBox(width: width, height: double.infinity, child: inner);
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// Les deux barres de la pause, centrées à coup sûr.
final class _PausePainter extends CustomPainter {
  const _PausePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width * 0.32;
    final paint = Paint()..color = Colors.white;
    final radius = Radius.circular(barWidth / 2);
    for (final left in [0.0, size.width - barWidth]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, 0, barWidth, size.height),
          radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PausePainter old) => false;
}
