/// Composer une position de départ, pour un défi par correspondance.
///
/// Un plateau vide, une ligne de pièces à poser, et deux règles :
///
///  1. un Héritier par camp, ni plus ni moins ;
///  2. des pièces carrées capables de bouger **des deux côtés** — une carrée
///     ne bouge que si elle en touche une autre, sans quoi la position serait
///     nulle d'entrée.
///
/// En dehors de cela, on pose ce qu'on veut où on veut : dix Gardes d'un côté,
/// c'est permis. Les deux règles sont dans `lib/engine/fug.dart` ; cet écran
/// ne fait que les appliquer, et dire lesquelles quand il refuse.
///
/// La pièce choisie le RESTE : on en pose plusieurs d'affilée sans avoir à la
/// reprendre à chaque case.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/board.dart';
import '../../engine/fug.dart';
import '../../engine/piece.dart';
import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import '../widgets/fuga_background.dart';
import '../widgets/fuga_button.dart';
import '../widgets/game_board_view.dart';
import '../widgets/game_top_bar.dart';
import '../widgets/piece_tile.dart';

/// Gris pile entre le noir et le blanc : le fond de la touche du trait, pour
/// que « Blancs » et « Noirs » s'y lisent tous les deux.
const Color kGrisMedian = Color.fromRGBO(128, 128, 128, 1);

/// L'ordre de la ligne de pièces : du plus lourd au plus léger.
const List<PieceType> kOrdreDesPieces = [
  PieceType.heritier,
  PieceType.nurse,
  PieceType.chevalier,
  PieceType.garde,
  PieceType.soldat,
];

class PositionComposerScreen extends StatefulWidget {
  const PositionComposerScreen({super.key, this.depart, this.turn});

  /// Position de départ du composeur. Nulle : un plateau vide.
  final Board? depart;
  final Camp? turn;

  @override
  State<PositionComposerScreen> createState() => _PositionComposerScreenState();
}

class _PositionComposerScreenState extends State<PositionComposerScreen> {
  late Board _board = widget.depart?.clone() ?? Board.empty();
  late Camp _trait = widget.turn ?? Camp.blanc;

  /// Le camp de la ligne de pièces — la bascule le change.
  Camp _campDesPieces = Camp.blanc;

  /// La pièce en main. Nulle : toucher une case l'efface au lieu d'en poser.
  PieceType? _enMain = PieceType.heritier;

  final TextEditingController _colle = TextEditingController();
  String? _erreurCollage;

  @override
  void dispose() {
    _colle.dispose();
    super.dispose();
  }

  void _toucheCase(Cell cell) {
    if (!cell.onBoard) return;
    setState(() {
      final enMain = _enMain;
      _board.setCell(
        cell,
        enMain == null ? null : Piece.of(enMain, _campDesPieces),
      );
    });
  }

  /// Coller un code `.fug` crée la position directement ; on peut ensuite la
  /// retoucher avant d'envoyer le défi.
  void _collerFug() {
    final lu = fugLire(_colle.text);
    if (lu.position == null) {
      setState(() => _erreurCollage = _texteErreur(lu));
      return;
    }
    setState(() {
      _board = lu.position!.board;
      _trait = lu.position!.turn;
      _erreurCollage = null;
      _colle.clear();
    });
  }

  String _texteErreur(FugLecture lu) => switch (lu.erreur!) {
    FugErreur.vide => T('Collez un code de position.'),
    FugErreur.traitInconnu => T(
      'La première ligne dit qui est au trait : B pour les Blancs, N pour les '
      'Noirs.',
    ),
    FugErreur.rangees => T('Il faut huit rangées, une par ligne.'),
    FugErreur.colonnes => T('Chaque rangée compte sept cases.'),
    FugErreur.lettre => T(
      'Lettres acceptées : h, n, c, g, s — majuscule pour les Noirs — et - '
      'pour une case vide.',
    ),
  };

  /// Valider la position, ou dire ce qui lui manque.
  Future<void> _valider() async {
    final refus = fugRefus(_board);
    if (refus == null) {
      Navigator.of(context).pop((board: _board, turn: _trait));
      return;
    }
    final palette = paletteOf(Settings.instance.themeAxes.general);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.fonce,
        title: Text(
          T('Cette position ne peut pas se jouer'),
          style: TextStyle(color: Colors.white, fontSize: SF(17)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ce qui cloche EN PREMIER, puis les deux règles : savoir qu'on a
            // tort sans savoir pourquoi n'aide personne.
            Text(
              switch (refus) {
                FugRefus.heritier => T(
                  'Il manque un Héritier, ou il y en a plusieurs.',
                ),
                FugRefus.carreesBloquees => T(
                  'Un camp n\'a aucune pièce carrée capable de bouger.',
                ),
              },
              style: TextStyle(
                color: palette.clair,
                fontSize: SF(15),
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: S(10)),
            Text(
              T(
                'Une position jouable demande deux choses :\n\n'
                '• un Héritier dans chaque camp, ni plus ni moins ;\n'
                '• dans chaque camp, au moins une pièce carrée qui touche une '
                'autre pièce carrée — une carrée isolée ne peut pas bouger, et '
                'la partie serait nulle d\'entrée.',
              ),
              style: TextStyle(color: Colors.white, fontSize: SF(14)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(T('Ok')),
          ),
        ],
      ),
    );
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
            SizedBox(
              height: MediaQuery.of(context).size.height * 7 / 104,
              child: GameTopBar(
                palette: palette,
                color: palette.fonce,
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
                    AspectRatio(
                      // La place que le plateau DESSINE : huit rangées
                      // jouables plus les deux zones de ralliement. Un carré
                      // les ferait déborder, et le doigt ne les atteindrait
                      // plus.
                      aspectRatio: kCols / kExtRows,
                      child: GameBoardView(
                        board: _board,
                        palette: palette,
                        flipped: true,
                        onTapCell: _toucheCase,
                        pieceTheme: axes.pieces,
                        boardTheme: axes.board,
                      ),
                    ),
                    SizedBox(height: S(8)),
                    _ligneDesPieces(palette, axes.pieces),
                    SizedBox(height: S(8)),
                    _cadreDeCollage(palette),
                    SizedBox(height: S(10)),
                    Row(
                      children: [
                        Expanded(
                          child: FugaButton(
                            text: T('Vider'),
                            onPressed: () => setState(() {
                              _board = Board.empty();
                            }),
                          ),
                        ),
                        SizedBox(width: S(8)),
                        Expanded(
                          child: FugaButton(
                            text: T('Position standard'),
                            onPressed: () => setState(() {
                              _board = Board.initial();
                            }),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: S(8)),
                    FugaButton(
                      text: T('Valider la position'),
                      color: palette.clair,
                      textColor: Colors.black,
                      onPressed: _valider,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// La ligne de pièces, la bascule de couleur, et la touche du trait.
  Widget _ligneDesPieces(ThemePalette palette, String? pieceTheme) => Row(
    children: [
      for (final type in kOrdreDesPieces) ...[
        Expanded(
          child: PieceTile(
            piece: Piece.of(type, _campDesPieces),
            palette: palette,
            pieceTheme: pieceTheme,
            selected: _enMain == type,
            onTap: () => setState(() => _enMain = type),
          ),
        ),
        SizedBox(width: S(3)),
      ],
      // La gomme : rien en main, et toucher une case la vide.
      Expanded(
        child: _carre(
          choisi: _enMain == null,
          palette: palette,
          onTap: () => setState(() => _enMain = null),
          child: Icon(
            Icons.backspace_outlined,
            color: Colors.white,
            size: SF(18),
          ),
        ),
      ),
      SizedBox(width: S(3)),
      // La bascule de couleur de la ligne : des pièces blanches aux noires.
      Expanded(
        child: _carre(
          choisi: false,
          palette: palette,
          onTap: () => setState(
            () => _campDesPieces = _campDesPieces == Camp.blanc
                ? Camp.noir
                : Camp.blanc,
          ),
          child: Icon(
            Icons.swap_horiz,
            color: _campDesPieces == Camp.blanc ? Colors.white : Colors.black,
            size: SF(20),
          ),
        ),
      ),
      SizedBox(width: S(6)),
      // « Trait aux Blancs / Noirs », sur fond gris médian pour que les deux
      // mots s'y lisent.
      Expanded(flex: 3, child: _toucheDuTrait()),
    ],
  );

  Widget _carre({
    required bool choisi,
    required ThemePalette palette,
    required VoidCallback onTap,
    required Widget child,
  }) => AspectRatio(
    aspectRatio: 1,
    child: Material(
      color: choisi
          ? palette.clair.withValues(alpha: 0.35)
          : (_campDesPieces == Camp.blanc ? kBarButtonDark : Colors.white24),
      borderRadius: BorderRadius.circular(S(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(S(8)),
        onTap: onTap,
        child: Center(child: child),
      ),
    ),
  );

  Widget _toucheDuTrait() => Material(
    color: kGrisMedian,
    borderRadius: BorderRadius.circular(S(8)),
    child: InkWell(
      borderRadius: BorderRadius.circular(S(8)),
      onTap: () => setState(
        () => _trait = _trait == Camp.blanc ? Camp.noir : Camp.blanc,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: S(4), horizontal: S(4)),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                T('Trait aux'),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: SF(11),
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _trait == Camp.blanc ? T('Blancs') : T('Noirs'),
                style: TextStyle(
                  // Le mot porte sa propre couleur : c'est ce qui rend la
                  // touche lisible d'un coup d'œil.
                  color: _trait == Camp.blanc ? Colors.white : Colors.black,
                  fontSize: SF(15),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _cadreDeCollage(ThemePalette palette) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _colle,
              maxLines: 2,
              style: TextStyle(color: Colors.white, fontSize: SF(12)),
              decoration: InputDecoration(
                hintText: T('Coller un code .fug'),
                hintStyle: TextStyle(color: palette.clairDim, fontSize: SF(12)),
                filled: true,
                fillColor: kBarButtonDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(S(8)),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
            ),
          ),
          SizedBox(width: S(6)),
          SizedBox(
            width: S(92),
            child: FugaButton(
              text: T('Coller'),
              onPressed: () async {
                // Le presse-papier d'abord : on vient de copier une position
                // ailleurs, inutile de la coller à la main.
                if (_colle.text.trim().isEmpty) {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  _colle.text = data?.text ?? '';
                }
                _collerFug();
              },
            ),
          ),
        ],
      ),
      if (_erreurCollage != null)
        Padding(
          padding: EdgeInsets.only(top: S(4)),
          child: Text(
            _erreurCollage!,
            style: TextStyle(color: palette.clair, fontSize: SF(12)),
          ),
        ),
    ],
  );
}
