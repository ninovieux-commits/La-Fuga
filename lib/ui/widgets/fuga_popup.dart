/// Popup aux proportions de Kivy — portage de `Popup(size_hint=(w, h))`.
///
/// Kivy ne donne jamais de taille fixe à un popup : il occupe une fraction de
/// l'écran, et ses enfants se partagent sa hauteur par `size_hint_y`. Une
/// boîte de dialogue garde donc la même allure d'un téléphone à l'autre.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'fuga_button.dart';

/// Une ligne du popup : sa part de la hauteur (le `size_hint_y` de Kivy) et
/// ce qu'elle contient.
///
/// ## La part ne gonfle plus la ligne
///
/// Les touches étant servies à épaisseur fixe, les lignes à part se
/// partageaient tout le reste de la hauteur demandée — et comme leurs parts
/// étaient renormalisées entre elles, elles l'avalaient en entier, quelle que
/// soit leur somme. Un popup de trois lignes courtes occupait 40 % de
/// l'écran, dont les deux tiers de vide. Nino : « aucune raison pour que tous
/// ces popups soient aussi gros, y a plein d'espace vide. »
///
/// Une ligne prend donc maintenant la hauteur qu'elle DEMANDE, et le popup la
/// somme. La part ne sert plus qu'à distinguer une ligne de touches
/// ([kTouchRow]) d'une ligne ordinaire ; on la garde telle quelle, parce
/// qu'elle dit encore l'intention de Kivy en relisant le portage.
typedef PopupRow = (double, Widget);

/// Part d'une ligne de touches : son épaisseur est celle d'une touche, la même
/// que partout ailleurs dans l'appli.
///
/// Une part en fraction de la hauteur du popup donnait des touches d'une
/// épaisseur différente dans chaque popup — et différente de celles du menu.
/// Le popup s'allonge s'il le faut : une touche ne se laisse pas comprimer.
const double kTouchRow = -1;

/// Ouvre un popup occupant [widthFactor] × [heightFactor] de l'écran.
Future<T?> showFugaPopup<T>(
  BuildContext context, {
  required double widthFactor,
  required double heightFactor,
  required List<PopupRow> rows,
  String title = '',
  double spacing = 8,
  double padding = 16,
  bool dismissible = false,
}) => showDialog<T>(
  context: context,
  barrierDismissible: dismissible,
  builder: (context) => FugaPopup(
    widthFactor: widthFactor,
    heightFactor: heightFactor,
    rows: rows,
    title: title,
    spacing: spacing,
    padding: padding,
  ),
);

class FugaPopup extends StatelessWidget {
  const FugaPopup({
    super.key,
    required this.widthFactor,
    required this.heightFactor,
    required this.rows,
    this.title = '',
    this.spacing = 8,
    this.padding = 16,
  });

  /// Fractions de l'écran — le `size_hint` du `Popup`.
  final double widthFactor;
  final double heightFactor;

  /// Titre du bandeau. Vide : pas de bandeau, comme `title=""`.
  final String title;

  final List<PopupRow> rows;

  /// `spacing` et `padding` du `BoxLayout` du contenu, en pixels de
  /// référence.
  final double spacing;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);

    // RESPIRATION VERTICALE, MESURÉE SUR LA HAUTEUR. Les marges d'un popup se
    // lisent le long de sa hauteur : les prendre en `S` — un pourcentage de
    // la LARGEUR — donnait 4 px d'écart entre deux lignes sur un téléphone.
    // La règle du fichier `scale.dart` : ce qui se lit comme une bande se
    // mesure sur la hauteur.
    final ecart = touchHeight() * 0.32;
    final marge = touchHeight() * 0.40;

    final titleHeight = title.isEmpty ? 0.0 : SF(18) * 1.8;

    return Dialog(
      backgroundColor: kFugaGrey,
      insetPadding: EdgeInsets.zero,
      // Le trait noir des touches fait aussi le tour des popups. Celui-ci
      // impose sa forme, il ne la prend donc pas du thème : on l'y remet.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(S(14)),
        side: kTraitDeTouche,
      ),
      child: ConstrainedBox(
        // [heightFactor] est un PLAFOND, pas une hauteur. Le popup prend ce
        // que son contenu demande et pas un pixel de plus.
        constraints: BoxConstraints(maxHeight: screen.height * heightFactor),
        child: SizedBox(
          width: screen.width * widthFactor,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title.isNotEmpty)
                SizedBox(
                  height: titleHeight,
                  child: Center(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: SF(18),
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              // Au plafond, le contenu DÉFILE plutôt que de déborder : une
              // traduction longue ne doit pas peindre par-dessus le bord.
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: S(padding),
                    vertical: marge,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0) SizedBox(height: ecart),
                        if (rows[i].$1 < 0)
                          SizedBox(
                            height: touchHeight(),
                            width: double.infinity,
                            child: rows[i].$2,
                          )
                        else
                          SizedBox(width: double.infinity, child: rows[i].$2),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Texte centré d'un popup, à la taille de référence donnée.
Widget popupText(
  String text, {
  required double size,
  Color color = Colors.white,
  bool bold = false,
  bool italic = false,
}) => Center(
  child: Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(
      fontSize: SF(size),
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      color: color,
    ),
  ),
);

/// « Oui » ou « Non », et rien d'autre.
///
/// La confirmation d'un geste qu'on ne peut pas défaire : abandonner, demander
/// la nulle, repartir en laissant ce qu'on avait préparé. Une seule, la même
/// partout — chaque écran avait la sienne, et deux d'entre elles étaient mot
/// pour mot la même.
Future<bool> confirmerFuga(
  BuildContext context, {
  required ThemePalette palette,
  required String titre,
  String message = '',
}) async {
  final ok = await showFugaPopup<bool>(
    context,
    widthFactor: 0.82,
    heightFactor: message.isEmpty ? 0.34 : 0.42,
    rows: [
      (0.42, popupText(titre, size: 17, bold: true)),
      if (message.isNotEmpty)
        (
          0.25,
          popupText(
            message,
            size: 13,
            color: const Color.fromRGBO(217, 217, 217, 1),
          ),
        ),
      (
        kTouchRow,
        Row(
          children: [
            Expanded(
              child: FugaButton(
                text: T('Non'),
                color: kGrisTouche,
                fontSize: SF(16),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
            SizedBox(width: S(8)),
            Expanded(
              child: FugaButton(
                text: T('Oui'),
                color: palette.fonce,
                fontSize: SF(16),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        ),
      ),
    ],
  );
  return ok == true;
}
