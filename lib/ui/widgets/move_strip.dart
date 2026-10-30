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
import 'package:flutter/rendering.dart';

import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'fuga_button.dart';
import 'game_top_bar.dart';
import 'picto_touche.dart';

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

  /// Appelé avec l'indice du DEMI-COUP à montrer, `-1` pour la position de
  /// départ.
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

  /// Une clé par demi-coup, pour retrouver celui qu'on veut amener à
  /// l'écran.
  ///
  /// UNE SEULE CLÉ POSÉE SUR LE COUP ACTIF NE MARCHE PAS : elle saute d'un
  /// coup à l'autre, et au moment où l'on cherche le coup visé son contexte
  /// est nul — le défilement ne partait jamais. Chaque coup garde donc la
  /// sienne.
  final Map<int, GlobalKey> _cles = {};

  GlobalKey _cleDe(int index) => _cles.putIfAbsent(index, GlobalKey.new);

  /// Dernier coup amené à l'écran : on ne redemande pas le même défilement à
  /// chaque reconstruction.
  int? _montre;

  /// EN RELECTURE, LE BANDEAU SUIT LE COUP REGARDÉ.
  ///
  /// Nino, en mode lecture : « les coups dans le bandeau fin du bas doivent
  /// défiler avec la partie. » Le bandeau ne se recalait qu'au présent : une
  /// partie lue défilait sur le plateau pendant que le bandeau restait sur
  /// ses dix premiers coups.
  void _suivreLActif(int actif) {
    if (widget.activeIndex == null) return;
    if (_montre == actif) return;
    _montre = actif;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _cles[actif]?.currentContext;
      // ignore: avoid_print
      if (ctx == null || !_scroll.hasClients) return;
      final boite = ctx.findRenderObject();
      if (boite is! RenderBox) return;
      // Au MILIEU du bandeau : on voit ce qui précède et ce qui suit, et le
      // coup suivant n'arrive pas par le bord.
      //
      // D'UN SAUT, sans animation : une lecture à une demi-seconde par coup
      // lancerait deux cents petits défilements qui se recouvrent, et la
      // fluidité passe avant la grâce.
      //
      // Le décalage se calcule plutôt que de passer par `ensureVisible` :
      // celui-ci ne bougeait pas d'un pixel quand le coup visé était loin
      // hors du cadre — exactement le cas qu'on veut traiter.
      final cadre = RenderAbstractViewport.of(boite);
      final cible = cadre.getOffsetToReveal(boite, 0.5).offset;
      final position = _scroll.position;
      _scroll.jumpTo(
        cible.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    });
  }

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
    _suivreLActif(active);

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
            'assets/images/fleche_gauche.webp',
            '<',
            T('Coup précédent'),
            moves.isEmpty || active < 0
                ? null
                : () => widget.onSelect(active - 1),
          ),
          Expanded(
            // TOUS LES COUPS SONT CONSTRUITS, pas seulement ceux qu'on voit.
            // Un `ListView` ne bâtit que ce qui entre dans le cadre : le coup
            // qu'on venait de lire, loin sur la droite, n'existait donc pas
            // encore quand on cherchait à l'amener à l'écran, et le bandeau
            // ne bougeait jamais. Un bandeau de coups n'a pas de quoi peser :
            // ce sont quelques dizaines de petits textes.
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: Row(
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
          ),
          _arrow(
            'assets/images/fleche_droite.webp',
            '>',
            T('Coup suivant'),
            widget.activeIndex == null
                ? null
                : () => widget.onSelect(active + 1),
          ),
        ],
      ),
    );
  }

  /// Un demi-coup : sa notation, touchable pour revenir dessus. Le demi-coup
  /// regardé s'écrit en noir, les autres en blanc.
  Widget _half(int index, String notation, bool actif) => TextButton(
    key: _cleDe(index),
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
  ///
  /// Son DESSIN suit le thème, comme la boule, l'avion et le drapeau : un
  /// fichier blanc sur fond transparent, teinté ici. Le chevron écrit « < »
  /// reste en secours, si l'image venait à manquer.
  ///
  /// Sans geste, elle PÂLIT — de la pâleur commune à toutes les touches
  /// éteintes de l'application. Elle a porté des hachures le temps d'un
  /// essai ; Nino, les ayant vues en vrai, a demandé qu'on revienne à ceci.
  Widget _arrow(
    String asset,
    String secours,
    String infobulle,
    VoidCallback? onPressed,
  ) => Opacity(
    opacity: onPressed == null ? kOpaciteEteinte : 1,
    // L'infobulle est DANS la pâleur, et non autour : c'est ce qui permet de
    // lire l'une en partant de l'autre. Et une flèche dessinée, sans mot,
    // doit pouvoir dire son nom.
    child: Tooltip(
      message: infobulle,
      child: AspectRatio(
        aspectRatio: 1,
        child: Material(
          color: kBarButtonDark,
          shape: formeDeTouche(BorderRadius.circular(S(20))),
          child: InkWell(
            borderRadius: BorderRadius.circular(S(20)),
            onTap: onPressed,
            child: Center(
              child: PictoTouche(
                asset: asset,
                // LA COULEUR FONCÉE. Nino : « les deux flèches de navigation
                // tout en bas aussi […] doivent utiliser la couleur
                // foncée. »
                couleur: widget.palette.fonce,
                secours: secours,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
