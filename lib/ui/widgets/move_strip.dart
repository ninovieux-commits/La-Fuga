/// Bandeau des coups — portage de `bot_bar` et `_do_update_history_ui`
/// (main.py).
///
/// Une flèche, l'historique qui défile, une flèche. On peut revenir sur
/// n'importe quelle position sans quitter la partie : le coup regardé s'écrit
/// en noir gras, les autres en blanc.
///
/// Le fond prend la couleur du camp du BAS, vive quand il a le trait — c'est
/// lui, avec le bandeau des touches en haut, qui dit à qui est le tour.
library;

import 'package:flutter/material.dart';

import '../../theme/themes.dart';
import '../scale.dart';
import 'game_top_bar.dart';

class MoveStrip extends StatefulWidget {
  const MoveStrip({
    super.key,
    required this.moves,
    required this.color,
    required this.onSelect,
    this.activeIndex,
    this.randomCode,
    required this.palette,
  });

  /// Notations dans l'ordre, Blanc puis Noir, Blanc puis Noir…
  final List<String> moves;

  /// Coup regardé. `null` = on est au présent (donc le dernier).
  final int? activeIndex;

  final Color color;
  final ThemePalette palette;

  /// Code de la position Random Fuga, affiché en tête quand il y en a un.
  final String? randomCode;

  /// Appelé avec l'indice du coup à montrer, `-1` pour la position de départ.
  final void Function(int index) onSelect;

  @override
  State<MoveStrip> createState() => _MoveStripState();
}

class _MoveStripState extends State<MoveStrip> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Nombre de coups déjà amenés à l'écran : inutile de redemander un
  /// défilement à chaque reconstruction, il y en a une par seconde à cause du
  /// chrono.
  int _scrolledTo = -1;

  /// Au présent, le bandeau montre toujours le dernier coup.
  void _scrollToEnd() {
    if (widget.activeIndex != null) return;
    if (widget.moves.length == _scrolledTo) return;
    _scrolledTo = widget.moves.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    _scrollToEnd();
    final moves = widget.moves;
    final active = widget.activeIndex ?? moves.length - 1;

    final turns = <Widget>[];
    for (var i = 0; i < moves.length; i += 2) {
      final blanc = moves[i];
      final noir = i + 1 < moves.length ? moves[i + 1] : null;
      final isActive = active == i || active == i + 1;
      turns.add(
        TextButton(
          onPressed: () => widget.onSelect(noir == null ? i : i + 1),
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: EdgeInsets.symmetric(horizontal: S(8)),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: isActive ? Colors.black : Colors.white,
          ),
          child: Text(
            '${i ~/ 2 + 1}.$blanc${noir == null ? '' : '/$noir'}',
            style: TextStyle(fontSize: SF(14), fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    return Container(
      // La hauteur vient de la pile (7 % de l'écran), comme chez Kivy.
      color: widget.color,
      // Comme le bandeau du haut : moins de marge, des flèches plus grosses.
      padding: EdgeInsets.symmetric(horizontal: S(12), vertical: S(2)),
      child: Row(
        children: [
          _arrow('<', moves.isEmpty ? null : () => widget.onSelect(active - 1)),
          Expanded(
            child: ListView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              children: [
                // Random Fuga : le code de la position en tête, pour pouvoir
                // la retrouver et la vérifier.
                if (widget.randomCode != null)
                  Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: S(8)),
                      child: Text(
                        widget.randomCode!,
                        style: TextStyle(
                          fontSize: SF(13),
                          fontWeight: FontWeight.bold,
                          color: widget.palette.clair,
                        ),
                      ),
                    ),
                  ),
                ...turns,
              ],
            ),
          ),
          _arrow(
            '>',
            widget.activeIndex == null
                ? null
                : () => widget.onSelect(active + 1),
          ),
        ],
      ),
    );
  }

  /// Flèche ronde, carrée : sa largeur suit la hauteur du bandeau.
  Widget _arrow(String label, VoidCallback? onPressed) => Opacity(
    opacity: onPressed == null ? 0.35 : 1,
    child: AspectRatio(
      aspectRatio: 1,
      child: Material(
        color: kBarButtonDark,
        borderRadius: BorderRadius.circular(S(20)),
        child: InkWell(
          borderRadius: BorderRadius.circular(S(20)),
          onTap: onPressed,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: SF(25),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
