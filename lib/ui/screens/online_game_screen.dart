/// Partie en ligne.
///
/// Toute la logique vit dans [OnlineGame] ; cet écran l'affiche et lui passe
/// les gestes, exactement comme l'écran local le fait avec le contrôleur.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../engine/board.dart';
import '../../engine/piece.dart';
import '../../game/move_controller.dart';
import '../../game/online_game.dart';
import '../../game/sound_player.dart';
import '../../game/last_move.dart';
import '../../i18n/translations.dart';
import '../../net/online_service.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../widgets/end_dialogs.dart';
import '../widgets/game_board_view.dart';
import '../widgets/move_strip.dart';
import '../widgets/game_top_bar.dart';
import '../widgets/pause_dialog.dart';
import '../widgets/player_panel.dart';

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
  LastMove? _lastMove;

  /// Position d'avant le coup : la mise en évidence en a besoin (type de la
  /// pièce qui pousse, chemin d'un saut).
  Board? _boardBefore;

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

  /// Le popup de fin n'est montré qu'une fois par partie.
  bool _endShown = false;

  void _handleEvent(OnlineEvent event) {
    if (!mounted) return;
    if (event == OnlineEvent.drawOffered && _g.drawOffered) {
      _askDraw();
    }
    if (event == OnlineEvent.nextGameStarted) _endShown = false;
    setState(() {});

    if (_g.endReason != null && !_endShown) {
      _endShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showEnd();
      });
    }
  }

  void _onTapCell(Cell cell) {
    // La position d'avant le coup est prise au premier geste du tour.
    if (!_g.game.moved) _boardBefore = _g.game.board.clone();
    final result = _g.tapCell(cell);
    if (result.effect == ControllerEffect.none) return;

    if (result.notation != null) {
      _sounds.playNotation(result.notation, hadEjection: result.hadEjection);
      _lastMove = LastMove.fromSlides(
        before: _boardBefore ?? Board.initial(),
        camp: result.camp ?? _g.game.turn.opposite,
        slides: result.slides,
        pushTargets: result.pushTargets,
        jumpPath: result.jumpPath,
      );
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
    // Mon camp est toujours en bas — sauf si le joueur retourne le plateau.
    final flipped = _flipOverride ?? (_g.myCamp == Camp.blanc);
    final topCamp = flipped ? Camp.noir : Camp.blanc;
    final bottomCamp = flipped ? Camp.blanc : Camp.noir;

    return Scaffold(
      backgroundColor: paletteOf(axes.menu).menu,
      body: SafeArea(
        child: Column(
          children: [
            GameTopBar(
              palette: palette,
              color: _campColor(palette, topCamp),
              onFlip: _toggleFlip,
              onChat: _openChat,
              onPause: _openPause,
              onMenu: _g.endReason != null
                  ? () => Navigator.of(context).pop()
                  : null,
            ),
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
                lastMove: _lastMove,
                pieceTheme: axes.pieces,
                boardTheme: axes.board,
              ),
            ),
            _banner(palette, bottomCamp),
            MoveStrip(
              moves: _g.game.history,
              color: _campColor(palette, bottomCamp),
              palette: palette,
              onSelect: (_) {},
            ),
          ],
        ),
      ),
    );
  }

  /// Couleur d'un camp, vive quand il a le trait.
  Color _campColor(ThemePalette palette, Camp camp) {
    final atTrait = _g.game.turn == camp && !_g.game.gameOver;
    if (camp == Camp.blanc) return atTrait ? palette.clair : palette.clairDim;
    return atTrait ? palette.fonce : palette.fonceDim;
  }

  /// Retourner le plateau : Kivy l'autorise même en ligne.
  bool? _flipOverride;

  void _toggleFlip() => setState(
    () => _flipOverride = !(_flipOverride ?? (_g.myCamp == Camp.blanc)),
  );

  /// La pause. En ligne, elle ne propose pas de quitter : on abandonne la
  /// partie par le [×] de son panneau, et le match entre deux parties.
  Future<void> _openPause() async {
    await showPauseDialog(
      context,
      palette: paletteOf(Settings.instance.themeAxes.general),
      quit: PauseQuit.none,
    );
    if (mounted) setState(() {});
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

    // Les gestes (↶ ½ X) n'appartiennent qu'à MON panneau : en ligne, je ne
    // peux ni annuler ni abandonner à la place de l'adversaire.
    final canAct = isMine && !_g.game.gameOver;

    return PlayerPanel(
      name: label,
      subtitle: subtitle,
      clock: _g.clock.displayFor(camp),
      palette: palette,
      isWhite: camp == Camp.blanc,
      isTurn: _g.game.turn == camp && !_g.game.gameOver,
      captures: _g.game.captured[camp.opposite] ?? const [],
      photo: isMine ? (OnlineService.instance.session?.photo ?? '') : '',
      score: _g.scoreLine.isEmpty
          ? null
          : (camp == Camp.blanc ? '${_g.scoreBlanc}' : '${_g.scoreNoir}'),
      busy: !isMine && !_g.opponentConnected,
      mirrored: isMine,
      onUndo: canAct && _g.game.canValidate
          ? () {
              if (_g.game.cancelCurrentMove()) setState(() {});
            }
          : null,
      onDraw: canAct ? _g.offerDraw : null,
      onResign: canAct ? _confirmResign : null,
    );
  }

  /// Quitter un match en cours : c'est un abandon du match entier.
  Future<void> _quitMatch() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(T('Quitter le match ?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(T('Annuler')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(T('Quitter le match')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _g.resignMatch();
    if (mounted) Navigator.of(context).pop();
  }

  /// Fin de partie : le popup de Kivy. Si le match continue, il propose la
  /// partie suivante ; sinon il annonce le résultat, le mélo, et le retour au
  /// menu.
  void _showEnd() {
    final palette = paletteOf(Settings.instance.themeAxes.general);
    final title = _verdict ?? T('Partie terminée');

    if (_g.matchContinues) {
      unawaited(
        showOnlineContinueDialog(
          context,
          palette: palette,
          title: title,
          body: _g.scoreLine,
          readySent: _g.readySent,
          onReady: () => setState(_g.readyForNext),
          onQuit: _quitMatch,
        ),
      );
      return;
    }

    final melo = _g.newMelo;
    final delta = _g.meloDelta;
    unawaited(
      showFinishDialog(
        context,
        palette: palette,
        title: title,
        body: _g.scoreLine,
        winner: switch (_g.loser?.opposite) {
          null => null,
          final Camp w => w == _g.myCamp ? widget.myPseudo : _g.info.opponent,
        },
        meloLine: (melo == null || delta == null)
            ? T('Mise à jour du mélo…')
            : T('Mélo : %d  (%s%d)')
                  .replaceFirst('%d', '$melo')
                  .replaceFirst('%s', delta >= 0 ? '+' : '')
                  .replaceFirst('%d', '$delta'),
        onMenu: () {
          if (mounted) Navigator.of(context).pop();
        },
      ),
    );
  }
}
