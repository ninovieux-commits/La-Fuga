/// Popup aux proportions de Kivy — portage de `Popup(size_hint=(w, h))`.
///
/// Kivy ne donne jamais de taille fixe à un popup : il occupe une fraction de
/// l'écran, et ses enfants se partagent sa hauteur par `size_hint_y`. Une
/// boîte de dialogue garde donc la même allure d'un téléphone à l'autre.
library;

import 'package:flutter/material.dart';

import '../scale.dart';
import 'fuga_button.dart';

/// Une ligne du popup : sa part de la hauteur (le `size_hint_y` de Kivy) et
/// ce qu'elle contient. Une part nulle laisse la ligne prendre sa hauteur
/// naturelle, pour les contenus qu'on ne sait pas mesurer.
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
    final width = screen.width * widthFactor;
    final height = screen.height * heightFactor;

    final titleHeight = title.isEmpty ? 0.0 : SF(18) * 1.8;
    // Ce que le popup dépense avant ses lignes : bandeau, marges, écarts.
    final chrome =
        titleHeight +
        2 * S(padding) +
        S(spacing) * (rows.length - 1).clamp(0, rows.length);

    // Les lignes de touches sont à épaisseur imposée ; les autres se
    // partagent ce qui reste, au prorata de leur part — exactement comme le
    // calcul d'un `BoxLayout` vertical, une fois les touches servies.
    final touches = rows.where((r) => r.$1 < 0).length * touchHeight();
    final parts = rows.fold<double>(0, (a, r) => r.$1 > 0 ? a + r.$1 : a);
    final requestedInner = height - chrome;
    var forParts = requestedInner - touches;
    var boxHeight = height;
    if (forParts < requestedInner * parts) {
      // Pas la place : c'est le popup qui s'allonge, pas les touches qui
      // maigrissent.
      forParts = requestedInner * parts;
      boxHeight = chrome + touches + forParts;
    }

    return Dialog(
      backgroundColor: kFugaGrey,
      insetPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(S(14))),
      child: SizedBox(
        width: width,
        height: boxHeight,
        child: Column(
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
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(S(padding)),
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0) SizedBox(height: S(spacing)),
                      if (rows[i].$1 < 0)
                        SizedBox(
                          height: touchHeight(),
                          width: double.infinity,
                          child: rows[i].$2,
                        )
                      else if (rows[i].$1 == 0)
                        Flexible(child: rows[i].$2)
                      else
                        SizedBox(
                          height: parts <= 0
                              ? 0
                              : forParts * rows[i].$1 / parts,
                          width: double.infinity,
                          child: rows[i].$2,
                        ),
                    ],
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
