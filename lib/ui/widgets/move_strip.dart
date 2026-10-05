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
    this.onPremove,
    this.premoveCount = 0,
  });

  /// Notations dans l'ordre, Blanc puis Noir, Blanc puis Noir…
  final List<String> moves;

  /// Coup regardé. `null` = on est au présent (donc le dernier).
  final int? activeIndex;

  final Color color;
  final ThemePalette palette;

  /// Code de la position Random Fuga, affiché en tête quand il y en a un.
  final String? randomCode;

  /// Appelé avec l'indice du DEMI-COUP à montrer, `-1` pour la position de
  /// départ.
  final void Function(int index) onSelect;

  /// Préparer ses pré-coups. `null` : la touche ne s'affiche pas — elle n'a de
  /// sens qu'en correspondance, et seulement quand c'est à l'adversaire de
  /// jouer.
  final VoidCallback? onPremove;

  /// Combien de variantes sont déjà armées. La touche le montre, pour qu'on
  /// sache sans l'ouvrir qu'une réponse attend.
  final int premoveCount;

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

    // Un tour, trois morceaux : son numéro, le demi-coup blanc, le demi-coup
    // noir. Chaque DEMI-COUP a sa propre touche — le bandeau n'en offrait
    // qu'une par tour, et elle menait toujours au coup noir : on ne pouvait
    // pas revenir sur le seul coup blanc, il fallait l'enjamber.
    final turns = <Widget>[];
    for (var i = 0; i < moves.length; i += 2) {
      final noir = i + 1 < moves.length ? moves[i + 1] : null;
      turns.add(
        Padding(
          padding: EdgeInsets.symmetric(horizontal: S(4)),
          child: Row(
            children: [
              Text(
                '${i ~/ 2 + 1}.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: SF(14),
                  fontWeight: FontWeight.bold,
                ),
              ),
              _half(i, moves[i], active == i),
              if (noir != null) ...[
                Text(
                  '/',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: SF(14),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                _half(i + 1, noir, active == i + 1),
              ],
            ],
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
          // Jusqu'à la position de départ : un demi-coup à la fois, et le
          // dernier pas ramène avant le premier coup.
          _arrow(
            '<',
            moves.isEmpty || active < 0
                ? null
                : () => widget.onSelect(active - 1),
          ),
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
          // La touche des pré-coups, à côté des flèches. Elle porte le nombre
          // de variantes armées quand il y en a, et un « P » quand il n'y en a
          // pas encore.
          if (widget.onPremove != null)
            _arrow(
              widget.premoveCount > 0 ? '${widget.premoveCount}' : 'P',
              widget.onPremove,
              fond: widget.premoveCount > 0 ? widget.palette.fonce : null,
            ),
        ],
      ),
    );
  }

  /// Un demi-coup : sa notation, touchable pour revenir dessus. Le demi-coup
  /// regardé s'écrit en noir, les autres en blanc.
  Widget _half(int index, String notation, bool actif) => TextButton(
    onPressed: () => widget.onSelect(index),
    style: TextButton.styleFrom(
      minimumSize: Size.zero,
      padding: EdgeInsets.symmetric(horizontal: S(3)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: actif ? Colors.black : Colors.white,
    ),
    child: Text(
      notation,
      style: TextStyle(fontSize: SF(14), fontWeight: FontWeight.bold),
    ),
  );

  /// Flèche ronde, carrée : sa largeur suit la hauteur du bandeau.
  Widget _arrow(String label, VoidCallback? onPressed, {Color? fond}) => Opacity(
    opacity: onPressed == null ? 0.35 : 1,
    child: AspectRatio(
      aspectRatio: 1,
      child: Material(
        color: fond ?? kBarButtonDark,
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
