/// Les messages de l'adversaire, pendant la partie.
///
/// Nino : « quand on reçoit un message pendant qu'on est sur la partie
/// concernant l'adversaire en question, le message s'affiche dans une bulle
/// […] Le message doit rester afficher pendant 5 secondes et si un deuxième
/// message est envoyé alors que le [premier] est toujours afficher, ça défile.
/// Il ne faut pas que ça déborde sur le plateau ni sur les touches du haut. »
///
/// ## Où ça tient
///
/// Dans le bandeau de l'adversaire, et nulle part ailleurs : c'est le dessin
/// de Nino, et c'est la seule bande libre de l'écran de jeu. Le plateau et les
/// touches n'en voient rien, parce que la bulle est posée DANS la boîte du
/// bandeau — pas en surimpression de l'écran — et que ce qu'on y peint est
/// rogné à cette boîte. Un message long ne peut donc pas déborder : il
/// enroule, et si la place manque, il défile.
///
/// La photo reste visible à gauche : les bulles commencent après elle, comme
/// sur le dessin.
///
/// ## Les miens y passent aussi
///
/// Un message écrit depuis le plateau — la touche à bulle du bandeau du bas —
/// paraît ici de la même façon, à droite et à ma couleur, exactement comme
/// dans la boîte de messages. Nino : « il apparaît du coup sur la partie
/// quelques secondes comme n'importe quel autre message. Il est écrit d'un
/// autre endroit mais doit être traité de la même manière. »
///
/// Sans cela, écrire depuis le plateau ne montrerait RIEN : il faudrait
/// ouvrir la conversation pour savoir si le message est parti, ce qui est
/// précisément ce que cette touche évite.
///
/// ## Les messages s'empilent PAR LE BAS
///
/// Nino : « lorsque celle-ci est petite, qu'elle soit en bas du bandeau et
/// non pas en haut, mais le défilement de plusieurs messages reste dans le
/// même sens : le premier message apparaît en bas du bandeau, puis le
/// deuxième prend sa place alors que le premier défile vers le haut. »
///
/// C'est la pile d'une boîte de messages, et elle tient en deux choses : la
/// colonne est alignée sur la FIN, et elle reçoit une hauteur minimale égale
/// à celle du bandeau. Tant que les bulles n'emplissent pas la bande, elles
/// sont donc poussées contre son bas ; dès qu'elles la dépassent, la hauteur
/// minimale ne contraint plus rien et la liste défile comme avant, le dernier
/// arrivé en bas.
///
/// ## Ce qui défile
///
/// Chaque message vit [kBulleEnJeuDuree], à partir de SON arrivée — son
/// propre minuteur, et rien d'autre. Deux messages rapprochés se retrouvent
/// donc affichés ensemble, et le premier s'efface à son heure sans emporter
/// l'autre.
///
/// À chaque arrivée, la vue glisse pour amener le DÉBUT du dernier message en
/// haut du bandeau. Glisser jusqu'en bas serait plus simple, mais un message
/// plus haut que le bandeau s'ouvrirait alors sur sa fin, ses premiers mots
/// déjà sortis par le haut. Quand le dernier message est court, l'ajustement
/// bute de lui-même sur le bas de la liste.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/themes.dart';
import '../scale.dart';
import 'message_bubble.dart';

/// Combien de temps un message reste à l'écran.
///
/// Cinq secondes au départ, « le message doit rester afficher pendant 5
/// secondes ». Puis, l'ayant essayé en partie : « la bulle qui apparaît avec
/// le message reçu doit rester 2 secondes de plus. » Sept, donc — le temps de
/// lever les yeux du plateau, de lire, et de revenir.
const Duration kBulleEnJeuDuree = Duration(seconds: 7);

/// Le temps que met la vue à glisser jusqu'au dernier message.
const Duration kBulleEnJeuGlissee = Duration(milliseconds: 220);

/// Le temps que met une bulle neuve à MONTER depuis le bas de la bande.
///
/// Nino, après l'avoir vue sauter : « et oui je voudrais une glissée. »
/// Quand la place est libre, il n'y a rien à faire DÉFILER — la vue ne bouge
/// pas, c'est la colonne qui se réarrange. La glissée vient donc de la bulle
/// elle-même : elle grandit depuis le bas, et ce qu'elle prend de hauteur,
/// elle le prend aux précédentes, qui montent d'autant.
const Duration kBulleEnJeuMontee = Duration(milliseconds: 180);

class BullesEnJeu extends StatefulWidget {
  const BullesEnJeu({
    super.key,
    required this.flux,
    required this.palette,
    this.miens,
    this.duree = kBulleEnJeuDuree,
  });

  /// Les textes reçus de l'adversaire de CETTE partie.
  final Stream<String> flux;

  /// Les textes que J'ENVOIE depuis le plateau. Ils paraissent dans la même
  /// bande, à droite et à ma couleur.
  final Stream<String>? miens;

  /// Les couleurs de MON thème : la bulle doit ressembler à celles de la
  /// boîte de messages, et celles-là sont les miennes.
  final ThemePalette palette;

  final Duration duree;

  @override
  State<BullesEnJeu> createState() => _BullesEnJeuState();
}

/// Un message affiché, avec le minuteur qui l'effacera.
final class _Affiche {
  _Affiche(this.texte, {required this.deMoi});

  final String texte;

  /// Vrai quand c'est moi qui l'ai écrit : la bulle passe à droite et prend
  /// ma couleur, comme dans la boîte de messages.
  final bool deMoi;

  /// Pour amener le début de cette bulle en haut du bandeau à son arrivée.
  final GlobalKey cle = GlobalKey();

  /// Son échéance à lui. Pas d'horloge murale ici : un minuteur par message,
  /// annulé en quittant l'écran. Lire `DateTime.now()` mêlerait deux horloges
  /// — celle du minuteur et celle du calendrier — et la durée cesserait d'être
  /// vérifiable.
  Timer? mort;
}

class _BullesEnJeuState extends State<BullesEnJeu> {
  final List<_Affiche> _bulles = [];
  final ScrollController _scroll = ScrollController();
  StreamSubscription<String>? _ecoute;
  StreamSubscription<String>? _ecouteMiens;

  @override
  void initState() {
    super.initState();
    _ecoute = widget.flux.listen((t) => _arrive(t, deMoi: false));
    _ecouteMiens = widget.miens?.listen((t) => _arrive(t, deMoi: true));
  }

  @override
  void dispose() {
    for (final b in _bulles) {
      b.mort?.cancel();
    }
    _ecoute?.cancel();
    _ecouteMiens?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _arrive(String texte, {required bool deMoi}) {
    if (!mounted || texte.trim().isEmpty) return;
    final venue = _Affiche(texte, deMoi: deMoi);
    venue.mort = Timer(widget.duree, () => _retire(venue));
    // Le dernier arrivé se montrera par son début — mais une fois MONTÉ,
    // c'est-à-dire depuis `onEnd` de sa montée. Viser pendant qu'il grandit,
    // c'est viser une boîte encore vide : la vue ne bouge pas, et la bulle
    // finit sa montée SOUS le bandeau, hors de vue. Mesuré.
    setState(() => _bulles.add(venue));
  }

  void _retire(_Affiche b) {
    if (!mounted) return;
    b.mort?.cancel();
    setState(() => _bulles.remove(b));
  }

  void _montre(_Affiche b) {
    final ou = b.cle.currentContext;
    if (ou == null || !_scroll.hasClients) return;
    Scrollable.ensureVisible(
      ou,
      // 0 : le haut de la bulle contre le haut du bandeau.
      alignment: 0,
      duration: kBulleEnJeuGlissee,
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_bulles.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        // La photo occupe un carré de la hauteur du bandeau, moins ses marges
        // — même calcul que `PlayerPanel`. Les bulles commencent après elle.
        final photo = box.maxHeight - 2 * S(4);
        return Padding(
          padding: EdgeInsets.only(
            left: photo + S(14),
            right: S(8),
            top: S(4),
            bottom: S(4),
          ),
          // Rogné au bandeau : rien ne sort vers le plateau ni vers les
          // touches. C'est la contrainte de Nino, et elle est tenue ici plutôt
          // que par la bonne volonté de chaque message. Un `ClipRect` autour
          // ferait le même découpage au même pixel — mesuré — donc on s'en
          // passe et on écrit le découpage là où il a lieu.
          child: SingleChildScrollView(
            controller: _scroll,
            clipBehavior: Clip.hardEdge,
            // La hauteur du bandeau, imposée EN MINIMUM à la colonne : tant
            // que les bulles n'emplissent pas la bande, la colonne l'emplit
            // pour elles et les pousse contre son bas. Dès qu'elles la
            // dépassent, ce minimum ne contraint plus rien.
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 2 * S(4)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                // EN BAS, comme dans une boîte de messages : le premier
                // message paraît contre le bas du bandeau, et le suivant
                // prend sa place en le poussant vers le haut.
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final b in _bulles)
                    // LA GLISSÉE. La bulle neuve grandit depuis son bas :
                    // `heightFactor` dit quelle part de sa hauteur elle
                    // occupe, le `ClipRect` cache le reste, et la colonne
                    // étant alignée sur sa fin, tout ce qu'elle gagne, les
                    // précédentes le montent. Une seule bulle bouge, et
                    // quatre remontent sans qu'on s'en occupe.
                    TweenAnimationBuilder<double>(
                      // L'identité de la bulle DANS LA LISTE : sans elle, une
                      // bulle qui s'efface décale les suivantes d'un cran et
                      // relance leur montée alors qu'elles sont déjà là.
                      //
                      // Ce n'est PAS la clé que vise le défilement : celle-là
                      // reste plus bas, sur une boîte qui existe vraiment.
                      // Posée ici, `Scrollable.ensureVisible` n'avait plus
                      // rien à viser et la vue ne bougeait plus — quatre
                      // bulles s'empilaient sous le bandeau, hors de vue.
                      key: ObjectKey(b),
                      tween: Tween<double>(begin: 0, end: 1),
                      duration: kBulleEnJeuMontee,
                      curve: Curves.easeOut,
                      // Montée finie : on amène son début sous les yeux, à
                      // l'image SUIVANTE — celle où sa hauteur est enfin
                      // celle qu'elle gardera.
                      onEnd: () => WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _montre(b),
                      ),
                      builder: (context, part, enfant) => ClipRect(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          heightFactor: part,
                          child: enfant,
                        ),
                      ),
                      child: Padding(
                        key: b.cle,
                        padding: EdgeInsets.only(bottom: S(4)),
                        child: Align(
                          // Reçu à gauche, envoyé à droite : la disposition de
                          // la boîte de messages, puisque c'en sont.
                          alignment: b.deMoi
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: MessageBubble(
                            texte: b.texte,
                            // La couleur et l'écriture que ce message aurait
                            // dans la boîte de messages.
                            deMoi: b.deMoi,
                            palette: widget.palette,
                            selectionnable: false,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
