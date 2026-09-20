/// Une partie de correspondance : on rejoue l'historique, on joue son coup,
/// on l'envoie, et on repart.
library;

import 'package:flutter/material.dart';

import '../../engine/board.dart';
import '../../engine/piece.dart';
import '../../game/correspondence.dart';
import '../../game/move_controller.dart';
import '../../game/sound_player.dart';
import '../../game/last_move.dart';
import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../../net/online_service.dart';
import '../widgets/game_board_view.dart';
import '../widgets/game_layout.dart';
import '../../game/clock.dart';
import '../widgets/game_top_bar.dart';
import '../widgets/move_strip.dart';
import '../widgets/name_menu.dart';
import '../widgets/pause_dialog.dart';
import '../widgets/player_panel.dart';
import '../widgets/slide_animation.dart';
import 'game_screen.dart';

class CorrGameScreen extends StatefulWidget {
  const CorrGameScreen({
    super.key,
    required this.game,
    required this.service,
    required this.myPseudo,
  });

  final CorrGame game;
  final CorrespondenceService service;
  final String myPseudo;

  @override
  State<CorrGameScreen> createState() => _CorrGameScreenState();
}

class _CorrGameScreenState extends State<CorrGameScreen> with SlideAnimation {
  final SoundPlayer _sounds = SoundPlayer();

  MoveController? _controller;
  LastMove? _lastMove;

  /// Position d'avant le coup : la mise en évidence en a besoin (type de la
  /// pièce qui pousse, chemin d'un saut).
  Board? _boardBefore;
  bool _sending = false;
  bool _played = false;
  String? _replayError;

  CorrGame get _g => widget.game;

  @override
  void initState() {
    super.initState();
    _sounds.init();
    _restore();
    if (_g.drawToAnswer) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _askDraw());
    }
  }

  @override
  void dispose() {
    _sounds.dispose();
    super.dispose();
  }

  /// Rejoue l'historique pour retrouver la position courante.
  ///
  /// Si un coup ne se relit pas, on l'annonce au lieu d'afficher une position
  /// fausse : mieux vaut un écran qui dit « je ne sais pas » qu'un plateau
  /// silencieusement faux.
  void _restore() {
    final state = replay(_g);
    if (state == null) {
      setState(() => _replayError = T('Partie illisible.'));
      return;
    }
    setState(() {
      _controller = MoveController(board: state.board, turn: state.turn);
      // Le dernier coup de l'adversaire reste encadré à l'ouverture.
      _lastMove = state.lastMove;
    });
  }

  bool get _canPlay =>
      _g.status == CorrStatus.enCours &&
      _g.myTurn &&
      !_played &&
      !_sending &&
      _controller != null;

  Future<void> _onTapCell(Cell cell) async {
    if (!_canPlay) return;
    final c = _controller!;
    if (!c.moved) _boardBefore = c.board.clone();
    final result = c.tapCell(cell);
    if (result.effect == ControllerEffect.none) return;

    if (result.notation != null) {
      _sounds.playNotation(result.notation, hadEjection: result.hadEjection);
      rememberSlides(result.slides);
      _lastMove = LastMove.fromSlides(
        before: _boardBefore ?? Board.initial(),
        camp: result.camp ?? c.turn.opposite,
        slides: result.slides,
        pushTargets: result.pushTargets,
        jumpPath: result.jumpPath,
      );
    }
    setState(() {});

    // Le coup est validé : on l'envoie.
    if (result.notation != null &&
        (result.effect == ControllerEffect.turnEnded ||
            result.effect == ControllerEffect.gameOver)) {
      await _send(result);
    }
  }

  Future<void> _send(ControllerResult result) async {
    setState(() => _sending = true);

    // Un coup qui clôt la partie part AVEC sa méthode : corr_jouer enregistre
    // le coup et clôt la partie en une seule requête. Deux appels séparés
    // ouvriraient la porte aux doubles envois.
    final method = result.effect == ControllerEffect.gameOver
        ? result.endReason
        : null;

    final ok = await widget.service.play(
      _g.id,
      result.notation!,
      method: method,
    );
    if (!mounted) return;

    setState(() {
      _sending = false;
      _played = ok;
    });

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(T("Impossible d'envoyer le coup."))),
      );
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// Répondre à une nulle proposée. On ne peut pas en proposer une soi-même :
  /// Kivy cache le ½ en correspondance (`_update_side_buttons`), le temps y
  /// étant illimité.
  Future<void> _askDraw() async {
    final accept = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(T('Nulle')),
        content: Text('${_g.drawProposer} ${T('propose la nulle')}'),
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
    await widget.service.answerDraw(_g.id, accept == true);
    if (accept == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _resign() async {
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
    if (ok != true) return;
    await widget.service.resign(_g.id);
    if (mounted) Navigator.of(context).pop();
  }

  /// Chat de la partie — les deux routes existaient côté serveur sans être
  /// utilisées par l'app Kivy.
  Future<void> _openChat() async {
    final messages = await widget.service.chat(_g.id);
    if (!mounted) return;

    final input = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: paletteOf(Settings.instance.themeAxes.menu).menu,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              T('Chat'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (messages == null)
              Text(T('Conversation indisponible.'))
            else if (messages.isEmpty)
              Text(T('Aucun message. Écrivez le premier !'))
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final m in messages)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          '${m['auteur'] ?? m['de'] ?? ''} : '
                          '${m['texte'] ?? ''}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: T('Votre message…'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    final text = input.text;
                    if (text.trim().isEmpty) return;
                    await widget.service.sendChat(_g.id, text);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: Text(T('Envoyer')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final axes = Settings.instance.themeAxes;
    final palette = paletteOf(axes.general);
    final flipped = _flipOverride ?? (_g.myCamp == Camp.blanc);
    final c = _controller;

    return Scaffold(
      backgroundColor: paletteOf(axes.menu).menu,
      body: SafeArea(
        child: c == null
            ? Column(
                children: [
                  _bar(palette, flipped),
                  Expanded(
                    child: Center(
                      child: _replayError != null
                          ? Text(_replayError!)
                          : const CircularProgressIndicator(),
                    ),
                  ),
                ],
              )
            : GameLayout(
                topBar: _bar(palette, flipped),
                topPanel: _panel(palette, flipped ? Camp.noir : Camp.blanc, c),
                board: GameBoardView(
                  board: c.board,
                  palette: palette,
                  flipped: flipped,
                  onTapCell: _onTapCell,
                  selected: c.selected,
                  groupSelection: c.groupSelection,
                  highlighted: c.availablePushCells.toSet(),
                  lastMove: _lastMove,
                  pieceTheme: axes.pieces,
                  boardTheme: axes.board,
                  slides: slides,
                  slideToken: slideToken,
                  slideDuration: slideDuration,
                ),
                bottomPanel: _panel(
                  palette,
                  flipped ? Camp.blanc : Camp.noir,
                  c,
                ),
                moveStrip: MoveStrip(
                  moves: _g.moves,
                  color: _campColor(palette, flipped ? Camp.blanc : Camp.noir),
                  palette: palette,
                  // La correspondance se relit, elle ne se remonte pas : le
                  // bandeau sert d'abord à relire les coups joués.
                  onSelect: (_) {},
                ),
              ),
      ),
    );
  }

  /// Analyser la position courante. L'IA y est interdite : elle soufflerait
  /// le coup d'une partie en cours.
  Future<void> _openAnalysis() async {
    final c = _controller;
    if (c == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          cadence: Cadence.zen,
          aiCamp: null,
          initialBoard: c.board.clone(),
          initialTurn: c.turn,
          analysis: true,
          analysisFromCorr: true,
          themeName: Settings.instance.themeAxes.general,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Couleur d'un camp, vive quand il a le trait.
  Color _campColor(ThemePalette palette, Camp camp) {
    final atTrait =
        _controller?.turn == camp && _g.status == CorrStatus.enCours;
    if (camp == Camp.blanc) return atTrait ? palette.clair : palette.clairDim;
    return atTrait ? palette.fonce : palette.fonceDim;
  }

  /// Le bandeau du haut, tel que Kivy le compose en correspondance.
  Widget _bar(ThemePalette palette, bool flipped) => GameTopBar(
    palette: palette,
    color: _campColor(palette, flipped ? Camp.noir : Camp.blanc),
    onFlip: _toggleFlip,
    onChat: _openChat,
    unreadChat: _g.unreadChat,
    // Kivy garde « Analyser » en correspondance : on peut essayer des coups
    // avant de jouer le sien.
    onAnalyse: _controller == null ? null : _openAnalysis,
    onPause: _openPause,
    onMenu: _g.status == CorrStatus.termine
        ? () => Navigator.of(context).pop()
        : null,
  );

  /// Retourner le plateau. Mon camp est en bas par défaut.
  bool? _flipOverride;

  void _toggleFlip() => setState(
    () => _flipOverride = !(_flipOverride ?? (_g.myCamp == Camp.blanc)),
  );

  /// La pause d'une partie de correspondance ne propose pas d'abandonner :
  /// on revient au menu, la partie reste en cours sur le serveur.
  Future<void> _openPause() async {
    final leave = await showPauseDialog(
      context,
      palette: paletteOf(Settings.instance.themeAxes.general),
      quit: PauseQuit.menu,
    );
    if (!mounted) return;
    setState(() {});
    if (leave) Navigator.of(context).pop();
  }

  /// Le panneau d'un joueur, comme en partie en ligne. La correspondance n'a
  /// pas de chrono : Kivy y affiche l'infini.
  Widget _panel(ThemePalette palette, Camp camp, MoveController c) {
    final isMine = camp == _g.myCamp;
    final canAct = isMine && _g.status == CorrStatus.enCours && !_played;

    return PlayerPanel(
      // Comme en ligne, le mélo suit le nom.
      name: isMine ? widget.myPseudo : '${_g.opponent}  (${_g.opponentMelo})',
      clock: '∞',
      palette: palette,
      isWhite: camp == Camp.blanc,
      isTurn: c.turn == camp && _g.status == CorrStatus.enCours,
      captures: c.captured[camp.opposite] ?? const [],
      photo: isMine ? (OnlineService.instance.session?.photo ?? '') : '',
      // En correspondance le score est cumulatif, sans objectif fixe : Kivy
      // écrit « X / ... ».
      score: '${isMine ? _g.myScore : _g.opponentScore} / ...',
      mirrored: isMine,
      onNameTap: () => showNameMenu(
        context,
        online: OnlineService.instance,
        pseudo: isMine ? widget.myPseudo : _g.opponent,
      ),
      onUndo: canAct && c.canValidate
          ? () {
              if (c.cancelCurrentMove()) setState(() {});
            }
          : null,
      // Pas de ½ en correspondance : le temps est illimité, Kivy ne montre
      // que l'abandon (`_update_side_buttons`).
      onResign: canAct ? _resign : null,
    );
  }
}
