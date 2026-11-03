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
import '../../state/settings.dart';
import '../../theme/themes.dart';
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

/// LES SIX TEINTES, dans l'ordre de l'arc-en-ciel.
///
/// Six et non douze : une colonne par teinte, c'est ce qui rend la grille
/// lisible. Pour la teinte exacte qui manque entre deux colonnes, il y a les
/// nuances.
const List<double> kTeintesDeLaPalette = [0, 60, 120, 180, 240, 300];

/// Les quatre degrés d'une teinte, du pâle au sombre.
///
/// (saturation, valeur) — le premier éclaircit, les suivants assombrissent.
const List<(double, double)> kDegresDeLaPalette = [
  (0.35, 1.0),
  (1.0, 1.0),
  (1.0, 0.72),
  (1.0, 0.42),
];

/// LA GRILLE, RANGÉE : une colonne par teinte, une rangée par degré.
///
/// Nino : « je comprends pas la palette couleurs… range-les de façon
/// logique. » Elles étaient rangées par teinte croissante sur deux rangées de
/// six : une colonne mêlait donc du rouge et du cyan, et l'œil n'y trouvait
/// aucune suite. Maintenant on descend dans une colonne pour assombrir, on se
/// déplace de côté pour changer de teinte, et les gris ferment la marche.
List<List<Color>> construisLesRangees() => [
  for (final (saturation, valeur) in kDegresDeLaPalette)
    [
      for (final teinte in kTeintesDeLaPalette)
        HSVColor.fromAHSV(1, teinte, saturation, valeur).toColor(),
    ],
  kGrisDeLaPalette,
];

/// Les rangées fixes — celles qui ne dépendent pas du thème.
final List<List<Color>> kRangeesDeLaPalette = construisLesRangees();

/// La palette fixe, à plat.
final List<Color> kPaletteComplete = [
  for (final rangee in kRangeesDeLaPalette) ...rangee,
];

/// LES COULEURS DU THÈME, la rangée du bas.
///
/// Nino : « rajoute en bas une ligne dans laquelle il y a les couleurs du
/// thème de l'utilisateur. » Ce sont celles de son écran : ses bulles, ses
/// enveloppes, son plateau. Écrire sur une photo avec la couleur de son thème
/// n'est pas une couleur de plus, c'est SA couleur.
List<Color> rangeeDuTheme(ThemePalette theme) => [
  theme.clair,
  theme.clairDim,
  theme.fonce,
  theme.fonceDim,
  theme.board,
  theme.menu,
];

/// Combien de pastilles par rangée.
const int kPastillesParRangee = 6;

/// Le bloc des carreaux, repéré pour les tests : c'est lui qui doit faire la
/// même taille que le nuancier.
const Key cleDesCarreaux = ValueKey('carreaux de la palette');

/// Le carré des nuances et sa barre de teintes, repérés de même.
const Key cleDuNuancier = ValueKey('nuancier de la palette');

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
  final cote = coteDUnCarreau(largeur);
  final rangees = kRangeesDeLaPalette.length + 1; // la rangée du thème
  return cote * rangees +
      _ecartDesCarreaux * (rangees - 1) +
      _hauteurDeLEtiquette +
      _ecartDesCarreaux;
}

/// Le côté d'une pastille, pour une largeur donnée.
double coteDUnCarreau(double largeur) {
  final dispo = largeur - 2 * _margeDesCarreaux;
  return (dispo - _ecartDesCarreaux * (kPastillesParRangee - 1)) /
      kPastillesParRangee;
}

/// La place du mot « Mon thème » au-dessus de la dernière rangée.
double get _hauteurDeLEtiquette => SF(11) * 1.4;

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

  /// La couleur en main, tenue en teinte-saturation-lumière : c'est ce que
  /// les deux dessins manipulent, et le gris n'a pas de teinte en RVB — la
  /// garder ici évite que la barre saute à zéro dès qu'on passe par le noir.
  late HSVColor _teinteEtNuance = HSVColor.fromColor(widget.actuelle);

  late final TextEditingController _code = TextEditingController(
    text: codeHexa(widget.actuelle),
  );

  Color get _couleur => _teinteEtNuance.toColor();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

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

  Widget _lesCarreaux(double hauteur) {
    final theme = paletteOf(Settings.instance.themeAxes.general);
    return SizedBox(
      key: cleDesCarreaux,
      height: hauteur,
      child: LayoutBuilder(
        builder: (context, boite) {
          final cote = coteDUnCarreau(boite.maxWidth);
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: _margeDesCarreaux),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final rangee in kRangeesDeLaPalette) ...[
                  _rangee(rangee, cote),
                  SizedBox(height: _ecartDesCarreaux),
                ],
                // LA RANGÉE DU THÈME, nommée : sans le mot, on prendrait ses
                // six couleurs pour une septième rangée de plus.
                SizedBox(
                  height: _hauteurDeLEtiquette,
                  child: Text(
                    T('Mon thème'),
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: SF(11),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _rangee(rangeeDuTheme(theme), cote),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Une rangée de pastilles, toutes de la même taille.
  Widget _rangee(List<Color> couleurs, double cote) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      for (final c in couleurs)
        SizedBox(
          width: cote,
          height: cote,
          child: _Pastille(
            couleur: c,
            choisie: c.toARGB32() == widget.actuelle.toARGB32(),
            onTap: () => Navigator.of(context).pop(c),
          ),
        ),
    ],
  );

  /// LES NUANCES, sur le modèle que Nino a montré : un carré de saturation
  /// et de lumière pour la teinte en cours, la barre des teintes à droite,
  /// le code hexadécimal — qu'on peut écrire — et l'ancienne couleur en
  /// regard de la nouvelle.
  ///
  /// Nino : « pour la nuance, recrée ça plutôt. » Le dégradé d'avant mettait
  /// tout dans un seul rectangle : on y perdait la teinte dès qu'on cherchait
  /// la lumière. Séparer les deux est ce que font tous les éditeurs, et pour
  /// la même raison.
  Widget _lesNuances(double hauteur) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        key: cleDuNuancier,
        height: hauteur,
        child: Row(
          children: [
            Expanded(
              child: Nuancier(
                couleur: _teinteEtNuance,
                onChange: _poseLaCouleur,
              ),
            ),
            SizedBox(width: S(8)),
            SizedBox(
              width: S(30),
              child: BarreDesTeintes(
                couleur: _teinteEtNuance,
                onChange: _poseLaCouleur,
              ),
            ),
          ],
        ),
      ),
      SizedBox(height: S(8)),
      // L'ANCIENNE ET LA NOUVELLE, côte à côte, chacune avec son code.
      Row(
        children: [
          _rond(widget.actuelle),
          SizedBox(width: S(6)),
          Text(
            codeHexa(widget.actuelle),
            style: TextStyle(
              color: Colors.white70,
              fontSize: SF(13),
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: S(8)),
          Icon(Icons.arrow_forward, size: SF(16), color: Colors.white54),
          SizedBox(width: S(8)),
          _rond(_couleur),
          SizedBox(width: S(6)),
          Expanded(
            child: TextField(
              controller: _code,
              maxLength: 7,
              style: TextStyle(
                color: Colors.white,
                fontSize: SF(13),
                fontWeight: FontWeight.bold,
              ),
              decoration: const InputDecoration(counterText: '', isDense: true),
              onChanged: _ecritLeCode,
            ),
          ),
        ],
      ),
      SizedBox(height: S(8)),
      SizedBox(
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
    ],
  );

  Widget _rond(Color c) => Container(
    width: touchHeight() * 0.46,
    height: touchHeight() * 0.46,
    decoration: BoxDecoration(
      color: c,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: S(1.5)),
    ),
  );

  /// Le doigt a bougé dans le carré ou dans la barre.
  void _poseLaCouleur(HSVColor c) => setState(() {
    _teinteEtNuance = c;
    _code.text = codeHexa(c.toColor());
  });

  /// On a écrit un code. Tant qu'il n'est pas complet, on ne touche à rien :
  /// effacer un caractère ne doit pas faire sauter la cible à l'autre bout
  /// du carré.
  void _ecritLeCode(String saisi) {
    final c = couleurDuCode(saisi);
    if (c == null) return;
    setState(() => _teinteEtNuance = HSVColor.fromColor(c));
  }
}

/// Le code d'une couleur, comme on l'écrit : « #RRGGBB ».
String codeHexa(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

/// La couleur d'un code écrit à la main, ou nul s'il n'en est pas un.
///
/// On accepte le dièse ou non, les majuscules comme les minuscules : ce qu'on
/// recopie d'ailleurs arrive sous toutes les formes.
Color? couleurDuCode(String saisi) {
  final propre = saisi.replaceAll('#', '').trim();
  if (propre.length != 6) return null;
  final valeur = int.tryParse(propre, radix: 16);
  if (valeur == null) return null;
  return Color(0xFF000000 | valeur);
}

/// LE CARRÉ : la saturation en largeur, la lumière en hauteur, pour une
/// teinte donnée.
class Nuancier extends StatelessWidget {
  const Nuancier({super.key, required this.couleur, required this.onChange});

  /// La couleur en main — sa teinte peint le carré, sa place y pose la cible.
  final HSVColor couleur;

  final ValueChanged<HSVColor> onChange;

  /// La couleur d'un point du carré, en fractions.
  static HSVColor couleurEn(double teinte, Offset f) => HSVColor.fromAHSV(
    1,
    teinte,
    f.dx.clamp(0.0, 1.0),
    1 - f.dy.clamp(0.0, 1.0),
  );

  /// Où se trouve une couleur dans le carré.
  static Offset placeDe(HSVColor c) => Offset(c.saturation, 1 - c.value);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, boite) {
      void suit(Offset local) => onChange(
        couleurEn(
          couleur.hue,
          Offset(local.dx / boite.maxWidth, local.dy / boite.maxHeight),
        ),
      );
      return GestureDetector(
        onTapDown: (d) => suit(d.localPosition),
        onPanUpdate: (d) => suit(d.localPosition),
        child: CustomPaint(
          painter: _PeintreDuCarre(couleur),
          size: boite.biggest,
        ),
      );
    },
  );
}

class _PeintreDuCarre extends CustomPainter {
  const _PeintreDuCarre(this.couleur);

  final HSVColor couleur;

  @override
  void paint(Canvas canvas, Size size) {
    final cadre = Offset.zero & size;
    final arrondi = RRect.fromRectAndRadius(cadre, Radius.circular(S(6)));
    canvas.save();
    canvas.clipRRect(arrondi);

    // Du blanc à la teinte pure, en largeur.
    canvas.drawRect(
      cadre,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white,
            HSVColor.fromAHSV(1, couleur.hue, 1, 1).toColor(),
          ],
        ).createShader(cadre),
    );
    // Puis le noir, en hauteur.
    canvas.drawRect(
      cadre,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Colors.black],
        ).createShader(cadre),
    );
    canvas.restore();

    _cible(canvas, Nuancier.placeDe(couleur), size);
  }

  @override
  bool shouldRepaint(_PeintreDuCarre vieux) => vieux.couleur != couleur;
}

/// LA BARRE DES TEINTES, à droite du carré.
class BarreDesTeintes extends StatelessWidget {
  const BarreDesTeintes({
    super.key,
    required this.couleur,
    required this.onChange,
  });

  final HSVColor couleur;
  final ValueChanged<HSVColor> onChange;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, boite) {
      void suit(Offset local) {
        final part = (local.dy / boite.maxHeight).clamp(0.0, 1.0);
        onChange(couleur.withHue(part * 359.99));
      }

      return GestureDetector(
        onTapDown: (d) => suit(d.localPosition),
        onPanUpdate: (d) => suit(d.localPosition),
        child: CustomPaint(
          painter: _PeintreDesTeintes(couleur.hue),
          size: boite.biggest,
        ),
      );
    },
  );
}

class _PeintreDesTeintes extends CustomPainter {
  const _PeintreDesTeintes(this.teinte);

  final double teinte;

  @override
  void paint(Canvas canvas, Size size) {
    final cadre = Offset.zero & size;
    final arrondi = RRect.fromRectAndRadius(cadre, Radius.circular(S(6)));
    canvas.save();
    canvas.clipRRect(arrondi);
    canvas.drawRect(
      cadre,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            for (var i = 0; i <= 12; i++)
              HSVColor.fromAHSV(1, (i * 30) % 360, 1, 1).toColor(),
          ],
        ).createShader(cadre),
    );
    canvas.restore();

    // Un trait en travers, à la hauteur de la teinte.
    final y = teinte / 360 * size.height;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = Colors.white
        ..strokeWidth = S(3),
    );
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = Colors.black
        ..strokeWidth = S(1),
    );
  }

  @override
  bool shouldRepaint(_PeintreDesTeintes vieux) => vieux.teinte != teinte;
}

/// La cible : deux ronds, un blanc et un noir, pour se voir sur tout.
void _cible(Canvas canvas, Offset place, Size size) {
  final ou = Offset(place.dx * size.width, place.dy * size.height);
  canvas.drawCircle(
    ou,
    S(8),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = S(3)
      ..color = Colors.white,
  );
  canvas.drawCircle(
    ou,
    S(8),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = S(1)
      ..color = Colors.black,
  );
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
