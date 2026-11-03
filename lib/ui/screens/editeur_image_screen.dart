/// L'ÉDITEUR : ce qu'on dessine sur une image avant de l'envoyer.
///
/// Nino, d'abord : « le tout avec une option pour dessiner / ajouter du texte
/// / des emojis sur la photo avant de l'envoyer », et « un bouton [tampon]
/// qui crée un texte automatique comprenant la date et les noms des deux
/// joueurs ».
///
/// Puis, l'ayant essayé :
///
/// > « Le mode modification ne me convient pas. Il ne doit pas y avoir un
/// > bouton déplacer. Ça doit plutôt marcher avec des mouvements de doigt
/// > comme traditionnellement sur les apps qui le permettent : on ajoute un
/// > texte ou un tampon, celui-ci apparaît dans un cadre bleu. Le cadre bleu
/// > est un cadre de sélection qui permet de déplacer, agrandir ou rétrécir,
/// > pivoter. »
///
/// ## Le cadre bleu, et rien d'autre
///
/// Il n'y a donc plus d'outil « déplacer ». Un objet posé est SÉLECTIONNÉ —
/// son cadre bleu le dit — et tant qu'il l'est, le doigt le déplace, deux
/// doigts le tournent et l'agrandissent, et la poignée de son coin fait les
/// deux à un seul doigt. Un appui à côté le désélectionne ; le doigt revient
/// alors au dessin. Un objet qui n'est pas sélectionné ne gêne pas le crayon :
/// il ne prend que l'appui qui le choisit.
///
/// ## Une seule touche de couleur
///
/// > « Il doit y avoir un seul bouton couleur qui donne accès à une palette
/// > complète. Si on sélectionne une couleur pendant qu'il y a un cadre bleu,
/// > ça change la couleur de l'objet en question. Autrement, ça change la
/// > couleur de nos actions suivantes (texte, tampon, dessin). »
///
/// La touche porte donc la couleur en main, et ce qu'on choisit dedans va à
/// l'objet sélectionné s'il y en a un, sinon à l'encre.
///
/// ## Du noir autour, du blanc contre l'image
///
/// > « Le fond du mode modification doit être noir, ainsi notre image a très
/// > peu de chance de se fondre dedans. Ajoute aussi un cadre blanc autour de
/// > l'image en modification. »
///
/// Le cadre blanc est peint par le PARENT de la surface photographiée : il
/// borde l'image à l'écran sans se retrouver dans le fichier envoyé.
///
/// ## Ce qui sort d'ici est CE QU'ON VOIT
///
/// L'image finale n'est pas recomposée à la main, trait par trait : on
/// photographie la surface d'édition elle-même, à la résolution de l'image
/// d'origine. Tout ce qui est posé dessus s'y retrouve exactement là où l'œil
/// l'attend, sans qu'on ait à refaire deux fois le même calcul de position.
///
/// Puis on réencode en JPEG : le PNG d'une photo 720p pèse deux mégaoctets,
/// le JPEG deux cents kilos, et c'est tout l'intérêt des enveloppes.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

import '../../game/enveloppe.dart';
import '../../i18n/translations.dart';
import '../scale.dart';
import '../suit_les_reglages.dart';
import '../widgets/fuga_button.dart';
import '../widgets/fuga_header.dart';
import '../widgets/palette_couleurs.dart';
import '../widgets/tampon_partie.dart';

/// Le bleu du cadre de sélection. Celui des sélections, partout : il ne
/// désigne rien dans le jeu, donc on ne le confond avec rien.
const Color kBleuSelection = Color(0xFF2D9CFF);

/// Un trait tracé au doigt.
final class TraitDessine {
  TraitDessine(this.couleur, this.epaisseur);

  final Color couleur;

  /// En fraction du PLUS PETIT côté de la boîte.
  final double epaisseur;

  /// Les points, EN FRACTION de la boîte de l'image : l'éditeur s'affiche à
  /// une taille, le fichier en fait une autre, et un trait doit tomber au
  /// même endroit sur les deux.
  final List<Offset> points = [];

  /// Ce trait passe-t-il à moins de [rayon] de ce point ? C'est la question
  /// que pose la gomme.
  bool toucheA(Offset f, double rayon) =>
      points.any((p) => (p - f).distance <= rayon);
}

/// Un objet posé sur l'image : une étiquette de texte, ou le tampon.
///
/// Les deux se manipulent exactement pareil — on les déplace, on les tourne,
/// on les grandit — donc ils ne font qu'une classe. Ce qui les distingue
/// tient en un champ : l'un porte des mots, l'autre un tampon.
final class ObjetPose {
  ObjetPose.texte(
    String this.texte, {
    required this.position,
    required this.taille,
    required this.couleur,
  }) : tampon = null;

  ObjetPose.tampon(
    Tampon this.tampon, {
    required this.position,
    required this.taille,
    required this.couleur,
  }) : texte = null;

  final String? texte;

  /// Mutable : la petite touche qui échange les deux ronds en pose un autre.
  Tampon? tampon;

  /// Le centre, en fraction de la boîte.
  Offset position;

  /// La hauteur des lettres, en fraction de la HAUTEUR de la boîte.
  double taille;

  /// En radians, autour de son centre.
  double angle = 0;

  Color couleur;

  bool get estUnTampon => tampon != null;
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

/// L'outil en main. Le doigt dessine, ou il gomme — le reste se fait au
/// cadre bleu.
enum Outil { dessin, gomme }

class _EditeurImageScreenState extends State<EditeurImageScreen>
    with SuitLesReglages {
  final GlobalKey _surface = GlobalKey();

  final List<TraitDessine> _traits = [];
  final List<ObjetPose> _objets = [];

  /// L'ordre des poses, pour défaire : chaque élément est un trait ou un
  /// objet. Sans lui, « défaire » reprendrait toujours les objets d'abord,
  /// même ceux posés avant le dernier trait.
  final List<Object> _ordre = [];

  Outil _outil = Outil.dessin;
  Color _encre = const Color(0xFFFF2D2D);

  /// L'épaisseur des PROCHAINS traits — Nino : « le mode dessin doit donner
  /// un curseur pour gérer l'épaisseur des prochains traits ». En fraction
  /// du petit côté, comme le trait lui-même.
  double _epaisseur = 0.008;

  /// L'objet sélectionné, celui qui porte le cadre bleu.
  ObjetPose? _choisi;

  bool _travaille = false;

  /// La forme de l'image : largeur sur hauteur.
  ///
  /// LA SURFACE PREND EXACTEMENT CETTE FORME, et c'est tout l'enjeu : les
  /// objets et les traits sont rangés en fractions de leur boîte, et si
  /// cette boîte est la place disponible plutôt que la photo, un tampon posé
  /// « aux neuf dixièmes de la hauteur » tombe sous l'image — invisible à
  /// l'écran, absent du fichier, puisque c'est la photo qu'on photographie.
  /// Mesuré : le tampon atterrissait cent quatre-vingts points trop bas.
  double? _forme;

  /// Ce qu'on retient au début d'un pincement ou d'une poignée.
  double _tailleDepart = 0;
  double _angleDepart = 0;
  double _rayonDepart = 0;
  double _directionDepart = 0;

  static const double kEpaisseurMin = 0.002;
  static const double kEpaisseurMax = 0.04;

  /// Le rayon de la gomme suit l'épaisseur : on efface large quand on dessine
  /// large. Trois fois le trait, pour n'avoir pas à viser.
  double get _rayonGomme => math.max(_epaisseur * 3, 0.02);

  @override
  void initState() {
    super.initState();
    unawaited(_mesureLImage());
  }

  Future<void> _mesureLImage() async {
    try {
      final decodee = await decodeImageFromList(widget.image);
      if (!mounted) return;
      setState(() => _forme = decodee.width / decodee.height);
      decodee.dispose();
    } catch (_) {
      // Une image illisible n'arrivera pas jusqu'ici — le greffon l'a déjà
      // décodée — mais un carré vaut mieux qu'un écran vide.
      if (mounted) setState(() => _forme = 1);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    // DU NOIR, ET RIEN D'AUTRE. Nino : « le fond du mode modification doit
    // être noir, ainsi notre image a très peu de chance de se fondre
    // dedans. » C'est le seul écran de l'application sans son décor : ici,
    // ce qu'on regarde est la photo, et tout le reste doit s'effacer.
    backgroundColor: Colors.black,
    body: SafeArea(
      child: Column(
        children: [
          FugaHeader(
            back: T('< Annuler'),
            title: T('Modifier'),
            titleSize: 22,
            // Le titre est noir par défaut, et le fond vient de passer au
            // noir : sans ce blanc, le mot disparaissait.
            titleColor: Colors.white,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(child: Center(child: _lImageEtSonCadre())),
          _barreDOutils(),
        ],
      ),
    ),
  );

  /// L'image, bordée de blanc.
  ///
  /// Le trait est peint ICI, hors de la surface photographiée : il borde
  /// l'image à l'écran et ne se retrouve pas dans le fichier envoyé.
  Widget _lImageEtSonCadre() {
    final forme = _forme;
    if (forme == null) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    return Container(
      margin: EdgeInsets.all(S(6)),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white, width: S(2)),
      ),
      // LA BOÎTE A LA FORME DE LA PHOTO : la surface épouse l'image, donc
      // une fraction de la boîte est une fraction de l'image, à l'écran
      // comme dans le fichier.
      child: AspectRatio(aspectRatio: forme, child: _surfaceDEdition()),
    );
  }

  /// L'image et tout ce qu'on a posé dessus, dans une boîte qu'on peut
  /// photographier d'un bloc.
  Widget _surfaceDEdition() => RepaintBoundary(
    key: _surface,
    child: LayoutBuilder(
      builder: (context, contraintes) {
        final boite = contraintes.biggest;
        return GestureDetector(
          // Un appui dans le vide range le cadre bleu. C'est ce qui rend le
          // crayon au doigt sans qu'on ait à toucher une touche.
          onTap: () => setState(() => _choisi = null),
          onPanStart: (d) => _commence(d.localPosition, boite),
          onPanUpdate: (d) => _continue(d.localPosition, boite),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // `fill` et non `contain` : la boîte a déjà la forme de
              // l'image, donc les deux donnent le même dessin — mais `fill`
              // le dit, et interdit la bande noire qu'un arrondi de pixel
              // ferait apparaître.
              Positioned.fill(
                child: Image.memory(widget.image, fit: BoxFit.fill),
              ),
              Positioned.fill(
                child: CustomPaint(painter: PeintreDesTraits(_traits)),
              ),
              for (final o in _objets) _poseLObjet(o, boite),
            ],
          ),
        );
      },
    ),
  );

  /// Un objet, à sa place, tourné, et dans son cadre s'il est choisi.
  Widget _poseLObjet(ObjetPose o, Size boite) {
    final choisi = identical(o, _choisi);
    final enfant = o.estUnTampon
        ? TamponPartie(
            tampon: o.tampon!,
            taille: o.taille * boite.height,
            encre: o.couleur,
          )
        : Text(
            o.texte!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: o.couleur,
              fontSize: o.taille * boite.height,
              fontWeight: FontWeight.bold,
              shadows: const [Shadow(blurRadius: 4, color: Color(0xCC000000))],
            ),
          );

    return Positioned(
      left: o.position.dx * boite.width,
      top: o.position.dy * boite.height,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        // LA PRISE EST HORS DE LA ROTATION : les déplacements qu'elle
        // rapporte sont alors ceux de l'écran, et non ceux d'un repère
        // tourné — sans quoi un objet penché part de travers dès qu'on le
        // pousse.
        child: GestureDetector(
          onTap: () => setState(() => _choisi = o),
          onScaleStart: choisi ? (d) => _prendLObjet(o) : null,
          onScaleUpdate: choisi ? (d) => _bougeLObjet(o, d, boite) : null,
          child: Transform.rotate(
            angle: o.angle,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: EdgeInsets.all(S(4)),
                  decoration: choisi
                      ? BoxDecoration(
                          border: Border.all(
                            color: kBleuSelection,
                            width: S(1.5),
                          ),
                        )
                      : null,
                  child: enfant,
                ),
                if (choisi) ..._poignees(o, boite),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Les prises du cadre bleu : les trois coins qui ne font que le montrer,
  /// et celui d'en bas à droite qui tourne et redimensionne à un seul doigt.
  List<Widget> _poignees(ObjetPose o, Size boite) {
    final cote = S(14);
    Widget point({required bool vivante}) => Container(
      width: cote,
      height: cote,
      decoration: BoxDecoration(
        color: vivante ? kBleuSelection : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: S(1.5)),
      ),
    );
    return [
      Positioned(top: -cote / 2, left: -cote / 2, child: point(vivante: false)),
      Positioned(
        top: -cote / 2,
        right: -cote / 2,
        child: point(vivante: false),
      ),
      Positioned(
        bottom: -cote / 2,
        left: -cote / 2,
        child: point(vivante: false),
      ),
      Positioned(
        bottom: -cote / 2,
        right: -cote / 2,
        child: GestureDetector(
          onPanStart: (d) => _prendLaPoignee(o, d.globalPosition, boite),
          onPanUpdate: (d) => _tireLaPoignee(o, d.globalPosition, boite),
          child: point(vivante: true),
        ),
      ),
    ];
  }

  // ── Le doigt sur l'objet ──────────────────────────────────────────────────

  void _prendLObjet(ObjetPose o) {
    _tailleDepart = o.taille;
    _angleDepart = o.angle;
  }

  void _bougeLObjet(ObjetPose o, ScaleUpdateDetails d, Size boite) {
    setState(() {
      // Un doigt : on pousse. Deux : on tourne et on grandit EN PLUS, car le
      // point entre les deux doigts se déplace lui aussi.
      o.position += Offset(
        d.focalPointDelta.dx / boite.width,
        d.focalPointDelta.dy / boite.height,
      );
      if (d.pointerCount > 1) {
        o.taille = (_tailleDepart * d.scale).clamp(0.02, 0.6);
        o.angle = _angleDepart + d.rotation;
      }
      o.position = Offset(
        o.position.dx.clamp(0.0, 1.0),
        o.position.dy.clamp(0.0, 1.0),
      );
    });
  }

  void _prendLaPoignee(ObjetPose o, Offset global, Size boite) {
    final v = _versLeCentre(o, global, boite);
    _tailleDepart = o.taille;
    _angleDepart = o.angle;
    _rayonDepart = v.distance;
    _directionDepart = v.direction;
  }

  void _tireLaPoignee(ObjetPose o, Offset global, Size boite) {
    if (_rayonDepart <= 0) return;
    final v = _versLeCentre(o, global, boite);
    setState(() {
      o.taille = (_tailleDepart * v.distance / _rayonDepart).clamp(0.02, 0.6);
      o.angle = _angleDepart + (v.direction - _directionDepart);
    });
  }

  /// Le vecteur qui va du centre de l'objet au doigt, dans le repère de la
  /// surface. C'est lui qui donne la distance — donc la taille — et l'angle.
  Offset _versLeCentre(ObjetPose o, Offset global, Size boite) {
    final boiteRendue = _surface.currentContext?.findRenderObject();
    if (boiteRendue is! RenderBox) return Offset.zero;
    final local = boiteRendue.globalToLocal(global);
    final centre = Offset(
      o.position.dx * boite.width,
      o.position.dy * boite.height,
    );
    return local - centre;
  }

  // ── Le doigt sur l'image ──────────────────────────────────────────────────

  void _commence(Offset ou, Size boite) {
    final f = Offset(ou.dx / boite.width, ou.dy / boite.height);
    if (_outil == Outil.gomme) {
      _gomme(f);
      return;
    }
    setState(() {
      final trait = TraitDessine(_encre, _epaisseur)..points.add(f);
      _traits.add(trait);
      _ordre.add(trait);
    });
  }

  void _continue(Offset ou, Size boite) {
    final f = Offset(ou.dx / boite.width, ou.dy / boite.height);
    if (_outil == Outil.gomme) {
      _gomme(f);
      return;
    }
    if (_traits.isEmpty) return;
    setState(() => _traits.last.points.add(f));
  }

  /// LA GOMME N'EFFACE QUE CE QUI EST DESSINÉ. Nino : « il doit y avoir une
  /// gomme aussi, qui ne marche que sur ce qui est dessiné. » Un texte ou un
  /// tampon se reprend par son cadre bleu, pas en frottant dessus.
  void _gomme(Offset f) {
    final morts = _traits.where((t) => t.toucheA(f, _rayonGomme)).toList();
    if (morts.isEmpty) return;
    setState(() {
      _traits.removeWhere(morts.contains);
      _ordre.removeWhere(morts.contains);
    });
  }

  // ── Les outils ────────────────────────────────────────────────────────────

  Widget _barreDOutils() => Container(
    color: const Color(0xFF1A1A1A),
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
            ),
            _outilTouche(
              Icons.auto_fix_normal,
              T('Gomme'),
              actif: _outil == Outil.gomme,
              onTap: () => setState(() => _outil = Outil.gomme),
            ),
            _outilTouche(Icons.title, T('Texte'), onTap: _ajouterDuTexte),
            _outilTouche(
              Icons.approval,
              T('Tampon'),
              actif: _objets.any((o) => o.estUnTampon),
              onTap: _poserLeTampon,
            ),
            _outilTouche(Icons.undo, T('Défaire'), onTap: _defaire),
          ],
        ),
        SizedBox(height: S(6)),
        Row(
          children: [
            _toucheDeCouleur(),
            SizedBox(width: S(8)),
            // LE CURSEUR D'ÉPAISSEUR, en dessin comme à la gomme : l'un trace
            // large, l'autre efface large, et c'est le même réglage.
            Expanded(child: _curseurDEpaisseur()),
            if (_choisi?.estUnTampon ?? false) ...[
              SizedBox(width: S(6)),
              _rondBouton(Icons.swap_horiz, T('Inverser les ronds'), () {
                setState(() => _choisi!.tampon = _choisi!.tampon!.echange());
              }),
            ],
            SizedBox(width: S(8)),
            SizedBox(
              width: S(100),
              child: FugaButton(
                text: _travaille ? '…' : T('Envoyer'),
                color: kBleuSelection,
                fontSize: SF(15),
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
    bool actif = false,
    required VoidCallback onTap,
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
          color: actif ? kBleuSelection : kGrisTouche,
          height: touchHeight() * 0.74,
          onPressed: onTap,
        ),
      ),
    ),
  );

  /// UNE SEULE TOUCHE DE COULEUR, qui porte celle qu'on a en main.
  ///
  /// Ce qu'on choisit dedans va à l'objet sélectionné s'il y en a un — « ça
  /// change la couleur de l'objet en question » — et sinon à l'encre, donc au
  /// prochain trait, au prochain texte, au prochain tampon.
  Widget _toucheDeCouleur() => Tooltip(
    message: T('Couleur'),
    child: GestureDetector(
      onTap: () => unawaited(_ouvrirLaPalette()),
      child: Container(
        width: touchHeight() * 0.62,
        height: touchHeight() * 0.62,
        decoration: BoxDecoration(
          color: _choisi?.couleur ?? _encre,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: S(2)),
        ),
      ),
    ),
  );

  Future<void> _ouvrirLaPalette() async {
    final choisi = _choisi;
    final couleur = await choisirUneCouleur(
      context,
      actuelle: choisi?.couleur ?? _encre,
    );
    if (couleur == null || !mounted) return;
    setState(() {
      if (choisi != null) {
        choisi.couleur = couleur;
      } else {
        _encre = couleur;
      }
    });
  }

  Widget _curseurDEpaisseur() => Row(
    children: [
      // Un aperçu du trait : le chiffre ne dit rien, le point se voit.
      Container(
        width: S(26),
        height: S(26),
        alignment: Alignment.center,
        child: Container(
          width: S(2) + S(22) * (_epaisseur - kEpaisseurMin) / kEpaisseurMax,
          height: S(2) + S(22) * (_epaisseur - kEpaisseurMin) / kEpaisseurMax,
          decoration: BoxDecoration(
            color: _choisi?.couleur ?? _encre,
            shape: BoxShape.circle,
          ),
        ),
      ),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: kBleuSelection,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.white,
            trackHeight: S(3),
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(
            value: _epaisseur,
            min: kEpaisseurMin,
            max: kEpaisseurMax,
            onChanged: (v) => setState(() => _epaisseur = v),
          ),
        ),
      ),
    ],
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

  /// Défait la dernière pose, trait ou objet, dans l'ordre où elles sont
  /// venues.
  void _defaire() {
    if (_ordre.isEmpty) return;
    setState(() {
      final dernier = _ordre.removeLast();
      if (dernier is TraitDessine) {
        _traits.remove(dernier);
      } else if (dernier is ObjetPose) {
        _objets.remove(dernier);
        if (identical(dernier, _choisi)) _choisi = null;
      }
    });
  }

  /// Le tampon se pose une fois ; le toucher de nouveau le retire.
  void _poserLeTampon() {
    final dejaLa = _objets.where((o) => o.estUnTampon).toList();
    if (dejaLa.isNotEmpty) {
      setState(() {
        _objets.removeWhere(dejaLa.contains);
        _ordre.removeWhere(dejaLa.contains);
        if (dejaLa.any((o) => identical(o, _choisi))) _choisi = null;
      });
      return;
    }
    final pose = ObjetPose.tampon(
      Tampon(date: DateTime.now(), gauche: widget.moi, droite: widget.lui),
      position: const Offset(0.5, 0.86),
      taille: 0.055,
      couleur: _encre,
    );
    setState(() {
      _objets.add(pose);
      _ordre.add(pose);
      _choisi = pose;
    });
  }

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
    if (texte == null || texte.trim().isEmpty || !mounted) return;
    final pose = ObjetPose.texte(
      texte.trim(),
      position: const Offset(0.5, 0.2),
      taille: 0.07,
      couleur: _encre,
    );
    setState(() {
      _objets.add(pose);
      _ordre.add(pose);
      // IL ARRIVE DANS SON CADRE BLEU : « on ajoute un texte ou un tampon,
      // celui-ci apparaît dans un cadre bleu ». On le place donc au doigt
      // tout de suite, sans avoir à le choisir d'abord.
      _choisi = pose;
    });
  }

  // ── La sortie ─────────────────────────────────────────────────────────────

  /// Photographie la surface et rend des octets JPEG.
  Future<void> _envoyer() async {
    // LE CADRE BLEU N'EST PAS DANS L'IMAGE : on range la sélection, on laisse
    // l'image se repeindre sans elle, et on photographie ensuite.
    setState(() {
      _choisi = null;
      _travaille = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
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
/// Publique, et c'est voulu : c'est par elle qu'un test voit ce que le doigt
/// a tracé — et surtout ce que la gomme a repris. Sans elle, on ne pourrait
/// vérifier le dessin qu'à l'œil, sur une image.
///
/// Les points sont rangés en FRACTION de la boîte : c'est ce qui fait qu'un
/// trait tracé sur un écran de téléphone tombe au même endroit dans le
/// fichier, qui en fait deux fois plus.
class PeintreDesTraits extends CustomPainter {
  const PeintreDesTraits(this.traits);

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
  bool shouldRepaint(PeintreDesTraits vieux) => true;
}
