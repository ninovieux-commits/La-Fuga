/// Partie en ligne.
///
/// Toute la logique vit dans [OnlineGame] ; cet écran l'affiche et lui passe
/// les gestes, exactement comme l'écran local le fait avec le contrôleur.
library;

import 'package:flutter/material.dart';

import '../../engine/board.dart';
import '../../engine/piece.dart';
import '../../game/move_controller.dart';
import '../../game/online_game.dart';
import '../../game/sound_player.dart';
import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../widgets/game_board_view.dart';

class OnlineGameScreen extends StatefulWidget {
  const OnlineGameScreen({
    super.key,
    required this.game,
    required this.myPseudo,
  });

  final OnlineGame game;
  final String myPseudo;

  @override
  State<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends State<OnlineGameScreen> {
  final SoundPlayer _sounds = SoundPlayer();
  Set<Cell> _lastMoveCells = {};

  OnlineGame get _g => widget.game;

  @override
  void initState() {
    super.initState();
    _sounds.init();
    _g.onChanged = _handleEvent;
  }

  @override
  void dispose() {
    _sounds.dispose();
    _g.dispose();
    super.dispose();
  }

  void _handleEvent(OnlineEvent event) {
    if (!mounted) return;
    if (event == OnlineEvent.drawOffered && _g.drawOffered) {
      _askDraw();
    }
    setState(() {});
  }

  void _onTapCell(Cell cell) {
    final result = _g.tapCell(cell);
    if (result.effect == ControllerEffect.none) return;

    if (result.notation != null) {
      _sounds.playNotation(result.notation, hadEjection: result.hadEjection);
      _lastMoveCells = {
        for (final (_, from, to) in result.slides) ...[from, to],
      }..removeWhere((c) => !c.onBoard);
    }
    setState(() {});
  }

  Future<void> _askDraw() async {
    final accept = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(T('Nulle')),
        content: Text('${_g.info.opponent} ${T('propose la nulle')}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(T('Refuser')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(T('Accepter')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    accept == true ? _g.acceptDraw() : _g.declineDraw();
  }

  Future<void> _confirmResign() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(T('Abandonner')),
        content: Text(T('Abandonner cette partie ?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(T('Annuler')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(T('Abandonner')),
          ),
        ],
      ),
    );
    if (ok == true) _g.resign();
  }

  Future<void> _openChat() async {
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: paletteOf(Settings.instance.themeAxes.menu).menu,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 240,
                child: ListView(
                  children: [
                    for (final m in _g.chat)
                      ListTile(
                        dense: true,
                        title: Text(m.text),
                        subtitle: Text(
                          m.author == 'moi' ? widget.myPseudo : m.author,
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      decoration: InputDecoration(hintText: T('Message')),
                      onSubmitted: (t) {
                        _g.sendChat(t);
                        controller.clear();
                        setSheetState(() {});
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: () {
                      _g.sendChat(controller.text);
                      controller.clear();
                      setSheetState(() {});
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  String? get _verdict {
    final reason = _g.endReason;
    if (reason == null) return null;
    final winner = _g.loser?.opposite;
    final base = switch (reason) {
      'fugue' => T('Fugue'),
      'mat' => T('Mat'),
      'papatte' => T('Papatte'),
      'temps' => T('Temps écoulé'),
      'abandon' => T('Abandon'),
      'nulle' || 'nulle_pat' || 'nulle_accord' => T('Match nul'),
      'repetition' => T('Match nul par répétition'),
      _ => T('Partie terminée'),
    };
    if (winner == null) return base;
    final who = winner == _g.myCamp ? T('Gagné !') : T('Perdu');
    return '$base — $who';
  }

  @override
  Widget build(BuildContext context) {
    final axes = Settings.instance.themeAxes;
    final palette = paletteOf(axes.general);
    // Mon camp est toujours en bas.
    final flipped = _g.myCamp == Camp.blanc;
    final topCamp = flipped ? Camp.noir : Camp.blanc;
    final bottomCamp = flipped ? Camp.blanc : Camp.noir;

    return Scaffold(
      backgroundColor: paletteOf(axes.menu).menu,
      body: SafeArea(
        child: Column(
          children: [
            _banner(palette, topCamp),
            Expanded(
              child: GameBoardView(
                board: _g.game.board,
                palette: palette,
                flipped: flipped,
                onTapCell: _onTapCell,
                selected: _g.game.selected,
                groupSelection: _g.game.groupSelection,
                highlighted: _g.game.availablePushCells.toSet(),
                lastMoveCells: _lastMoveCells,
              ),
            ),
            _banner(palette, bottomCamp),
            _actionBar(),
          ],
        ),
      ),
    );
  }

  Widget _banner(ThemePalette palette, Camp camp) {
    final isMine = camp == _g.myCamp;
    final label = isMine ? widget.myPseudo : _g.info.opponent;
    String? subtitle;
    if (!isMine && !_g.opponentConnected) {
      final delay = _g.disconnectGrace;
      subtitle = delay == null
          ? T('Hors ligne')
          : '${T('Hors ligne')} · ${delay}s';
    } else if (!isMine) {
      subtitle = 'Mélo ${_g.info.opponentMelo}';
    } else if (_g.newMelo != null) {
      final d = _g.meloDelta ?? 0;
      subtitle = 'Mélo ${_g.newMelo} (${d >= 0 ? '+' : ''}$d)';
    }

    return PlayerBanner(
      label: label,
      subtitle: subtitle,
      clock: _g.clock.displayFor(camp),
      palette: palette,
      isWhite: camp == Camp.blanc,
      isTurn: _g.game.turn == camp && !_g.game.gameOver,
      busy: !isMine && !_g.opponentConnected,
    );
  }

  Widget _actionBar() {
    final verdict = _verdict;
    final over = _g.endReason != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      color: Colors.black38,
      child: Row(
        children: [
          Expanded(
            child: Text(
              verdict ??
                  (_g.game.canValidate
                      ? T('Retouchez la pièce pour valider')
                      : _g.isMyTurn
                      ? T('À vous de jouer')
                      : T(
                          "À votre adversaire\nde jouer",
                        ).replaceAll('\n', ' ')),
              style: TextStyle(
                color: over ? Colors.white : Colors.white70,
                fontWeight: over ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline, size: 20),
            tooltip: T('Messages'),
            onPressed: _openChat,
          ),
          if (!over) ...[
            TextButton(onPressed: _g.offerDraw, child: const Text('½')),
            TextButton(onPressed: _confirmResign, child: Text(T('Abandonner'))),
          ] else
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(T('< Menu')),
            ),
        ],
      ),
    );
  }
}
