/// Lecteur `.fug` : on colle une position, elle s'ouvre.
///
/// Le pendant du lecteur `.nmc`, pour l'autre format. Le `.nmc` décrit une
/// PARTIE et s'ouvre en relecture, coup par coup ; le `.fug` décrit une
/// POSITION, et il n'y a rien à rejouer. Il s'ouvre donc là où une position
/// s'examine : en analyse, où l'on peut jouer les deux camps, remonter, et
/// reprendre la position contre Deep Grey — exactement ce que le lecteur
/// `.nmc` finit par offrir.
///
/// On accepte toute position LISIBLE, même injouable. Les deux contraintes —
/// un Héritier par camp, des carrées qui bougent — valent pour composer un
/// défi, pas pour regarder un plateau : refuser d'afficher une position à
/// deux pièces n'aiderait personne.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/fug.dart';
import '../../engine/piece.dart';
import '../../game/clock.dart';
import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import '../widgets/fuga_background.dart';
import '../widgets/fuga_button.dart';
import '../widgets/fuga_header.dart';
import 'game_screen.dart';

class FugReaderScreen extends StatefulWidget {
  const FugReaderScreen({super.key});

  @override
  State<FugReaderScreen> createState() => _FugReaderScreenState();
}

class _FugReaderScreenState extends State<FugReaderScreen> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _lire() async {
    final lu = fugLire(_input.text);
    if (lu.position == null) {
      await _erreur(lu);
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          cadence: Cadence.zen,
          aiCamp: null,
          initialBoard: lu.position!.board,
          initialTurn: lu.position!.turn,
          analysis: true,
          // Les Blancs en bas quand ils ont le trait, comme au départ d'une
          // partie.
          initialFlipped: lu.position!.turn == Camp.blanc,
          themeName: Settings.instance.themeAxes.general,
        ),
      ),
    );
  }

  /// Dire CE QUI ne va pas, et où : « invalide » tout court n'aide personne à
  /// corriger huit lignes de sept caractères.
  Future<void> _erreur(FugLecture lu) {
    final quoi = switch (lu.erreur!) {
      FugErreur.vide => T('Collez une position au format .fug.'),
      FugErreur.traitInconnu => T(
        'La première ligne dit qui est au trait : B pour les Blancs, N pour '
        'les Noirs.',
      ),
      FugErreur.rangees => T('Il faut huit rangées, une par ligne.'),
      FugErreur.colonnes => T('Chaque rangée compte sept cases.'),
      FugErreur.lettre => T(
        'Lettres acceptées : h, n, c, g, s — majuscule pour les Noirs — et - '
        'pour une case vide.',
      ),
    };
    final ou = lu.ligne == null ? '' : '\n\n${T('Ligne')} ${lu.ligne}.';
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kFugaGrey,
        title: Text(T('Erreur'), style: const TextStyle(color: Colors.white)),
        content: Text(
          '$quoi$ou',
          style: TextStyle(color: Colors.white, fontSize: SF(13)),
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
    final palette = paletteOf(Settings.instance.themeAxes.general);
    return FugaScaffold(
      body: SafeArea(
        child: Column(
          children: [
            FugaHeader(
              back: T('< Retour'),
              title: T('Lecteur fug'),
              titleSize: 32,
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(S(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: SF(13),
                          // Huit lignes de sept caractères ne s'alignent qu'en
                          // chasse fixe : c'est ce qui rend le plateau
                          // reconnaissable dans le texte.
                          fontFamily: 'monospace',
                        ),
                        decoration: InputDecoration(
                          hintText: 'B\nsgshgsg\ngnnnnns\n…',
                          hintStyle: TextStyle(
                            color: palette.clairDim,
                            fontSize: SF(13),
                            fontFamily: 'monospace',
                          ),
                          filled: true,
                          fillColor: const Color.fromRGBO(38, 38, 38, 1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(S(10)),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: S(12)),
                    Row(
                      children: [
                        Expanded(
                          child: FugaButton(
                            text: T('Coller'),
                            onPressed: () async {
                              final data = await Clipboard.getData(
                                Clipboard.kTextPlain,
                              );
                              if (data?.text != null) {
                                setState(() => _input.text = data!.text!);
                              }
                            },
                          ),
                        ),
                        SizedBox(width: S(10)),
                        Expanded(
                          child: FugaButton(
                            text: T('Lire'),
                            color: palette.clair,
                            textColor: Colors.black,
                            onPressed: _lire,
                          ),
                        ),
                      ],
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
}
