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

import 'package:flutter/services.dart' show TextInputFormatter;

import '../../game/date_locale.dart';
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

/// Le rouge de la croix qui supprime : la seule prise du cadre qui DÉFAIT
/// quelque chose, et elle le dit.
const Color kRougeSuppression = Color(0xFFD93232);

/// La place laissée autour d'un cadre pour ses poignées.
///
/// ELLE EST DANS LA BOÎTE DE L'OBJET, et c'est tout l'enjeu : une poignée
/// peinte en dehors — ce qu'on obtient avec un `Positioned` négatif et un
/// `Clip.none` — se VOIT mais ne reçoit AUCUN doigt. Flutter n'envoie pas un
/// appui à ce qui déborde de la boîte de son parent. Nino : « je n'arrive
/// pas à pivoter ni agrandir/rétrécir. »
/// Elle se mesure sur la HAUTEUR D'UNE TOUCHE, et non sur la largeur de
/// l'écran : `S(18)` donne moins de dix points sur un téléphone — un dessin,
/// pas une prise. Une poignée se vise au doigt, elle suit donc la règle des
/// touches.
double get kMargeDesPoignees => touchHeight() * 0.55;

/// LES CRANS DE LA ROTATION : tous les quarts de tour, et les moitiés.
///
/// Nino : « la rotation doit avoir des "aimants" tous les 45 degrés (par
/// exemple quand on est à 85 degrés ça nous fixe tout seul à 90 en faisant
/// apparaître une ligne droite le long de l'écran). » Une ligne droite se
/// vise mal à la main : l'aimant la donne.
const double kCranDeRotation = math.pi / 4;

/// La portée de l'aimant : à moins de huit degrés d'un cran, on s'y colle.
///
/// Huit, et non trois : l'exemple de Nino demande que 85 degrés tombent sur
/// 90. Et non vingt : il reste alors trente degrés libres entre deux crans,
/// de quoi poser un angle qu'on a choisi.
const double kAimantDeRotation = 8 * math.pi / 180;

/// Le plus grand grossissement de l'image en cours de retouche.
const double kZoomMax = 4;

/// La transformation du regard, repérée pour les tests.
const Key cleDuZoom = ValueKey('zoom de l image');

/// La lenteur du zoom : Nino, « elle doit pouvoir se zoomer jusqu'à 4 fois
/// mais lentement pour la précision. » Un pincement qui double l'écart des
/// doigts ne grossit donc que de 40 % — on vise le pixel sans se battre.
const double kLenteurDuZoom = 0.4;

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

  /// CE QUI RESTE DU TRAIT quand la gomme passe à [rayon] de [f].
  ///
  /// Nino : « elle doit fonctionner comme une gomme — là elle supprime la
  /// totalité d'un trait qu'elle touche — c'est-à-dire effacer uniquement là
  /// où elle passe. » Un trait gommé par le milieu rend donc DEUX traits, et
  /// le trou a la taille du rond de la gomme.
  List<TraitDessine> moins(Offset f, double rayon) {
    final restes = <TraitDessine>[];
    TraitDessine? courant;
    for (final p in points) {
      if ((p - f).distance <= rayon) {
        courant = null;
        continue;
      }
      if (courant == null) {
        courant = TraitDessine(couleur, epaisseur);
        restes.add(courant);
      }
      courant.points.add(p);
    }
    // Un point tout seul se voit (le peintre en fait un rond), donc on le
    // garde : effacer autour d'un point ne doit pas effacer le point.
    return restes;
  }
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

  /// Mutable : la touche qui échange les ronds, et les corrections de la
  /// date ou des noms, en posent un autre.
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
  double _directionDepart = 0;

  /// LE REGARD, pas l'image : ce grossissement et ce décalage sont posés
  /// AU-DESSUS de la surface photographiée, donc ils ne partent pas dans
  /// l'enveloppe. On regarde de près pour viser, on envoie l'image entière.
  double _zoom = 1;
  Offset _vue = Offset.zero;
  double _zoomDepart = 1;

  /// Vrai tant qu'un doigt tient la poignée de rotation.
  bool _tourne = false;

  /// L'angle du cran auquel on est collé, le temps qu'on y reste.
  ///
  /// C'est lui que la ligne de repère suit. Nul : on tourne librement, et
  /// il n'y a pas de ligne.
  double? _aimant;

  /// Où le doigt s'est posé sur la croix de suppression.
  ///
  /// Un appui supprime, un glissement non : on ne jette pas un objet qu'on
  /// essayait de déplacer en partant de son coin.
  Offset? _doigtSurLaCroix;

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
      child: AspectRatio(
        aspectRatio: forme,
        // LE ZOOM EST AU-DESSUS DE LA SURFACE PHOTOGRAPHIÉE, et c'est ce qui
        // fait qu'il ne part pas dans l'enveloppe : `toImage` dessine la
        // limite de repeinture dans SON repère, sans rien savoir de ce que
        // ses parents lui font subir. On regarde donc de près, et on envoie
        // l'image entière.
        //
        // Les doigts, eux, traversent la transformation à l'endroit :
        // Flutter leur applique l'inverse, et le trait tombe là où on le
        // trace, zoomé ou non.
        child: ClipRect(
          child: Transform(
            key: cleDuZoom,
            transform: Matrix4.identity()
              ..translateByDouble(_vue.dx, _vue.dy, 0, 1)
              ..scaleByDouble(_zoom, _zoom, 1, 1),
            child: _surfaceDEdition(),
          ),
        ),
      ),
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
          // UNE SEULE PRISE POUR TOUT : un doigt dessine ou gomme, deux
          // doigts zooment. Flutter refuse qu'un même détecteur suive à la
          // fois les glissements et les pincements — et il a raison, les
          // deux se disputeraient le même appui.
          onTap: () => setState(() => _choisi = null),
          onScaleStart: (d) {
            _zoomDepart = _zoom;
            _tailleDepart = _choisi?.taille ?? 0;
            if (d.pointerCount == 1) _commence(d.localFocalPoint, boite);
          },
          // DEUX DOIGTS VONT À L'OBJET CHOISI, OÙ QU'ON LES POSE.
          //
          // Nino : « l'action de pincée à deux doigts doit agir sur l'objet
          // sélectionné même si on le fait ailleurs sur l'écran. Il ne doit
          // faire zoomer l'image uniquement si aucun objet n'est
          // sélectionné. » Pincer sur un petit objet demandait de viser un
          // objet plus petit que deux doigts ; on pince désormais au large,
          // et c'est l'objet qui répond.
          onScaleUpdate: (d) {
            if (d.pointerCount > 1) {
              final choisi = _choisi;
              if (choisi != null) {
                _redimensionne(choisi, d.scale);
              } else {
                _zoome(d, boite);
              }
              return;
            }
            _continue(d.localFocalPoint, boite);
          },
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
              // LA LIGNE DE L'AIMANT, par-dessus le reste : c'est elle qui
              // dit qu'on est droit. `IgnorePointer`, car elle traverse le
              // cadre et ses prises.
              if (_aimant != null && _choisi != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: PeintreDAimant(
                        centre: Offset(
                          _choisi!.position.dx * boite.width,
                          _choisi!.position.dy * boite.height,
                        ),
                        angle: _aimant!,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );

  /// Un objet, à sa place, tourné, et dans son cadre s'il est choisi.
  Widget _poseLObjet(ObjetPose o, Size boite) {
    final choisi = identical(o, _choisi);
    final tampon = o.tampon;
    final enfant = tampon != null
        ? TamponPartie(
            tampon: tampon,
            taille: o.taille * boite.height,
            encre: o.couleur,
            // LES NOMS ET LA DATE SE TOUCHENT, mais seulement quand le
            // tampon est choisi : sinon le premier appui le sélectionne,
            // comme pour tout le reste.
            surLaDate: choisi ? () => unawaited(_changerLaDate(o)) : null,
            surGauche: choisi
                ? () => unawaited(_changerUnNom(o, gauche: true))
                : null,
            surDroite: choisi
                ? () => unawaited(_changerUnNom(o, gauche: false))
                : null,
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

    // La place des poignées, DANS la boîte de l'objet. À droite, de quoi
    // loger la touche des ronds quand c'est un tampon choisi.
    final marge = kMargeDesPoignees;
    final margeDroite = choisi && o.estUnTampon ? touchHeight() * 0.7 : marge;

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
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    marge,
                    marge,
                    margeDroite,
                    marge,
                  ),
                  child: Container(
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
                ),
                if (choisi) ..._poignees(o, boite, margeDroite),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Les prises du cadre bleu : deux coins qui ne font que le montrer, la
  /// CROIX au coin haut-droit, la POIGNÉE DE ROTATION au coin bas-droit, et
  /// — pour un tampon — la touche qui échange les ronds, à droite du cadre.
  ///
  /// Nino : « il doit y avoir une poignée de rotation juste après l'angle
  /// haut/droite des cadres de sélection. Agrandir et rétrécir doit se faire
  /// en pinçant/dépinçant avec deux doigts », puis « la poignée de rotation
  /// doit finalement aller à l'angle du bas. Comme ça à l'angle du haut tu
  /// mets une croix qui supprime l'objet sélectionné. » Et : « le bouton
  /// d'inversion noir/blanc ne doit pas être dans le bandeau d'outils, il
  /// doit apparaître à droite du cadre lorsque le tampon est sélectionné. »
  List<Widget> _poignees(ObjetPose o, Size boite, double margeDroite) {
    final cote = S(13);
    final marge = kMargeDesPoignees;
    Widget point() => Container(
      width: cote,
      height: cote,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: kBleuSelection, width: S(1.5)),
      ),
    );
    // Les coins du cadre, mesurés depuis les bords de la boîte.
    final decal = marge - cote / 2;
    return [
      Positioned(top: decal, left: decal, child: point()),
      Positioned(bottom: decal, left: decal, child: point()),
      // LA CROIX QUI SUPPRIME, au coin haut-droit.
      Positioned(
        top: 0,
        right: margeDroite - marge,
        child: _croixDeSuppression(o, marge),
      ),
      // LA POIGNÉE DE ROTATION, au coin bas-droit.
      Positioned(
        bottom: 0,
        right: margeDroite - marge,
        // UN `Listener`, ET NON UNE PRISE DE PLUS : le détecteur de
        // l'objet suit les pincements, et un pincement accepte aussi UN
        // doigt. Les deux se disputaient donc la poignée, et c'est le
        // pincement qui gagnait — on déplaçait l'objet en croyant le
        // tourner. Nino : « je n'arrive pas à pivoter. »
        //
        // Le `Listener` reçoit les doigts sans entrer dans cette dispute, et
        // le drapeau dit au déplacement de se taire le temps qu'on tourne.
        child: Listener(
          onPointerDown: (e) {
            _tourne = true;
            _prendLaPoignee(o, e.position, boite);
          },
          onPointerMove: (e) {
            if (_tourne) _tourneLaPoignee(o, e.position, boite);
          },
          onPointerUp: (_) => _lacheLaPoignee(),
          onPointerCancel: (_) => _lacheLaPoignee(),
          child: Container(
            width: marge,
            height: marge,
            decoration: BoxDecoration(
              color: kBleuSelection,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: S(1.5)),
            ),
            child: Icon(
              Icons.rotate_right,
              size: marge * 0.72,
              color: Colors.white,
            ),
          ),
        ),
      ),
      if (o.estUnTampon)
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: Center(
            child: _rondBouton(
              Icons.swap_horiz,
              T('Inverser les ronds'),
              () => setState(() => o.tampon = o.tampon!.echange()),
            ),
          ),
        ),
    ];
  }

  /// LA CROIX QUI JETTE L'OBJET CHOISI.
  ///
  /// Nino : « à l'angle du haut tu mets une croix qui supprime l'objet
  /// sélectionné. »
  ///
  /// Un `Listener` comme la poignée de rotation, et pour la même raison : le
  /// détecteur de l'objet suit les pincements, et un pincement accepte aussi
  /// un doigt — une prise de plus se ferait voler l'appui.
  ///
  /// ET SEULEMENT SUR UN APPUI : un doigt qui a glissé voulait déplacer
  /// l'objet, pas le jeter. Un coin se touche par mégarde, et ce qu'on jette
  /// ici ne se récupère pas.
  Widget _croixDeSuppression(ObjetPose o, double marge) => Listener(
    onPointerDown: (e) => _doigtSurLaCroix = e.position,
    onPointerUp: (e) {
      final depart = _doigtSurLaCroix;
      _doigtSurLaCroix = null;
      if (depart == null || (e.position - depart).distance > S(12)) return;
      _supprime(o);
    },
    onPointerCancel: (_) => _doigtSurLaCroix = null,
    child: Container(
      width: marge,
      height: marge,
      decoration: BoxDecoration(
        color: kRougeSuppression,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: S(1.5)),
      ),
      child: Icon(Icons.close, size: marge * 0.72, color: Colors.white),
    ),
  );

  /// Retire l'objet, de la page ET de l'histoire des poses : « défaire » ne
  /// doit pas chercher à retirer une seconde fois ce qui n'est plus là.
  void _supprime(ObjetPose o) {
    setState(() {
      _objets.remove(o);
      _ordre.remove(o);
      if (identical(o, _choisi)) _choisi = null;
    });
  }

  // ── Le doigt sur l'objet ──────────────────────────────────────────────────

  void _prendLObjet(ObjetPose o) {
    // LA POIGNÉE A LA MAIN, ET ELLE LA GARDE.
    //
    // Le détecteur de l'objet suit les pincements, et un pincement accepte
    // aussi un doigt : dès que le doigt posé sur la poignée BOUGE, ce
    // détecteur s'éveille et passe par ici. Il y remettait l'angle de
    // départ à l'angle COURANT, sans toucher à la direction de départ — et
    // la rotation se mettait alors à compter double, puis triple. C'est
    // l'autre moitié du « je n'arrive pas à pivoter » : la poignée partait
    // en avance sur le doigt.
    if (_tourne) return;
    _tailleDepart = o.taille;
    _angleDepart = o.angle;
  }

  void _bougeLObjet(ObjetPose o, ScaleUpdateDetails d, Size boite) {
    // La poignée a la main : on ne déplace pas ce qu'on est en train de
    // faire tourner.
    if (_tourne) return;
    setState(() {
      // Un doigt : on pousse. Deux : on grandit — Nino, « agrandir et
      // rétrécir doit se faire en pinçant/dépinçant avec deux doigts » — et
      // le point entre les deux doigts continue de pousser.
      o.position += Offset(
        d.focalPointDelta.dx / boite.width,
        d.focalPointDelta.dy / boite.height,
      );
      if (d.pointerCount > 1) {
        o.taille = _tailleVisee(d.scale);
      }
      o.position = Offset(
        o.position.dx.clamp(0.0, 1.0),
        o.position.dy.clamp(0.0, 1.0),
      );
    });
  }

  /// La taille qu'un pincement d'échelle [echelle] demande, bornée.
  double _tailleVisee(double echelle) =>
      (_tailleDepart * echelle).clamp(0.02, 0.6);

  /// Le pincement grandit ou rapetisse l'objet choisi, sans le déplacer :
  /// on pince AILLEURS que sur lui, le centre des doigts n'a rien à dire de
  /// sa place.
  void _redimensionne(ObjetPose o, double echelle) {
    setState(() => o.taille = _tailleVisee(echelle));
  }

  void _prendLaPoignee(ObjetPose o, Offset global, Size boite) {
    final v = _versLeCentre(o, global, boite);
    _angleDepart = o.angle;
    _directionDepart = v.direction;
  }

  /// LA POIGNÉE NE FAIT QUE TOURNER. La taille se prend à deux doigts : une
  /// poignée qui ferait les deux change l'une quand on cherche l'autre.
  ///
  /// ET ELLE S'AIMANTE TOUS LES QUARTS DE TOUR. Voir [kCranDeRotation] : à
  /// moins de [kAimantDeRotation] d'un cran, l'objet s'y pose et une ligne
  /// le dit. Au-delà, l'angle reste celui du doigt — l'aimant aide, il
  /// n'impose pas.
  void _tourneLaPoignee(ObjetPose o, Offset global, Size boite) {
    final v = _versLeCentre(o, global, boite);
    if (v == Offset.zero) return;
    final brut = _angleDepart + (v.direction - _directionDepart);
    final cran = (brut / kCranDeRotation).roundToDouble() * kCranDeRotation;
    final colle = (brut - cran).abs() <= kAimantDeRotation;
    setState(() {
      o.angle = colle ? cran : brut;
      _aimant = colle ? cran : null;
    });
  }

  /// Le doigt quitte la poignée : la ligne de repère s'en va avec lui.
  void _lacheLaPoignee() {
    _tourne = false;
    if (_aimant != null) setState(() => _aimant = null);
  }

  /// Le vecteur qui va du centre de l'objet au doigt, dans le repère de la
  /// surface — zoom compris, puisque c'est lui qui porte la transformation.
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

  /// DEUX DOIGTS SUR L'IMAGE : on regarde de plus près.
  ///
  /// Nino : « lorsqu'on fait cette action alors que rien n'est sélectionné,
  /// ça doit zoomer/dézoomer l'image. Elle doit pouvoir se zoomer jusqu'à 4
  /// fois mais lentement pour la précision. On ne doit pas pouvoir dézoomer
  /// lorsque l'image est déjà entière. »
  ///
  /// D'où les deux bornes : un plancher à 1 — l'image entière, et pas plus
  /// petite — et un plafond à quatre. La vue est ensuite ramenée dans
  /// l'image : on ne peut pas faire glisser du vide dans le cadre.
  void _zoome(ScaleUpdateDetails d, Size boite) {
    final vise = (_zoomDepart * (1 + (d.scale - 1) * kLenteurDuZoom))
        .clamp(1.0, kZoomMax)
        .toDouble();
    setState(() {
      // Le point entre les deux doigts reste sous les doigts : sans cela, on
      // zoome toujours sur le coin de l'image.
      final ancre = d.localFocalPoint;
      final avant = (ancre - _vue) / _zoom;
      _zoom = vise;
      _vue = ancre - avant * _zoom;
      _vue += d.focalPointDelta;
      _vue = _dansLImage(_vue, boite);
    });
  }

  /// Ramène la vue dans l'image : jamais de vide dans le cadre.
  Offset _dansLImage(Offset vue, Size boite) {
    final debordX = boite.width * (_zoom - 1);
    final debordY = boite.height * (_zoom - 1);
    return Offset(vue.dx.clamp(-debordX, 0.0), vue.dy.clamp(-debordY, 0.0));
  }

  /// LA GOMME N'EFFACE QUE LÀ OÙ ELLE PASSE, et que ce qui est dessiné.
  ///
  /// Nino : « elle doit fonctionner comme une gomme — là elle supprime la
  /// totalité d'un trait qu'elle touche — c'est-à-dire effacer uniquement là
  /// où elle passe. » Un trait gommé par le milieu devient donc deux traits.
  /// Un texte ou un tampon, lui, se reprend par son cadre bleu : « elle ne
  /// marche que sur ce qui est dessiné ».
  void _gomme(Offset f) {
    final rayon = _rayonGomme;
    final touches = _traits.where((t) => t.toucheA(f, rayon)).toList();
    if (touches.isEmpty) return;
    setState(() {
      for (final vieux in touches) {
        final restes = vieux.moins(f, rayon);
        final place = _traits.indexOf(vieux);
        _traits.removeAt(place);
        _traits.insertAll(place, restes);
        // L'ordre des poses suit : « défaire » doit reprendre les morceaux
        // là où était le trait entier.
        final rang = _ordre.indexOf(vieux);
        if (rang >= 0) {
          _ordre.removeAt(rang);
          _ordre.insertAll(rang, restes);
        }
      }
    });
  }

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
            // UNE VRAIE GOMME, et non la baguette magique de Material :
            // Nino, « la gomme doit avoir une image de gomme plutôt que
            // cette espèce de baguette magique ». Aucune des icônes livrées
            // avec Flutter n'en est une — on la dessine.
            _outilTouche(
              null,
              T('Gomme'),
              dessin: GommeDessinee(
                encre: _outil == Outil.gomme ? Colors.black : Colors.white,
              ),
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
    IconData? icone,
    String nom, {
    bool actif = false,
    Widget? dessin,
    required VoidCallback onTap,
  }) => Expanded(
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: S(2)),
      child: Tooltip(
        message: nom,
        child: FugaButton(
          enfant:
              dessin ??
              Icon(
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

  /// LA DATE SE CORRIGE, et le clavier n'a que des chiffres à donner.
  ///
  /// Nino : « pour la date, ça doit laisser les // et remplir seul au bon
  /// endroit, qu'on ait qu'à appuyer sur les chiffres voulus. » Les
  /// séparateurs sont donc posés par le champ lui-même, dans l'ordre de la
  /// langue : le doigt ne tape que des chiffres.
  Future<void> _changerLaDate(ObjetPose o) async {
    final tampon = o.tampon;
    if (tampon == null) return;
    final langue = Translations.current.language;
    final controleur = TextEditingController(
      text: dateEcriteSelon(tampon.date, langue),
    );
    final saisi = await _demandeUnTexte(
      titre: T('La date'),
      indice: ordreDeLaDate(langue).masque,
      controleur: controleur,
      formateurs: [_MasqueDeDate(langue)],
      clavier: TextInputType.number,
      taille: 10,
    );
    if (saisi == null || !mounted) return;
    final date = dateDuTexte(saisi, langue);
    if (date == null) return;
    setState(() => o.tampon = tampon.copie(date: date));
  }

  /// L'un des deux noms. On ne les devine plus : ce sont les deux joueurs,
  /// mais une partie se raconte parfois autrement.
  Future<void> _changerUnNom(ObjetPose o, {required bool gauche}) async {
    final tampon = o.tampon;
    if (tampon == null) return;
    final controleur = TextEditingController(
      text: gauche ? tampon.gauche : tampon.droite,
    );
    final saisi = await _demandeUnTexte(
      titre: T('Le nom'),
      indice: T('Votre texte…'),
      controleur: controleur,
      taille: 20,
    );
    if (saisi == null || saisi.trim().isEmpty || !mounted) return;
    setState(
      () => o.tampon = gauche
          ? tampon.copie(gauche: saisi.trim())
          : tampon.copie(droite: saisi.trim()),
    );
  }

  /// Un champ dans un popup, et ce qu'on y a écrit.
  Future<String?> _demandeUnTexte({
    required String titre,
    required String indice,
    required TextEditingController controleur,
    required int taille,
    List<TextInputFormatter> formateurs = const [],
    TextInputType? clavier,
  }) => showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: kFugaGrey,
      title: Text(titre, style: const TextStyle(color: Colors.white)),
      content: TextField(
        controller: controleur,
        autofocus: true,
        maxLength: taille,
        keyboardType: clavier,
        inputFormatters: formateurs,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          counterText: '',
          hintText: indice,
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
/// LA LIGNE DE L'AIMANT : une droite qui traverse l'écran par le centre de
/// l'objet, à l'angle du cran où il vient de se poser.
///
/// Nino : « en faisant apparaître une ligne droite le long de l'écran ».
/// Elle ne vit que le temps où le doigt tient la poignée ET où l'objet est
/// collé : elle est la preuve qu'il est droit, pas une décoration.
class PeintreDAimant extends CustomPainter {
  const PeintreDAimant({required this.centre, required this.angle});

  /// Le centre de l'objet, dans le repère de la surface.
  final Offset centre;

  /// L'angle du cran, en radians.
  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    // Assez long pour sortir de la boîte par les deux bouts, quel que soit
    // l'angle : la somme des deux côtés dépasse toujours la diagonale.
    final portee = size.width + size.height;
    final sens = Offset(math.cos(angle), math.sin(angle)) * portee;
    canvas.drawLine(
      centre - sens,
      centre + sens,
      Paint()
        ..color = kBleuSelection
        ..strokeWidth = S(1.5)
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(PeintreDAimant vieux) =>
      vieux.centre != centre || vieux.angle != angle;
}

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

/// LE MASQUE DE LA DATE : les séparateurs se posent tout seuls.
///
/// On ne retient que les chiffres de ce qui est tapé, et on les redistribue
/// dans l'ordre de la langue. Effacer enlève un chiffre, jamais une barre
/// qu'il faudrait viser.
class _MasqueDeDate extends TextInputFormatter {
  _MasqueDeDate(this.langue);

  final String langue;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue vieux,
    TextEditingValue neuf,
  ) {
    final texte = masqueLaDate(neuf.text, langue);
    return TextEditingValue(
      text: texte,
      selection: TextSelection.collapsed(offset: texte.length),
    );
  }
}

/// UNE GOMME, dessinée : Flutter n'en livre pas.
///
/// Un parallélogramme penché, coupé en deux dans sa longueur — le caoutchouc
/// clair et la partie qui a servi. C'est le dessin que tout le monde
/// reconnaît, et il tient en quelques traits.
class GommeDessinee extends StatelessWidget {
  const GommeDessinee({super.key, this.encre = Colors.white});

  /// La couleur du trait qui en fait le tour.
  final Color encre;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: SF(20),
    height: SF(20),
    child: CustomPaint(painter: _PeintreDeGomme(encre)),
  );
}

class _PeintreDeGomme extends CustomPainter {
  const _PeintreDeGomme(this.encre);

  final Color encre;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width;
    // Le corps, penché : quatre points et un arrondi.
    final corps = Path()
      ..moveTo(c * 0.08, c * 0.72)
      ..lineTo(c * 0.52, c * 0.16)
      ..lineTo(c * 0.94, c * 0.46)
      ..lineTo(c * 0.50, c * 0.94)
      ..close();
    canvas.drawPath(corps, Paint()..color = const Color(0xFFF2B5B5));

    // La moitié basse, plus sombre : la partie qui a frotté.
    final usee = Path()
      ..moveTo(c * 0.08, c * 0.72)
      ..lineTo(c * 0.30, c * 0.44)
      ..lineTo(c * 0.72, c * 0.70)
      ..lineTo(c * 0.50, c * 0.94)
      ..close();
    canvas.drawPath(usee, Paint()..color = const Color(0xFFD98C8C));

    final trait = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = c * 0.07
      ..strokeJoin = StrokeJoin.round
      ..color = encre;
    canvas.drawPath(corps, trait);
    canvas.drawLine(
      Offset(c * 0.30, c * 0.44),
      Offset(c * 0.72, c * 0.70),
      trait,
    );
  }

  @override
  bool shouldRepaint(_PeintreDeGomme vieux) => vieux.encre != encre;
}
