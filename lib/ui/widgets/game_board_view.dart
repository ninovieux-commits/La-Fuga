/// Vue du plateau : décor, pièces, et gestes.
///
/// Partagée par la partie locale, la partie contre Deep Grey et la partie en
/// ligne — le plateau doit se comporter exactement pareil dans les trois cas.
library;

import 'package:flutter/material.dart';

import '../../engine/board.dart';
import '../../engine/piece.dart';
import '../../game/last_move.dart';
import '../../theme/themes.dart';
import 'board_geometry.dart';
import 'board_painter.dart';
import 'picto_touche.dart';
import 'theme_image_cache.dart';

class GameBoardView extends StatefulWidget {
  const GameBoardView({
    super.key,
    required this.board,
    required this.palette,
    required this.flipped,
    required this.onTapCell,
    this.fuguedHeirs = const {},
    this.slideJumpPath = const [],
    this.selected,
    this.groupSelection = const {},
    this.highlighted = const {},
    this.lastMove,
    this.pieceTheme,
    this.boardTheme,
    this.slides = const [],
    this.slideToken = 0,
    this.motRalliement,
    this.ralliementEnEdition,
    this.ralliementsTouchables = false,
    this.slideDuration = Duration.zero,
  });

  final Board board;
  final ThemePalette palette;

  /// Vrai quand les Blancs sont en bas.
  final bool flipped;

  final void Function(Cell cell) onTapCell;

  /// Camps dont l'Héritier a rejoint son ralliement : il s'y affiche.
  /// Où se tient l'Héritier de chaque camp qui a fugué : sa vraie case.
  final Map<Camp, Cell> fuguedHeirs;

  /// Atterrissages intermédiaires du coup en cours d'animation : la pièce y
  /// passe au lieu de couper en ligne droite.
  final List<Cell> slideJumpPath;

  final Cell? selected;
  final Set<Cell> groupSelection;

  /// Cases à pointer : directions de poussée encore disponibles.
  final Set<Cell> highlighted;

  /// Dernier coup joué : cadres, rebonds du multisaut, points de poussée.
  final LastMove? lastMove;

  /// Thème dont viennent les images de pièces (axe « pieces »).
  final String? pieceTheme;

  /// Thème dont vient l'image de plateau (axe « board »).
  ///
  /// Séparé du précédent : la composition à cinq axes permet de prendre les
  /// pièces d'un thème et le plateau d'un autre.
  final String? boardTheme;

  /// Pièces à faire glisser : (pièce, départ, arrivée) — portage de
  /// `animate_slide`. Kivy anime TOUS les coups, y compris ceux du joueur.
  final List<(Piece, Cell, Cell)> slides;

  /// Change à chaque nouveau glissement : c'est lui qui relance l'animation,
  /// et non le contenu de [slides], qui peut se répéter à l'identique.
  final int slideToken;

  /// Mot écrit sur les zones de ralliement — « Modifier », dans le composeur.
  final String? motRalliement;

  /// Le camp dont on choisit la zone : ses SEPT cases deviennent touchables,
  /// pas seulement celles qui rallient déjà.
  final Camp? ralliementEnEdition;

  /// Dans le composeur : les deux rangées de ralliement répondent au doigt,
  /// même vides — sinon une zone qu'on a vidée ne se rouvre jamais.
  final bool ralliementsTouchables;

  /// Durée du glissement — le réglage « Vitesse de glissée des pièces ».
  /// Nulle : les pièces se posent d'un coup, comme le mode « Instantané ».
  final Duration slideDuration;

  @override
  State<GameBoardView> createState() => _GameBoardViewState();
}

class _GameBoardViewState extends State<GameBoardView>
    with SingleTickerProviderStateMixin {
  LoadedThemeImages? _pieceImages;
  LoadedThemeImages? _boardImages;

  /// Glissement en cours. Au repos il vaut 1 : rien ne vole.
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: 1,
  );

  /// Cases dont la pièce est en vol.
  ///
  /// Ne change que DEUX fois par glissement — au décollage et à l'atterrissage
  /// — là où l'avancement, lui, change soixante fois par seconde. C'est ce qui
  /// permet à la couche des quarante pièces posées de ne pas être reconstruite
  /// à chaque image : seule celle qui vole l'est.
  final ValueNotifier<Set<Cell>> _flying = ValueNotifier(const {});

  @override
  void initState() {
    super.initState();
    _slide.addStatusListener(_onSlideStatus);
    _loadImages();
  }

  @override
  void dispose() {
    _slide.removeStatusListener(_onSlideStatus);
    _slide.dispose();
    _flying.dispose();
    super.dispose();
  }

  /// Le glissement est fini : la pièce se repose sur sa case.
  void _onSlideStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _flying.value.isNotEmpty) {
      _flying.value = const {};
    }
  }

  @override
  void didUpdateWidget(GameBoardView old) {
    super.didUpdateWidget(old);
    if (old.pieceTheme != widget.pieceTheme ||
        old.boardTheme != widget.boardTheme) {
      _loadImages();
    }
    if (old.slideToken != widget.slideToken) _startSlide();
  }

  /// Lance le glissement du coup qui vient d'être joué.
  ///
  /// Une durée nulle, ou rien à déplacer, et les pièces se posent aussitôt :
  /// c'est le mode « Instantané » des réglages.
  void _startSlide() {
    if (widget.slides.isEmpty || widget.slideDuration <= Duration.zero) {
      _flying.value = const {};
      _slide.value = 1;
      return;
    }
    _flying.value = {for (final (_, _, to) in widget.slides) to};
    // La durée suit la DISTANCE : le réglage donne le temps d'UNE case, et
    // l'animation dure le temps qu'il faut à la pièce qui va le plus loin.
    // À durée fixe, un multisaut de six cases filait six fois plus vite
    // qu'un pas simple.
    final cases = slideSpan(widget.slides, widget.slideJumpPath);
    _slide.duration = cases <= 1
        ? widget.slideDuration
        : widget.slideDuration * cases;
    _slide.forward(from: 0);
  }

  /// Charge les images des deux axes.
  ///
  /// Tant qu'elles ne sont pas prêtes, le rendu géométrique s'affiche : le
  /// plateau apparaît tout de suite plutôt que de rester blanc.
  ///
  /// UN CHARGEMENT QUI REVIENT TROP TARD N'ÉCRASE RIEN. On change de thème
  /// plus vite que les images ne se décodent : dans le composeur, choisir un
  /// plateau puis un autre lançait deux chargements, et c'est celui qui
  /// finissait le dernier qui s'affichait — pas celui qu'on venait de
  /// choisir. Le thème demandé pouvait donc revenir à l'écran après celui
  /// d'après, et ne s'y remettait qu'au prochain passage. Nino : « le
  /// composeur de thème foire parfois. Par exemple quand je sélectionne un
  /// plateau différent. »
  ///
  /// Chaque chargement vérifie donc, à son retour, que c'est bien ENCORE son
  /// thème qu'on attend.
  Future<void> _loadImages() async {
    final pieceTheme = widget.pieceTheme;
    final boardTheme = widget.boardTheme;

    _pieceImages = pieceTheme == null
        ? null
        : ThemeImageCache.ready(pieceTheme);
    _boardImages = boardTheme == null
        ? null
        : ThemeImageCache.ready(boardTheme);

    if (pieceTheme != null && _pieceImages == null) {
      final loaded = await ThemeImageCache.load(pieceTheme);
      if (mounted && widget.pieceTheme == pieceTheme) {
        setState(() => _pieceImages = loaded);
      }
    }
    if (boardTheme != null && _boardImages == null) {
      final loaded = await ThemeImageCache.load(boardTheme);
      if (mounted && widget.boardTheme == boardTheme) {
        setState(() => _boardImages = loaded);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final geometry = BoardGeometry(
          size: size,
          flipped: widget.flipped,
          rall: widget.board.rall,
          rangeeOuverte: widget.ralliementEnEdition,
          ralliementsTouchables: widget.ralliementsTouchables,
        );
        // Le plateau répond à la POSE du doigt, comme `on_touch_down` en
        // Kivy — pas à son relâchement. Un `Listener` ne passe par aucune
        // arène de gestes : la case part au moment exact du contact, et c'est
        // ce qui fait la différence entre « ça répond » et « ça suit ».
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            final cell = geometry.pixelToCell(event.localPosition);
            if (cell != null) widget.onTapCell(cell);
          },
          child: Stack(
            children: [
              // Le décor ne dépend que du thème et de la taille : isolé
              // derrière son RepaintBoundary, il n'est pas redessiné à chaque
              // coup.
              RepaintBoundary(
                child: CustomPaint(
                  size: size,
                  painter: BoardBackgroundPainter(
                    geometry: geometry,
                    palette: widget.palette,
                    images: _boardImages,
                    motRalliement: widget.motRalliement,
                    ralliementEnEdition: widget.ralliementEnEdition,
                  ),
                ),
              ),
              // Deux couches de pièces, chacune derrière sa frontière de
              // repeint : celles qui sont posées, et celle qui vole. Pendant
              // une glissée, seule la seconde est reconstruite à chaque image —
              // les quarante autres pièces ne changent pas, et leur couche
              // n'écoute que la liste des cases en vol, qui ne bouge qu'au
              // décollage et à l'atterrissage.
              ValueListenableBuilder<Set<Cell>>(
                valueListenable: _flying,
                builder: (context, flying, _) => RepaintBoundary(
                  child: CustomPaint(
                    size: size,
                    painter: BoardPiecesPainter(
                      geometry: geometry,
                      palette: widget.palette,
                      board: widget.board,
                      selected: widget.selected,
                      groupSelection: widget.groupSelection,
                      destinations: widget.highlighted,
                      lastMove: widget.lastMove,
                      theme: widget.pieceTheme,
                      images: _pieceImages,
                      flying: flying,
                      fuguedHeirs: widget.fuguedHeirs,
                    ),
                  ),
                ),
              ),
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _slide,
                  builder: (context, _) => CustomPaint(
                    size: size,
                    painter: FlyingPiecesPainter(
                      geometry: geometry,
                      palette: widget.palette,
                      // Une pièce tenue reste enfoncée, même en vol.
                      choisies: {
                        if (widget.selected != null) widget.selected!,
                        ...widget.groupSelection,
                      },
                      slides: widget.slides,
                      progress: _slide.value,
                      jumpPath: widget.slideJumpPath,
                      images: _pieceImages,
                      theme: widget.pieceTheme,
                    ),
                  ),
                ),
              ),
              // LE CHEVRON DE LA MENEUSE, dans la couche des widgets.
              //
              // C'est un symbole de touche comme les autres — couleur du
              // thème, trait noir, même fabrication — et `PictoTouche` est un
              // widget : le peindre à la main dans le peintre en redonnerait
              // une seconde version à tenir à jour. Il ne paraît que lorsque
              // PLUSIEURS pièces sont prises : seule, il n'y a personne à
              // mener. Nino : « quand on en sélectionne plusieurs, ce symbole
              // apparaît sur la meneuse. »
              //
              // EN DERNIER, ET IL SUIT SA PIÈCE. Posé plus haut dans la pile,
              // il passait sous la couche des pièces en vol ; posé sur la
              // case d'arrivée, il y attendait sa meneuse au lieu de
              // l'accompagner — la sélection a déjà suivi le coup quand le
              // glissement commence. Nino : « pendant une manœuvre, le
              // symbole de meneuse doit glisser avec la pièce. »
              if (widget.selected != null && widget.groupSelection.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _slide,
                      builder: (context, _) => Stack(
                        children: [
                          Positioned.fromRect(
                            rect:
                                placeEnVol(
                                  geometry,
                                  widget.slides,
                                  widget.slideJumpPath,
                                  _slide.value,
                                  widget.selected!,
                                ) ??
                                geometry.cellRect(
                                  widget.selected!.col,
                                  widget.selected!.row,
                                ),
                            child: PictoTouche(
                              asset: 'assets/images/meneuse.webp',
                              // LA COULEUR DE SON CAMP, comme partout
                              // ailleurs : l'orange des Blancs, le bleu des
                              // Noirs, dans le thème d'origine. Il avait
                              // d'abord porté l'AUTRE, de peur qu'il se fonde
                              // dans la pièce ; c'était inutile — la pièce
                              // choisie est enfoncée, et le chevron, plein et
                              // cerné de noir, s'en détache tout seul.
                              couleur:
                                  widget.board
                                          .at(
                                            widget.selected!.col,
                                            widget.selected!.row,
                                          )
                                          ?.camp ==
                                      Camp.noir
                                  ? widget.palette.fonce
                                  : widget.palette.clair,
                              secours: '^',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
