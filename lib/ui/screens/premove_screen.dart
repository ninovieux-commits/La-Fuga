/// Préparer ses pré-coups : on joue le coup de l'adversaire, puis le sien.
///
/// En correspondance, l'attente se compte en heures. Quand on sait déjà quoi
/// répondre, on le prépare ici : si l'adversaire joue le coup prévu, la
/// réponse part toute seule — c'est le SERVEUR qui la joue, téléphone éteint.
///
/// On compose une variante en jouant les deux camps à tour de rôle, comme en
/// analyse : son coup, le nôtre, son coup, le nôtre… Une variante s'arrête
/// toujours sur un des NÔTRES, sans quoi elle ne préparerait rien.
///
/// Six variantes au plus, six demi-coups au plus, et aucune ne doit contredire
/// une autre. La règle est dans `lib/game/premove.dart` ; cet écran ne fait que
/// l'appliquer et dire pourquoi, quand elle refuse.
library;

import 'package:flutter/material.dart';

import '../../engine/board.dart';
import '../../engine/literal_replay.dart';
import '../../engine/piece.dart';
import '../../game/correspondence.dart';
import '../../game/move_controller.dart';
import '../../game/premove.dart';
import '../../game/sound_player.dart';
import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import '../widgets/fuga_background.dart';
import '../widgets/fuga_button.dart';
import '../widgets/game_board_view.dart';
import '../widgets/game_top_bar.dart';
import '../widgets/slide_animation.dart';

class PremoveScreen extends StatefulWidget {
  const PremoveScreen({
    super.key,
    required this.game,
    required this.service,
    required this.board,
    this.plan,
    this.flipped = false,
    this.sounds,
  });

  final CorrGame game;
  final CorrespondenceService service;

  /// Position actuelle de la partie : l'adversaire y a le trait.
  final Board board;

  /// Le plan à reprendre, quand l'appelant en sait un plus frais que celui de
  /// la partie. Armer un plan ne change ni les coups ni le statut : la partie
  /// n'est donc pas relue, et `game.premove` reste celui d'avant.
  final PremovePlan? plan;

  final bool flipped;

  /// Injectable pour les tests, comme partout ailleurs.
  final SoundPlayer? sounds;

  @override
  State<PremoveScreen> createState() => _PremoveScreenState();
}

class _PremoveScreenState extends State<PremoveScreen> with SlideAnimation {
  late MoveController _jeu;
  late PremovePlan _plan;

  /// Les demi-coups de la variante en cours de composition.
  final List<String> _ligne = [];

  /// Ce que vaut le dernier coup de la ligne, quand il termine la partie.
  String? _methode;
  String? _gagnant;

  /// Pourquoi la dernière tentative d'enregistrement a été refusée.
  String? _refus;

  /// Un envoi est en vol.
  bool _envoi = false;

  late SoundPlayer _sons;

  @override
  void initState() {
    super.initState();
    _sons = widget.sounds ?? SoundPlayer();
    // Le plan déjà armé côté serveur, s'il y en a un : on reprend où on en
    // était plutôt que de repartir de zéro.
    _plan =
        widget.plan ??
        widget.game.premove ??
        PremovePlan(base: corrMoveLines(widget.game.movesText).length);
    _jeu = _neuf();
  }

  /// Un contrôleur sur la position de la partie : l'adversaire y a le trait.
  ///
  /// Une variante n'est pas une partie : la répétition n'y veut rien dire.
  MoveController _neuf() => _depuis(const []);

  /// Vrai si le prochain demi-coup est à NOUS.
  bool get _aNous => premoveEstANous(_ligne.length);

  /// Vrai si la variante en cours peut être enregistrée : elle a au moins un
  /// aller-retour, et elle s'arrête sur un de nos coups.
  bool get _enregistrable => _ligne.isNotEmpty && _ligne.length.isEven;

  /// Vrai si on peut encore jouer dans la variante en cours.
  bool get _peutJouer =>
      !_envoi &&
      _ligne.length < kPremoveMaxCoups &&
      // Une variante qui s'est terminée sur une fin de partie ne se prolonge
      // pas : il n'y a plus rien après.
      _methode == null &&
      _plan.peutEnAjouter;

  void _onTapCell(Cell cell) {
    if (!_peutJouer) return;
    final r = _jeu.tapCell(cell);
    if (r.effect == ControllerEffect.none) return;
    rememberSlides(r.slides, jumpPath: r.jumpPath);
    final notation = r.notation;
    setState(() {
      _refus = null;
      if (notation != null) {
        _ligne.add(notation);
        if (r.effect == ControllerEffect.gameOver) {
          // C'est NOUS qui avons compté : le serveur ne connaît pas les
          // règles, et c'est ce couple-là qui lui dira de clore la partie.
          _methode = r.endReason ?? 'nulle';
          _gagnant = r.loser?.opposite.wire;
        }
      }
    });
    if (notation != null) _sons.playNotation(notation);
  }

  /// Défaire le dernier demi-coup de la variante en cours.
  void _defaire() {
    if (_ligne.isEmpty) return;
    final garde = List<String>.of(_ligne)..removeLast();
    setState(() {
      _ligne
        ..clear()
        ..addAll(garde);
      _methode = null;
      _gagnant = null;
      _refus = null;
      _jeu = _depuis(garde);
    });
  }

  /// Un contrôleur posé sur la position qu'on atteint en jouant [coups] depuis
  /// la position de la partie.
  ///
  /// Relecture LITTÉRALE, comme partout : les notations viennent d'être
  /// produites ici même, elles s'appliquent telles qu'elles sont écrites.
  MoveController _depuis(List<String> coups) {
    var board = widget.board.clone();
    final fugues = <Camp>{};
    for (final coup in coups) {
      final relu = applyNotationLiterally(board, coup);
      board = relu.board;
      fugues.addAll(relu.fugued);
    }
    return MoveController(
      board: board,
      turn: coups.length.isEven ? widget.game.opponentCamp : widget.game.myCamp,
      countRepetitions: false,
      fugued: fugues,
    );
  }

  /// Ranger la variante en cours parmi les autres.
  void _garder() {
    final v = PremoveVariante(
      List<String>.of(_ligne),
      methode: _methode,
      gagnant: _gagnant,
    );
    final refus = _plan.refusDe(v);
    if (refus != null) {
      setState(() => _refus = _texteDuRefus(refus));
      return;
    }
    setState(() {
      _plan = _plan.avec(v)!;
      _ligne.clear();
      _methode = null;
      _gagnant = null;
      _refus = null;
      _jeu = _neuf();
    });
  }

  void _oublier(int index) => setState(() {
    _plan = _plan.sans(index);
    _refus = null;
  });

  String _texteDuRefus(PremoveRefus refus) => switch (refus) {
    PremoveRefus.tropDeVariantes => T('Six variantes au plus.'),
    PremoveRefus.malFormee => T(
      'Une variante compte au plus six demi-coups, et finit par le vôtre.',
    ),
    PremoveRefus.doublon => T('Cette variante est déjà préparée.'),
    PremoveRefus.contradiction => T(
      'Cette variante en contredit une autre : au même coup de votre '
      'adversaire, vous répondriez deux choses différentes.',
    ),
  };

  /// Envoyer le plan au serveur et refermer l'écran.
  Future<void> _terminer() async {
    setState(() => _envoi = true);
    final erreur = await widget.service.savePremoves(widget.game.id, _plan);
    if (!mounted) return;
    if (erreur != null) {
      setState(() {
        _envoi = false;
        _refus = erreur;
      });
      return;
    }
    Navigator.of(context).pop(_plan);
  }

  @override
  Widget build(BuildContext context) {
    final axes = Settings.instance.themeAxes;
    final palette = paletteOf(axes.general);

    return FugaScaffold(
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Le bandeau a besoin d'une hauteur imposée : ses touches sont
            // carrées, et sans contrainte verticale elles ne savent pas quelle
            // taille prendre. Même proportion que `GameLayout` : 7 parts
            // sur 104.
            SizedBox(
              height: MediaQuery.of(context).size.height * 7 / 104,
              child: GameTopBar(
                palette: palette,
                color: palette.fonce,
                // Le plateau garde le sens qu'il avait dans la partie : le
                // retourner ici ferait perdre la position de vue.
                onFlip: () {},
                pauseLabel: '<<',
                onPause: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(S(10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _entete(),
                    SizedBox(height: S(8)),
                    AspectRatio(
                      // Un plateau dessine `kExtRows` rangées de haut : les
                      // huit jouables, plus les deux zones de ralliement de
                      // l'Héritier. Un CARRÉ les faisait déborder d'un
                      // huitième de largeur en haut et en bas — peintes
                      // par-dessus les textes voisins, et hors de la boîte,
                      // donc hors de portée du doigt : Flutter arrête le test
                      // de contact aux bords d'un widget, quoi qu'il peigne
                      // au-delà.
                      //
                      // `GameLayout` résout la même chose autrement, en posant
                      // le plateau dans une pile par-dessus une place
                      // réservée. Ici l'écran défile : on lui donne simplement
                      // la place qu'il dessine.
                      aspectRatio: kCols / kExtRows,
                      child: GameBoardView(
                        board: _jeu.board,
                        palette: palette,
                        flipped: widget.flipped,
                        onTapCell: _onTapCell,
                        selected: _jeu.selected,
                        groupSelection: _jeu.groupSelection,
                        highlighted: _jeu.availablePushCells.toSet(),
                        fuguedHeirs: _jeu.fuguedHeirs,
                        pieceTheme: axes.pieces,
                        boardTheme: axes.board,
                        slides: slides,
                        slideJumpPath: slideJumpPath,
                        slideToken: slideToken,
                        slideDuration: slideDuration,
                      ),
                    ),
                    SizedBox(height: S(8)),
                    _ligneEnCours(palette),
                    if (_refus != null)
                      _message(_refus!, palette, alerte: true),
                    SizedBox(height: S(8)),
                    _touches(palette),
                    SizedBox(height: S(12)),
                    _variantes(palette),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// À qui le prochain coup, et ce qu'on attend de nous.
  Widget _entete() {
    final String titre;
    if (!_plan.peutEnAjouter) {
      titre = T('Six variantes préparées : c\'est le maximum.');
    } else if (_methode != null) {
      titre = T('Ce coup termine la partie : la variante s\'arrête ici.');
    } else if (_ligne.length >= kPremoveMaxCoups) {
      titre = T('Six demi-coups : la variante s\'arrête ici.');
    } else if (_aNous) {
      titre = T('Votre réponse');
    } else {
      titre = '${T('Le coup de')} ${widget.game.opponent}';
    }
    // Rien d'autre que le titre : l'explication tenait sur deux lignes
    // au-dessus du plateau, et il n'y a pas la place.
    return Text(
      titre,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white,
        fontSize: SF(17),
        fontWeight: FontWeight.bold,
      ),
    );
  }

  /// La variante en cours de composition, demi-coup par demi-coup.
  Widget _ligneEnCours(ThemePalette palette) {
    if (_ligne.isEmpty) {
      return _message(
        '${T('Jouez le coup que vous attendez de')} ${widget.game.opponent}.',
        palette,
      );
    }
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: S(6),
      children: [
        for (var i = 0; i < _ligne.length; i++)
          _pastille(
            _ligne[i],
            // Les nôtres se distinguent des siens : c'est la seule chose
            // qu'il faut pouvoir lire d'un coup d'œil.
            mienne: premoveEstANous(i),
            palette: palette,
          ),
      ],
    );
  }

  Widget _pastille(
    String notation, {
    required bool mienne,
    required ThemePalette palette,
  }) => Container(
    padding: EdgeInsets.symmetric(horizontal: S(8), vertical: S(3)),
    decoration: BoxDecoration(
      color: mienne ? palette.clair : palette.fonceDim,
      borderRadius: BorderRadius.circular(S(6)),
    ),
    child: Text(
      notation,
      style: TextStyle(
        color: mienne ? Colors.black : Colors.white,
        fontSize: SF(13),
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  Widget _message(String texte, ThemePalette palette, {bool alerte = false}) =>
      Padding(
        padding: EdgeInsets.symmetric(vertical: S(4)),
        child: Text(
          texte,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: alerte ? palette.clair : palette.clairDim,
            fontSize: SF(13),
            fontWeight: alerte ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );

  Widget _touches(ThemePalette palette) => Row(
    children: [
      Expanded(
        child: FugaButton(
          text: T('Défaire'),
          onPressed: _ligne.isEmpty || _envoi ? null : _defaire,
        ),
      ),
      SizedBox(width: S(8)),
      Expanded(
        child: FugaButton(
          text: T('Garder la variante'),
          onPressed: _enregistrable && !_envoi ? _garder : null,
        ),
      ),
    ],
  );

  /// Les variantes déjà préparées, et de quoi en retirer une.
  Widget _variantes(ThemePalette palette) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '${T('Variantes préparées')} : '
        '${_plan.variantes.length} / $kPremoveMaxVariantes',
        style: TextStyle(
          color: Colors.white,
          fontSize: SF(15),
          fontWeight: FontWeight.bold,
        ),
      ),
      SizedBox(height: S(6)),
      for (var i = 0; i < _plan.variantes.length; i++)
        Padding(
          padding: EdgeInsets.only(bottom: S(4)),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: S(5),
                  runSpacing: S(3),
                  children: [
                    for (var k = 0; k < _plan.variantes[i].coups.length; k++)
                      _pastille(
                        _plan.variantes[i].coups[k],
                        mienne: premoveEstANous(k),
                        palette: palette,
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _envoi ? null : () => _oublier(i),
                icon: const Icon(Icons.close, color: Colors.white),
                iconSize: SF(20),
                tooltip: T('Retirer'),
              ),
            ],
          ),
        ),
      SizedBox(height: S(6)),
      FugaButton(
        // Même quand il n'y a plus aucune variante : c'est ainsi qu'on annule
        // tout ce qu'on avait préparé.
        text: _plan.estVide ? T('Ne rien préjouer') : T('Armer'),
        color: palette.fonce,
        onPressed: _envoi ? null : _terminer,
      ),
    ],
  );
}
