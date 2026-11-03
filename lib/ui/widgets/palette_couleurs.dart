/// LA PALETTE : toutes les couleurs, derrière un seul bouton.
///
/// Nino : « il doit y avoir un seul bouton couleur qui donne accès à une
/// palette complète. Si on sélectionne une couleur pendant qu'il y a un cadre
/// bleu (objet sélectionné), ça change la couleur de l'objet en question.
/// Autrement, ça change la couleur de nos actions suivantes (texte, tampon,
/// dessin). » Puis : « la palette doit pouvoir passer de carreaux à nuance
/// avec un bouton. »
///
/// Ce fichier ne connaît que le choix d'une couleur ; ce qu'on en fait —
/// repeindre ce qui est sélectionné, ou régler l'encre à venir — regarde
/// l'éditeur.
///
/// ## Deux façons de choisir, une touche pour passer de l'une à l'autre
///
/// **Les carreaux** : trente pastilles — douze teintes en vif, les mêmes en
/// sombre, et six gris du blanc au noir. Un appui, c'est choisi. C'est ce
/// qu'on veut neuf fois sur dix : viser une pastille ne demande aucune
/// adresse.
///
/// **Les nuances** : un dégradé continu, la teinte en largeur, le clair et le
/// sombre en hauteur. On y promène le doigt, la couleur suit, et une touche
/// la valide. C'est ce qu'il faut quand on cherche le bleu exact du ciel de
/// la photo — un carreau ne l'aura jamais.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../scale.dart';
import 'fuga_button.dart';
import 'fuga_popup.dart';

/// Les gris, du blanc au noir : ils se lisent sur tout.
const List<Color> kGrisDeLaPalette = [
  Colors.white,
  Color(0xFFCCCCCC),
  Color(0xFF999999),
  Color(0xFF666666),
  Color(0xFF333333),
  Colors.black,
];

/// Les teintes vives, puis les mêmes en sombre, puis les gris.
List<Color> construisLaPalette() {
  final vives = <Color>[];
  final sombres = <Color>[];
  for (var i = 0; i < 12; i++) {
    final teinte = i * 30.0;
    vives.add(HSVColor.fromAHSV(1, teinte, 0.95, 1).toColor());
    sombres.add(HSVColor.fromAHSV(1, teinte, 1, 0.55).toColor());
  }
  return [...vives, ...sombres, ...kGrisDeLaPalette];
}

/// La palette entière, construite une fois.
final List<Color> kPaletteComplete = construisLaPalette();

/// Combien de pastilles par rangée.
const int kPastillesParRangee = 6;

/// L'écart entre deux pastilles, et la marge autour de la grille.
double get _ecartDesCarreaux => S(6);
double get _margeDesCarreaux => S(4);

/// LA HAUTEUR DE LA GRILLE, pour une largeur donnée.
///
/// Nino : « le truc de nuances doit faire la même taille que celui de
/// carreaux, comme ça il sera plus simple d'utilisation. » Les deux modes
/// occupent donc exactement la même boîte — on ne vise pas mieux dans un
/// dégradé étroit, et le popup ne change pas de taille quand on bascule.
///
/// Elle se calcule plutôt que de se deviner : c'est la grille qui commande,
/// et elle dépend de la largeur qu'on lui donne.
double hauteurDesCarreaux(double largeur) {
  final dispo = largeur - 2 * _margeDesCarreaux;
  final cote =
      (dispo - _ecartDesCarreaux * (kPastillesParRangee - 1)) /
      kPastillesParRangee;
  final rangees = (kPaletteComplete.length / kPastillesParRangee).ceil();
  return cote * rangees + _ecartDesCarreaux * (rangees - 1);
}

/// Ouvre la palette. Rend la couleur choisie, ou nul si l'on a refermé.
Future<Color?> choisirUneCouleur(
  BuildContext context, {
  required Color actuelle,
}) => showFugaPopup<Color>(
  context,
  widthFactor: 0.9,
  heightFactor: 0.72,
  dismissible: true,
  rows: [
    (0.1, popupText(T('Couleur'), size: 17, bold: true)),
    (0.1, CorpsDeLaPalette(actuelle: actuelle)),
    (
      kTouchRow,
      Row(
        children: [
          Expanded(
            child: FugaButton(
              text: T('Fermer'),
              color: kGrisTouche,
              fontSize: SF(15),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    ),
  ],
);

/// Le corps de la palette : la touche qui change de mode, et le mode.
///
/// Un widget à état, parce que la touche change ce qu'on voit sans refermer
/// le popup — et le popup, lui, ne construit ses lignes qu'une fois.
class CorpsDeLaPalette extends StatefulWidget {
  const CorpsDeLaPalette({super.key, required this.actuelle});

  final Color actuelle;

  @override
  State<CorpsDeLaPalette> createState() => _CorpsDeLaPaletteState();
}

class _CorpsDeLaPaletteState extends State<CorpsDeLaPalette> {
  bool _nuances = false;
  late Color _couleur = widget.actuelle;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        height: touchHeight() * 0.74,
        child: FugaButton(
          enfant: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _nuances ? Icons.grid_view : Icons.gradient,
                size: SF(16),
                color: Colors.white,
              ),
              SizedBox(width: S(6)),
              Text(
                _nuances ? T('Carreaux') : T('Nuances'),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: SF(14),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          color: kGrisTouche,
          height: double.infinity,
          onPressed: () => setState(() => _nuances = !_nuances),
        ),
      ),
      SizedBox(height: S(8)),
      // La même boîte pour les deux modes, mesurée sur la grille.
      LayoutBuilder(
        builder: (context, boite) {
          final hauteur = hauteurDesCarreaux(boite.maxWidth);
          return _nuances ? _lesNuances(hauteur) : _lesCarreaux(hauteur);
        },
      ),
    ],
  );

  Widget _lesCarreaux(double hauteur) => SizedBox(
    height: hauteur,
    child: GridView.count(
      // LE POPUP DÉFILE DÉJÀ : sa colonne ne borne pas la hauteur de ses
      // lignes, et une grille qui veut s'étendre à l'infini s'y plaint. On
      // lui donne donc la hauteur calculée, et elle ne défile pas pour son
      // compte.
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: kPastillesParRangee,
      mainAxisSpacing: _ecartDesCarreaux,
      crossAxisSpacing: _ecartDesCarreaux,
      padding: EdgeInsets.symmetric(horizontal: _margeDesCarreaux),
      children: [
        for (final c in kPaletteComplete)
          _Pastille(
            couleur: c,
            choisie: c.toARGB32() == widget.actuelle.toARGB32(),
            onTap: () => Navigator.of(context).pop(c),
          ),
      ],
    ),
  );

  Widget _lesNuances(double hauteur) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        // LA MÊME BOÎTE QUE LES CARREAUX : grande, donc facile à viser.
        height: hauteur,
        width: double.infinity,
        child: Nuancier(
          couleur: _couleur,
          onChange: (c) => setState(() => _couleur = c),
        ),
      ),
      SizedBox(height: S(8)),
      Row(
        children: [
          Container(
            width: touchHeight() * 0.62,
            height: touchHeight() * 0.62,
            decoration: BoxDecoration(
              color: _couleur,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: S(2)),
            ),
          ),
          SizedBox(width: S(8)),
          Expanded(
            child: SizedBox(
              height: touchHeight() * 0.74,
              child: FugaButton(
                text: T('Choisir'),
                color: _couleur,
                textColor: _couleur.computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white,
                fontSize: SF(15),
                height: double.infinity,
                onPressed: () => Navigator.of(context).pop(_couleur),
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

/// Le dégradé continu : la teinte en largeur, le clair et le sombre en
/// hauteur.
///
/// En haut, du blanc vers la teinte pure ; en bas, de la teinte pure vers le
/// noir. Tout ce qu'un écran sait montrer tient donc dans ce rectangle, et le
/// doigt y va directement — pas de curseur à régler l'un après l'autre.
class Nuancier extends StatelessWidget {
  const Nuancier({super.key, required this.couleur, required this.onChange});

  final Color couleur;
  final ValueChanged<Color> onChange;

  /// La couleur d'un point du rectangle, en fractions.
  static Color couleurEn(Offset f) {
    final teinte = (f.dx.clamp(0.0, 1.0)) * 360;
    final y = f.dy.clamp(0.0, 1.0);
    // Au-dessus du milieu : du blanc vers la teinte. En dessous : de la
    // teinte vers le noir.
    final saturation = y <= 0.5 ? y * 2 : 1.0;
    final valeur = y <= 0.5 ? 1.0 : 1 - (y - 0.5) * 2;
    return HSVColor.fromAHSV(1, teinte % 360, saturation, valeur).toColor();
  }

  /// Où se trouve une couleur dans le rectangle — pour y poser la cible.
  static Offset placeDe(Color c) {
    final hsv = HSVColor.fromColor(c);
    final y = hsv.value < 1 ? 0.5 + (1 - hsv.value) / 2 : hsv.saturation / 2;
    return Offset(hsv.hue / 360, y.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, boite) {
      void suit(Offset local) => onChange(
        couleurEn(
          Offset(local.dx / boite.maxWidth, local.dy / boite.maxHeight),
        ),
      );
      return GestureDetector(
        onTapDown: (d) => suit(d.localPosition),
        onPanUpdate: (d) => suit(d.localPosition),
        child: CustomPaint(
          painter: _PeintreDesNuances(placeDe(couleur)),
          size: boite.biggest,
        ),
      );
    },
  );
}

class _PeintreDesNuances extends CustomPainter {
  const _PeintreDesNuances(this.cible);

  /// La position de la couleur en main, en fractions.
  final Offset cible;

  @override
  void paint(Canvas canvas, Size size) {
    final cadre = Offset.zero & size;
    final arrondi = RRect.fromRectAndRadius(cadre, Radius.circular(S(8)));
    canvas.save();
    canvas.clipRRect(arrondi);

    // LES TEINTES, en largeur.
    final teintes = <Color>[
      for (var i = 0; i <= 12; i++)
        HSVColor.fromAHSV(1, (i * 30) % 360, 1, 1).toColor(),
    ];
    canvas.drawRect(
      cadre,
      Paint()..shader = LinearGradient(colors: teintes).createShader(cadre),
    );

    // LE BLANC AU-DESSUS, LE NOIR EN DESSOUS, et la teinte pure au milieu.
    canvas.drawRect(
      cadre,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0x00FFFFFF), Colors.black],
          stops: [0, 0.5, 1],
        ).createShader(cadre),
    );
    canvas.restore();

    // LA CIBLE : deux ronds, un blanc et un noir, pour se voir sur tout.
    final ou = Offset(cible.dx * size.width, cible.dy * size.height);
    canvas.drawCircle(
      ou,
      S(9),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = S(3)
        ..color = Colors.white,
    );
    canvas.drawCircle(
      ou,
      S(9),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = S(1)
        ..color = Colors.black,
    );
  }

  @override
  bool shouldRepaint(_PeintreDesNuances vieux) => vieux.cible != cible;
}

/// Une pastille de la palette. Celle qui est en main porte un trait blanc.
class _Pastille extends StatelessWidget {
  const _Pastille({
    required this.couleur,
    required this.choisie,
    required this.onTap,
  });

  final Color couleur;
  final bool choisie;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        color: couleur,
        shape: BoxShape.circle,
        border: Border.all(
          color: choisie ? Colors.white : Colors.black54,
          width: choisie ? S(3) : S(1),
        ),
      ),
    ),
  );
}
