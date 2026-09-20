/// Une partie de correspondance : on rejoue l'historique, on joue son coup,
/// on l'envoie, et on repart.
library;

import 'package:flutter/material.dart';

import '../../engine/board.dart';
import '../../engine/piece.dart';
import '../../game/correspondence.dart';
import '../../game/move_controller.dart';
import '../../game/sound_player.dart';
import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../widgets/game_board_view.dart';

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

class _CorrGameScreenState extends State<CorrGameScreen> {
  final SoundPlayer _sounds = SoundPlayer();

  MoveController? _controller;
  Set<Cell> _lastMoveCells = {};
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
    final result = c.tapCell(cell);
    if (result.effect == ControllerEffect.none) return;

    if (result.notation != null) {
      _sounds.playNotation(result.notation, hadEjection: result.hadEjection);
      _lastMoveCells = {
        for (final (_, from, to) in result.slides) ...[from, to],
      }..removeWhere((cell) => !cell.onBoard);
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

  Future<void> _offerDraw() async {
    await widget.service.offerDraw(_g.id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(T('Proposition de nulle envoyée.'))));
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
    final flipped = _g.myCamp == Camp.blanc;
    final c = _controller;

    return Scaffold(
      backgroundColor: paletteOf(axes.menu).menu,
      appBar: AppBar(
        backgroundColor: palette.clair,
        foregroundColor: Colors.white,
        title: Text(_g.opponent),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: _g.unreadChat > 0,
              label: Text('${_g.unreadChat}'),
              child: const Icon(Icons.chat_bubble_outline),
            ),
            tooltip: T('Chat'),
            onPressed: _openChat,
          ),
          if (_g.status == CorrStatus.enCours) ...[
            TextButton(
              onPressed: _offerDraw,
              child: const Text('½', style: TextStyle(color: Colors.white)),
            ),
            IconButton(
              icon: const Icon(Icons.flag_outlined),
              tooltip: T('Abandonner'),
              onPressed: _resign,
            ),
          ],
        ],
      ),
      body: _replayError != null
          ? Center(child: Text(_replayError!))
          : c == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _header(palette),
                Expanded(
                  child: GameBoardView(
                    board: c.board,
                    palette: palette,
                    flipped: flipped,
                    onTapCell: _onTapCell,
                    selected: c.selected,
                    groupSelection: c.groupSelection,
                    highlighted: c.availablePushCells.toSet(),
                    lastMoveCells: _lastMoveCells,
                    pieceTheme: axes.pieces,
                    boardTheme: axes.board,
                  ),
                ),
                _footer(),
              ],
            ),
    );
  }

  Widget _header(ThemePalette palette) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
    color: _g.myCamp == Camp.blanc ? palette.clair : palette.fonce,
    child: Row(
      children: [
        Expanded(
          child: Text(
            '${widget.myPseudo}  ·  '
            '${_g.myScore} - ${_g.opponentScore}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Text(
          'Mélo ${_g.opponentMelo}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _footer() {
    final String message;
    if (_sending) {
      message = T('Envoi…');
    } else if (_played) {
      message = T('Coup envoyé.');
    } else if (_g.status == CorrStatus.termine) {
      message = _g.won == null
          ? T('Nulle')
          : (_g.won! ? T('Gagné !') : T('Perdu'));
    } else if (_canPlay) {
      message = _controller!.canValidate
          ? T('Retouchez la pièce pour valider')
          : T('À vous de jouer');
    } else {
      message = T("À votre adversaire\nde jouer").replaceAll('\n', ' ');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      color: Colors.black38,
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          if (_sending)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (_canPlay && _controller!.canValidate)
            TextButton(
              onPressed: () {
                if (_controller!.cancelCurrentMove()) setState(() {});
              },
              child: Text(T('Annuler')),
            ),
        ],
      ),
    );
  }
}
