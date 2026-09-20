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

  /// En relecture seulement.
  final VoidCallback? onAnalyse;

  /// En analyse et en relecture : reprendre la position contre Deep Grey.
  final VoidCallback? onDeepGrey;

  /// Contre Deep Grey : `true` en mode profond.
  final bool? aiDeepMode;
  final VoidCallback? onToggleAiMode;

  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    color: color,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Row(
      children: [
        _round('< >', onFlip, fontSize: 18, tooltip: T('Retourner le plateau')),
        if (onMenu != null) ...[
          const SizedBox(width: 6),
          _wide(
            T('Retour au menu'),
            onMenu!,
            width: 120,
            color: palette.clair,
            fontSize: 11,
          ),
        ],
        const Spacer(),
        if (onChat != null) ...[
          _wide(T('Chat'), onChat!, width: 88, color: kBarButtonDark),
          const SizedBox(width: 6),
        ],
        if (onToggleAiMode != null) ...[
          _wide(
            aiDeepMode == true ? T('Profond') : T('Rapide'),
            onToggleAiMode!,
            width: 108,
            color: kBarButtonDark,
            fontSize: 15,
            tooltip: T('Deep Grey'),
          ),
          const SizedBox(width: 6),
        ],
        if (onAnalyse != null) ...[
          _wide(T('Analyser'), onAnalyse!, width: 100, color: palette.clair),
          const SizedBox(width: 6),
        ],
        if (onDeepGrey != null) ...[
          _wide(
            'Deep Grey',
            onDeepGrey!,
            width: 110,
            color: kBarButtonDeepGrey,
          ),
          const SizedBox(width: 6),
        ],
        _round(
          pauseLabel,
          onPause,
          fontSize: 22,
          tooltip: pauseLabel == '| |' ? T('Pause') : T('Retour'),
        ),
      ],
    ),
  );

  /// Touche ronde, carrée : la hauteur du bandeau fait sa largeur.
  Widget _round(
    String label,
    VoidCallback onPressed, {
    required double fontSize,
    required String tooltip,
  }) => _button(
    label,
    onPressed,
    width: 32,
    color: kBarButtonDark,
    radius: 20,
    fontSize: fontSize,
    tooltip: tooltip,
  );

  Widget _wide(
    String label,
    VoidCallback onPressed, {
    required double width,
    required Color color,
    double fontSize = 14,
    String? tooltip,
  }) => _button(
    label,
    onPressed,
    width: width,
    color: color,
    radius: 14,
    fontSize: fontSize,
    tooltip: tooltip,
  );

  Widget _button(
    String label,
    VoidCallback onPressed, {
    required double width,
    required Color color,
    required double radius,
    required double fontSize,
    String? tooltip,
  }) {
    final button = SizedBox(
      width: width,
      height: double.infinity,
      child: Material(
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
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}
