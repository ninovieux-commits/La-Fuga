/// Lecteur de parties : on rejoue une partie enregistrée, coup par coup.
library;

import 'package:flutter/material.dart';

import '../../engine/piece.dart';
import '../../game/clock.dart';
import '../../game/replay_controller.dart';
import '../../game/sound_player.dart';
import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../widgets/game_board_view.dart';
import 'game_screen.dart';

class ReplayScreen extends StatefulWidget {
  const ReplayScreen({super.key, required this.nmc, this.title});

  /// Contenu du fichier `.nmc`.
  final String nmc;

  final String? title;

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  late final ReplayController _replay;
  final SoundPlayer _sounds = SoundPlayer();
  bool _flipped = true;

  @override
  void initState() {
    super.initState();
    _replay = ReplayController.fromNmc(widget.nmc);
    _sounds.init();
  }

  @override
  void dispose() {
    _sounds.dispose();
    super.dispose();
  }

  /// Avance ou recule, en jouant le son du coup atteint.
  ///
  /// Le son suit la navigation : en avançant on entend le coup joué, en
  /// reculant on entend celui auquel on revient.
  void _move(bool Function() action) {
    if (!action()) return;
    _sounds.playNotation(_replay.current.notation);
    setState(() {});
  }

  /// Reprend la partie depuis la position affichée.
  ///
  /// Contre Deep Grey, l'IA prend le camp qui n'est PAS au trait : c'est au
  /// lecteur de jouer le coup qu'il regarde.
  Future<void> _playFromHere(bool againstAi) async {
    final step = _replay.current;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          cadence: Cadence.illimitee,
          aiCamp: againstAi ? step.turn.opposite : null,
          initialBoard: step.board.clone(),
          initialTurn: step.turn,
          analysis: !againstAi,
          themeName: Settings.instance.themeAxes.general,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final axes = Settings.instance.themeAxes;
    final palette = paletteOf(axes.general);
    final step = _replay.current;
    final meta = _replay.meta;

    return Scaffold(
      backgroundColor: paletteOf(axes.menu).menu,
      appBar: AppBar(
        backgroundColor: palette.clair,
        foregroundColor: Colors.white,
        title: Text(widget.title ?? '${meta.player1} – ${meta.player2}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flip),
            tooltip: T('Retourner le plateau'),
            onPressed: () => setState(() => _flipped = !_flipped),
          ),
          // Reprendre la partie d'ici : soit pour explorer seul, soit contre
          // Deep Grey — comme en Kivy.
          PopupMenuButton<bool>(
            icon: const Icon(Icons.play_circle_outline),
            tooltip: T('Analyse'),
            onSelected: _playFromHere,
            itemBuilder: (context) => [
              PopupMenuItem(value: false, child: Text(T('Analyse'))),
              PopupMenuItem(
                value: true,
                child: Text(T('Jouer contre Deep Grey')),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _header(palette, meta),
          if (_replay.isTruncated) _truncatedNotice(),
          Expanded(
            child: GameBoardView(
              board: step.board,
              palette: palette,
              flipped: _flipped,
              onTapCell: (_) {},
              lastMoveCells: step.highlightedCells,
              pieceTheme: axes.pieces,
              boardTheme: axes.board,
            ),
          ),
          _moveStrip(palette),
          _controls(palette),
        ],
      ),
    );
  }

  Widget _header(ThemePalette palette, meta) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
    color: palette.clairDim,
    child: Row(
      children: [
        Expanded(
          child: Text(
            '${meta.date}  ·  ${meta.cadence}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        Text(
          '${meta.result}  ${meta.method}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );

  /// La partie n'a pas pu être rejouée jusqu'au bout : on le dit, au lieu de
  /// laisser croire qu'elle s'arrêtait là.
  Widget _truncatedNotice() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
    color: FugaColors.immobile.withValues(alpha: 0.85),
    child: Text(
      '${T("Lecture interrompue au coup")} ${_replay.brokenMoveNumber}',
      style: const TextStyle(color: Colors.white, fontSize: 12),
    ),
  );

  /// Bandeau des coups : on peut sauter directement à l'un d'eux.
  Widget _moveStrip(ThemePalette palette) {
    if (_replay.moveCount == 0) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _replay.moveCount,
        itemBuilder: (context, i) {
          final stepIndex = i + 1;
          final selected = _replay.index == stepIndex;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
            child: ActionChip(
              backgroundColor: selected ? palette.clair : null,
              label: Text(
                '${(stepIndex + 1) ~/ 2}${stepIndex.isOdd ? '.' : '…'} '
                '${_replay.steps[stepIndex].notation}',
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? Colors.white : null,
                ),
              ),
              onPressed: () => _move(() => _replay.goTo(stepIndex)),
            ),
          );
        },
      ),
    );
  }

  Widget _controls(ThemePalette palette) {
    final step = _replay.current;
    final label = step.notation == null
        ? T('Position de départ')
        : '${_replay.index} / ${_replay.moveCount}  ·  ${step.notation}';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      color: Colors.black38,
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.first_page),
                onPressed: _replay.atStart
                    ? null
                    : () => _move(_replay.toStart),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _replay.atStart
                    ? null
                    : () => _move(_replay.previous),
              ),
              Text(
                step.turn == Camp.blanc ? T('Blanc') : T('Noir'),
                style: TextStyle(
                  color: step.turn == Camp.blanc
                      ? palette.clair
                      : palette.fonce,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _replay.atEnd ? null : () => _move(_replay.next),
              ),
              IconButton(
                icon: const Icon(Icons.last_page),
                onPressed: _replay.atEnd ? null : () => _move(_replay.toEnd),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
