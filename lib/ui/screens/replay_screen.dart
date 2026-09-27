/// Lecteur de parties : on rejoue une partie enregistrée, coup par coup.
library;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../engine/board.dart';
import '../../game/clock.dart';
import '../../game/slides.dart';
import '../../game/nmc.dart';
import '../../game/replay_controller.dart';
import '../../game/sound_player.dart';
import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import '../widgets/fuga_background.dart';
import '../widgets/deep_grey_dialog.dart';
import '../widgets/game_board_view.dart';
import '../widgets/game_layout.dart';
import '../widgets/game_top_bar.dart';
import '../widgets/move_strip.dart';
import '../widgets/nmc_dialog.dart';
import '../widgets/slide_animation.dart';
import '../widgets/player_panel.dart';
import 'game_screen.dart';

class ReplayScreen extends StatefulWidget {
  const ReplayScreen({super.key, required this.nmc, this.title});

  /// Contenu du fichier `.nmc`.
  final String nmc;

  final String? title;

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> with SlideAnimation {
  late final ReplayController _replay;
  final SoundPlayer _sounds = SoundPlayer();
  bool _flipped = true;

  @override
  void initState() {
    super.initState();
    _replay = ReplayController.fromNmc(widget.nmc);
    // Kivy ouvre la relecture sur le premier coup joué, pas sur la position
    // de départ (`viewing_idx = 0` à la fin de `load_replay`).
    _replay.goTo(1);
    _sounds.init();
  }

  @override
  void dispose() {
    _sounds.dispose();
    super.dispose();
  }

  /// Avance ou recule, en jouant le son ET le glissement du coup atteint.
  ///
  /// Le son suit la navigation : en avançant on entend le coup joué, en
  /// reculant on entend celui auquel on revient. Les pièces suivent de même —
  /// elles ne le faisaient pas, et parcourir une partie enregistrée faisait
  /// sauter le plateau d'une position à l'autre sans qu'on voie rien bouger.
  void _move(bool Function() action) {
    final avant = _replay.index;
    if (!action()) return;
    _animerVers(avant, _replay.index);
    _sounds.playNotation(_replay.current.notation);
    setState(() {});
  }

  /// Fait glisser les pièces entre deux positions de la partie.
  ///
  /// Toucher un coup du bandeau, même lointain, montre CE coup se jouer : on
  /// part de la position qui le précède. Reculer rejoue le coup à l'envers,
  /// atterrissages de multisaut compris, dans l'autre sens.
  void _animerVers(int depuis, int vers) {
    if (depuis == vers) return;
    final recule = vers < depuis;
    // En reculant : le coup défait est celui qu'on quitte. En avançant ou en
    // sautant d'un coup à l'autre : celui qui mène là où l'on va.
    final coup = recule ? _replay.steps[vers + 1] : _replay.steps[vers];
    final origine = recule ? _replay.steps[vers + 1] : _replay.steps[vers - 1];
    final arrivee = _replay.steps[vers];

    final chemin = coup.lastMove?.jumpPath ?? const <Cell>[];
    final glissees = [
      ...slidesBetween(origine.board, arrivee.board),
      // L'Héritier qui fugue quitte le plateau : il n'a pas d'arrivée à
      // apparier, et sans cela le coup final ne montrait rien glisser.
      for (final camp in arrivee.fugued.difference(origine.fugued))
        ...fugueSlide(origine.board, arrivee.board, camp),
    ];
    rememberSlides(
      glissees,
      jumpPath: recule ? chemin.reversed.toList() : chemin,
    );
  }

  /// Reprend la partie depuis la position affichée, seul ou contre l'IA.
  ///
  /// Sans camp choisi, on repart en analyse plutôt que contre l'IA : mieux
  /// vaut une partie libre qu'un écran qui se ferme.
  Future<void> _playFromHere(bool againstAi, {Camp? myCamp}) async {
    final step = _replay.current;
    final ai = againstAi ? myCamp?.opposite : null;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          cadence: Cadence.zen,
          aiCamp: ai,
          initialBoard: step.board.clone(),
          initialTurn: step.turn,
          initialFugued: step.fugued,
          analysis: ai == null,
          // On reprend la position telle qu'on la regardait.
          initialFlipped: ai == null ? _flipped : null,
          themeName: Settings.instance.themeAxes.general,
        ),
      ),
    );
  }

  /// Contre Deep Grey : le joueur choisit son camp, le trait ne change pas.
  Future<void> _playAgainstDeepGrey() async {
    final mine = await askDeepGreyCamp(context);
    if (mine == null || !mounted) return;
    await _playFromHere(true, myCamp: mine);
  }

  @override
  Widget build(BuildContext context) {
    final axes = Settings.instance.themeAxes;
    final palette = paletteOf(axes.general);
    final step = _replay.current;
    final meta = _replay.meta;
    // `_flipped` vrai = Blancs en bas, comme en Kivy.
    final topCamp = _flipped ? Camp.noir : Camp.blanc;
    final bottomCamp = _flipped ? Camp.blanc : Camp.noir;

    return FugaScaffold(
      // Le bandeau touche le HAUT de l'écran, comme en Kivy : en plein
      // écran immersif il n'y a pas de barre d'état à éviter, et la bande
      // laissée au-dessus mangeait de la place au plateau.
      body: SafeArea(
        top: false,
        child: GameLayout(
          topBar: GameTopBar(
            palette: palette,
            // En relecture, le bandeau prend la couleur du camp au trait.
            color: step.turn == Camp.blanc ? palette.clair : palette.fonce,
            onFlip: () => setState(() => _flipped = !_flipped),
            pauseLabel: '<<',
            onPause: () => Navigator.of(context).pop(),
            onCopyNmc: () => showNmcDialog(context, widget.nmc),
            onAnalyse: () => _playFromHere(false),
            onDeepGrey: _playAgainstDeepGrey,
          ),
          notice: _replay.isTruncated ? _truncatedNotice() : null,
          topPanel: _panel(palette, topCamp, meta),
          board: GameBoardView(
            board: step.board,
            palette: palette,
            flipped: _flipped,
            onTapCell: (_) {},
            lastMove: step.lastMove,
            fuguedHeirs: step.fugued,
            slides: slides,
            slideToken: slideToken,
            slideDuration: slideDuration,
            slideJumpPath: slideJumpPath,
            pieceTheme: axes.pieces,
            boardTheme: axes.board,
          ),
          bottomPanel: _panel(palette, bottomCamp, meta),
          moveStrip: MoveStrip(
            moves: [
              for (var i = 1; i < _replay.steps.length; i++)
                _replay.steps[i].notation ?? '',
            ],
            activeIndex: _replay.index - 1,
            color: bottomCamp == Camp.blanc ? palette.clair : palette.fonce,
            palette: palette,
            randomCode: meta.random,
            onSelect: (i) => _move(() => _replay.goTo(i + 1)),
          ),
        ),
      ),
    );
  }

  /// Panneau d'un joueur, rempli avec l'en-tête du fichier : les noms, le
  /// chrono de la cadence enregistrée, et les pièces prises à cet instant.
  Widget _panel(ThemePalette palette, Camp camp, NmcMeta meta) {
    final blancIsFirst = meta.blanc.isEmpty || meta.blanc == meta.player1;
    final name = (camp == Camp.blanc) == blancIsFirst
        ? meta.player1
        : meta.player2;

    return PlayerPanel(
      name: name.isEmpty ? T('Joueur 1') : name,
      clock: _clockLabel(meta.cadence),
      palette: palette,
      isWhite: camp == Camp.blanc,
      isTurn: _replay.current.turn == camp,
      captures: _replay.current.captured[camp.opposite] ?? const [],
      score: '0 / ${meta.objectif == 'partie' ? '1' : meta.objectif}',
    );
  }

  /// Chrono affiché en relecture : Kivy y remet la pendule de la cadence
  /// enregistrée (`load_replay`), pas le temps réellement consommé.
  String _clockLabel(String cadence) {
    if (cadence == 'zen' || cadence.isEmpty) return '∞';
    final minutes = int.tryParse(cadence) ?? 15;
    return '${minutes.toString().padLeft(2, '0')}:00';
  }

  /// La partie n'a pas pu être rejouée jusqu'au bout : on le dit, au lieu de
  /// laisser croire qu'elle s'arrêtait là.
  Widget _truncatedNotice() => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(vertical: S(6), horizontal: S(16)),
    color: FugaColors.immobile.withValues(alpha: 0.85),
    child: Text(
      '${T("Lecture interrompue au coup")} ${_replay.brokenMoveNumber}',
      style: TextStyle(color: Colors.white, fontSize: SF(12)),
    ),
  );
}
