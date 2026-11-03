/// L'ÉDITEUR : ce qu'on dessine sur une image avant de l'envoyer.
///
/// Nino : « le tout avec une option pour dessiner/ajouter du texte/des emojis
/// sur la photo avant de l'envoyer », et « en modifier, il faut ajouter un
/// bouton [tampon] qui crée un texte automatique comprenant la date et les
/// noms des deux joueurs. On doit pouvoir déplacer et changer la taille de ce
/// tampon. »
///
/// ## Ce qui sort d'ici est CE QU'ON VOIT
///
/// L'image finale n'est pas recomposée à la main, trait par trait : on
/// photographie la surface d'édition elle-même, à la résolution de l'image
/// d'origine. Tout ce qui est posé dessus — traits, étiquettes, tampon — s'y
/// retrouve exactement là où l'œil l'attend, sans qu'on ait à refaire deux
/// fois le même calcul de position, une fois pour l'écran et une fois pour
/// le fichier.
///
/// Puis on réencode en JPEG : le PNG d'une photo 720p pèse deux mégaoctets,
/// le JPEG deux cents kilos, et c'est tout l'intérêt des enveloppes.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

import '../../game/enveloppe.dart';
import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import '../suit_les_reglages.dart';
import '../widgets/fuga_background.dart';
import '../widgets/fuga_button.dart';
import '../widgets/fuga_header.dart';
import '../widgets/tampon_partie.dart';

/// Un trait tracé au doigt.
final class TraitDessine {
  TraitDessine(this.couleur, this.epaisseur);

  final Color couleur;
  final double epaisseur;

  /// Les points, EN FRACTION de la boîte de l'image : l'éditeur s'affiche à
  /// une taille, le fichier en fait une autre, et un trait doit tomber au
  /// même endroit sur les deux.
  final List<Offset> points = [];
}

/// Une étiquette posée sur l'image : du texte, des émojis, ou les deux.
final class Etiquette {
  Etiquette(this.texte, this.position, this.taille);

  String texte;

  /// Le centre, en fraction de la boîte.
  Offset position;

  /// La hauteur des lettres, en fraction de la HAUTEUR de la boîte.
  double taille;
}

/// Ce que l'éditeur rend : les octets JPEG de l'image composée.
class EditeurImageScreen extends StatefulWidget {
  const EditeurImageScreen({
    super.key,
    required this.image,
    required this.moi,
    required this.lui,
  });

  /// L'image d'origine, déjà réduite à 720p par le greffon.
  final Uint8List image;

  /// Les deux joueurs, pour le tampon.
  final String moi;
  final String lui;

  @override
  State<EditeurImageScreen> createState() => _EditeurImageScreenState();
}

/// L'outil en main.
enum Outil { dessin, deplacer }

class _EditeurImageScreenState extends State<EditeurImageScreen>
    with SuitLesReglages {
  final GlobalKey _surface = GlobalKey();

  final List<TraitDessine> _traits = [];
  final List<Etiquette> _etiquettes = [];
  Tampon? _tampon;
  Offset _tamponOu = const Offset(0.5, 0.86);
  double _tamponTaille = 0.055;

  Outil _outil = Outil.dessin;
  Color _encre = const Color(0xFFFF2D2D);
  bool _travaille = false;

  /// Ce qu'on est en train de déplacer : l'indice d'une étiquette, ou −1
  /// pour le tampon. Nul : rien.
  int? _saisi;

  /// Les couleurs du crayon : les deux du thème, et le noir et blanc qui se
  /// lisent sur tout.
  List<Color> get _encres {
    final palette = paletteOf(Settings.instance.themeAxes.general);
    return [
      const Color(0xFFFF2D2D),
      palette.clair,
      palette.fonce,
      Colors.white,
      Colors.black,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(Settings.instance.themeAxes.general);
    return FugaScaffold(
      body: SafeArea(
        child: Column(
          children: [
            FugaHeader(
              back: T('< Annuler'),
              title: T('Modifier'),
              titleSize: 22,
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(child: Center(child: _surfaceDEdition())),
            _barreDOutils(palette),
          ],
        ),
      ),
    );
  }

  /// L'image et tout ce qu'on a posé dessus, dans une boîte qu'on peut
  /// photographier d'un bloc.
  Widget _surfaceDEdition() => RepaintBoundary(
    key: _surface,
    child: LayoutBuilder(
      builder: (context, boite) => GestureDetector(
        onPanStart: (d) => _commence(d.localPosition, boite.biggest),
        onPanUpdate: (d) => _continue(d.localPosition, boite.biggest),
        onPanEnd: (_) => _saisi = null,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Image.memory(widget.image, fit: BoxFit.contain),
            Positioned.fill(
              child: CustomPaint(painter: _PeintreDesTraits(_traits)),
            ),
            for (var i = 0; i < _etiquettes.length; i++)
              _pose(
                _etiquettes[i].position,
                boite.biggest,
                Text(
                  _etiquettes[i].texte,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: _etiquettes[i].taille * boite.maxHeight,
                    fontWeight: FontWeight.bold,
                    shadows: const [
                      Shadow(blurRadius: 4, color: Color(0xCC000000)),
                    ],
                  ),
                ),
              ),
            if (_tampon != null)
              _pose(
                _tamponOu,
                boite.biggest,
                TamponPartie(
                  tampon: _tampon!,
                  taille: _tamponTaille * boite.maxHeight,
                ),
              ),
          ],
        ),
      ),
    ),
  );

  /// Pose un morceau à une position donnée en fraction de la boîte.
  Widget _pose(Offset ou, Size boite, Widget enfant) => Positioned(
    left: ou.dx * boite.width,
    top: ou.dy * boite.height,
    child: FractionalTranslation(
      translation: const Offset(-0.5, -0.5),
      child: enfant,
    ),
  );

  // ── Le doigt ──────────────────────────────────────────────────────────────

  void _commence(Offset ou, Size boite) {
    final f = Offset(ou.dx / boite.width, ou.dy / boite.height);
    if (_outil == Outil.dessin) {
      setState(() {
        _traits.add(TraitDessine(_encre, 0.008)..points.add(f));
      });
      return;
    }
    // Déplacement : on prend ce qui est le plus près du doigt.
    _saisi = _leProcheDe(f);
  }

  void _continue(Offset ou, Size boite) {
    final f = Offset(ou.dx / boite.width, ou.dy / boite.height);
    if (_outil == Outil.dessin) {
      if (_traits.isEmpty) return;
      setState(() => _traits.last.points.add(f));
      return;
    }
    final saisi = _saisi;
    if (saisi == null) return;
    setState(() {
      if (saisi < 0) {
        _tamponOu = f;
      } else if (saisi < _etiquettes.length) {
        _etiquettes[saisi].position = f;
      }
    });
  }

  /// L'indice du morceau le plus proche : −1 pour le tampon, sinon
  /// l'étiquette. Nul si rien n'est assez près.
  int? _leProcheDe(Offset f) {
    int? gagnant;
    var meilleur = 0.18; // au-delà, le doigt visait autre chose
    if (_tampon != null) {
      final d = (f - _tamponOu).distance;
      if (d < meilleur) {
        meilleur = d;
        gagnant = -1;
      }
    }
    for (var i = 0; i < _etiquettes.length; i++) {
      final d = (f - _etiquettes[i].position).distance;
      if (d < meilleur) {
        meilleur = d;
        gagnant = i;
      }
    }
    return gagnant;
  }

  // ── Les outils ────────────────────────────────────────────────────────────

  Widget _barreDOutils(ThemePalette palette) => Container(
    color: Colors.black38,
    padding: EdgeInsets.symmetric(horizontal: S(8), vertical: S(6)),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _outilTouche(
              Icons.brush,
              T('Dessin'),
              actif: _outil == Outil.dessin,
              onTap: () => setState(() => _outil = Outil.dessin),
              palette: palette,
            ),
            _outilTouche(
              Icons.open_with,
              T('Déplacer'),
              actif: _outil == Outil.deplacer,
              onTap: () => setState(() => _outil = Outil.deplacer),
              palette: palette,
            ),
            _outilTouche(
              Icons.title,
              T('Texte'),
              actif: false,
              onTap: _ajouterDuTexte,
              palette: palette,
            ),
            _outilTouche(
              Icons.approval,
              T('Tampon'),
              actif: _tampon != null,
              onTap: _poserLeTampon,
              palette: palette,
            ),
            _outilTouche(
              Icons.undo,
              T('Défaire'),
              actif: false,
              onTap: _defaire,
              palette: palette,
            ),
          ],
        ),
        SizedBox(height: S(6)),
        Row(
          children: [
            for (final c in _encres) _pastilleDEncre(c),
            const Spacer(),
            if (_tampon != null) ...[
              // Le petit bouton qui échange les deux ronds, et celui qui
              // change la taille du tampon.
              _rondBouton(Icons.swap_horiz, T('Inverser les ronds'), () {
                setState(() => _tampon = _tampon!.echange());
              }),
              SizedBox(width: S(4)),
              _rondBouton(Icons.remove, T('Plus petit'), () {
                setState(
                  () => _tamponTaille = (_tamponTaille * 0.85).clamp(0.02, 0.2),
                );
              }),
              SizedBox(width: S(4)),
              _rondBouton(Icons.add, T('Plus grand'), () {
                setState(
                  () => _tamponTaille = (_tamponTaille * 1.18).clamp(0.02, 0.2),
                );
              }),
              SizedBox(width: S(8)),
            ],
            SizedBox(
              width: S(120),
              child: FugaButton(
                text: _travaille ? '…' : T('Envoyer'),
                color: palette.clair,
                textColor: Colors.black,
                onPressed: _travaille ? null : () => unawaited(_envoyer()),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _outilTouche(
    IconData icone,
    String nom, {
    required bool actif,
    required VoidCallback onTap,
    required ThemePalette palette,
  }) => Expanded(
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: S(2)),
      child: Tooltip(
        message: nom,
        child: FugaButton(
          enfant: Icon(
            icone,
            size: SF(18),
            color: actif ? Colors.black : Colors.white,
          ),
          color: actif ? palette.clair : kGrisTouche,
          height: touchHeight() * 0.74,
          onPressed: onTap,
        ),
      ),
    ),
  );

  Widget _pastilleDEncre(Color c) => Padding(
    padding: EdgeInsets.only(right: S(6)),
    child: GestureDetector(
      onTap: () => setState(() => _encre = c),
      child: Container(
        width: S(22),
        height: S(22),
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(
            color: _encre == c ? Colors.white : Colors.black54,
            width: _encre == c ? S(3) : S(1),
          ),
        ),
      ),
    ),
  );

  Widget _rondBouton(IconData icone, String nom, VoidCallback onTap) => Tooltip(
    message: nom,
    child: SizedBox(
      width: touchHeight() * 0.62,
      height: touchHeight() * 0.62,
      child: FugaButton(
        enfant: Icon(icone, size: SF(16), color: Colors.white),
        color: kGrisTouche,
        height: double.infinity,
        radius: S(10),
        onPressed: onTap,
      ),
    ),
  );

  void _defaire() => setState(() {
    if (_etiquettes.isNotEmpty) {
      _etiquettes.removeLast();
    } else if (_traits.isNotEmpty) {
      _traits.removeLast();
    } else {
      _tampon = null;
    }
  });

  /// Le tampon se pose une fois ; le toucher de nouveau le retire.
  void _poserLeTampon() => setState(() {
    if (_tampon != null) {
      _tampon = null;
      return;
    }
    _tampon = Tampon(
      date: DateTime.now(),
      gauche: widget.moi,
      droite: widget.lui,
    );
    _outil = Outil.deplacer;
  });

  /// Du texte — et des émojis, que le clavier du téléphone offre déjà.
  Future<void> _ajouterDuTexte() async {
    final controleur = TextEditingController();
    final texte = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kFugaGrey,
        title: Text(
          T('Texte à poser'),
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controleur,
          autofocus: true,
          maxLength: 60,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: T('Votre texte…'),
            hintStyle: const TextStyle(color: Colors.white38),
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(T('Annuler')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controleur.text),
            child: Text(T('Poser')),
          ),
        ],
      ),
    );
    if (texte == null || texte.trim().isEmpty) return;
    setState(() {
      _etiquettes.add(Etiquette(texte.trim(), const Offset(0.5, 0.2), 0.07));
      _outil = Outil.deplacer;
    });
  }

  // ── La sortie ─────────────────────────────────────────────────────────────

  /// Photographie la surface et rend des octets JPEG.
  Future<void> _envoyer() async {
    setState(() => _travaille = true);
    try {
      final octets = await composeLImage(_surface);
      if (!mounted) return;
      Navigator.of(context).pop(octets);
    } catch (_) {
      if (!mounted) return;
      setState(() => _travaille = false);
    }
  }
}

/// Photographie la surface d'édition et réencode en JPEG.
///
/// Hors de la classe pour qu'un test puisse l'appeler sur n'importe quelle
/// boîte : c'est le seul endroit où l'image finale se fabrique.
Future<Uint8List> composeLImage(GlobalKey surface) async {
  final limite =
      surface.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  // On photographie à la taille de l'image d'origine, pas à celle de
  // l'écran : le téléphone affiche la surface en petit, et un envoi ne doit
  // pas y perdre sa définition.
  final largeur = limite.size.width;
  final ratio = largeur <= 0
      ? 1.0
      : (kEnveloppeCote / largeur).clamp(1.0, 4.0).toDouble();
  final image = await limite.toImage(pixelRatio: ratio);
  final brut = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final pixels = img.Image.fromBytes(
    width: image.width,
    height: image.height,
    bytes: brut!.buffer,
    numChannels: 4,
  );
  image.dispose();
  return img.encodeJpg(pixels, quality: 80);
}

/// Les traits, peints par-dessus l'image.
///
/// Les points sont rangés en FRACTION de la boîte : c'est ce qui fait qu'un
/// trait tracé sur un écran de téléphone tombe au même endroit dans le
/// fichier, qui en fait deux fois plus.
class _PeintreDesTraits extends CustomPainter {
  const _PeintreDesTraits(this.traits);

  final List<TraitDessine> traits;

  @override
  void paint(Canvas canvas, Size size) {
    for (final trait in traits) {
      if (trait.points.isEmpty) continue;
      final encre = Paint()
        ..color = trait.couleur
        ..style = PaintingStyle.stroke
        ..strokeWidth = trait.epaisseur * size.shortestSide
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final chemin = Path();
      final premier = trait.points.first;
      chemin.moveTo(premier.dx * size.width, premier.dy * size.height);
      for (final p in trait.points.skip(1)) {
        chemin.lineTo(p.dx * size.width, p.dy * size.height);
      }
      // Un point seul doit se voir : sans cela, un simple appui ne laisse
      // rien.
      if (trait.points.length == 1) {
        canvas.drawCircle(
          Offset(premier.dx * size.width, premier.dy * size.height),
          trait.epaisseur * size.shortestSide / 2,
          Paint()..color = trait.couleur,
        );
      }
      canvas.drawPath(chemin, encre);
    }
  }

  @override
  bool shouldRepaint(_PeintreDesTraits vieux) => true;
}
