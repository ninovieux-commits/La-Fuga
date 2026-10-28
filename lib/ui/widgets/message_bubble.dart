/// Une bulle de conversation.
///
/// Nino : « Le texte doit apparaître dans des bulles par dessus. Les bulles
/// doivent être aux couleurs du thème. Pour les proportions des bulles
/// utilisez les proportions moyennes sur les apps de messages. »
///
/// ## Les proportions
///
/// Ce sont celles qu'on retrouve partout, et elles ne sont pas arbitraires :
///
///   — **largeur maximale : 75 %** de la place disponible. Au-delà, l'œil ne
///     distingue plus qui parle ; en deçà, les longs messages se hachent en
///     colonnes étroites.
///   — **marges intérieures : 14 horizontales, 10 verticales.** Le texte ne
///     doit pas toucher le bord, et l'écart horizontal est le plus grand
///     parce qu'une ligne se lit en largeur.
///   — **rayon : 18, sauf le coin du locuteur, à 4.** C'est ce coin presque
///     droit qui fait la « pointe » et dit d'où vient le message, sans
///     dessiner de queue.
///   — **écart entre deux bulles : 4**, et le double entre deux locuteurs.
///
/// ## Un cri
///
/// Un message qui finit par « ! » sort de sa bulle ronde et prend la bulle
/// hérissée de [PeintreBulleCri] — même couleur, même côté, même place
/// maximale. Voir `bulle_cri.dart` pour la forme ; ici, on se contente de
/// choisir le fond.
///
/// ## Que des dessins
///
/// Un message qui n'est fait QUE d'émojis, ou QUE d'images, sort de sa bulle
/// et s'affiche en grand, comme dans toutes les messageries : une bulle
/// autour d'un dessin ne sert à rien. Plus il y en a, plus ils sont petits,
/// mais ils ne redeviennent jamais de la taille du texte — Nino : « quand on
/// envoie que des smileys ou que des images ça doit aussi le mettre en plus
/// gros ». Voir `grossissementDe` dans `texte_emoji.dart`.
///
/// ## Une pièce
///
/// `[Soldat]`, `[Soldat Noir]` : le jeton se dessine à la place du texte,
/// dans le thème de CELUI QUI LIT — comme une photo de profil, qui voyage
/// elle aussi en mot et non en image. Seules les pièces, et pas le reste du
/// message : « bien joué [Garde] » garde sa phrase et sa pièce.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../state/settings.dart';
import '../../theme/themes.dart';
import '../mesure_emoji.dart';
import '../pieces_emoji.dart';
import '../scale.dart';
import '../texte_emoji.dart';
import 'bulle_cri.dart';
import 'fuga_button.dart';
import 'profile_photo.dart';

/// Part de la largeur qu'une bulle peut occuper au plus.
const double kBulleLargeurMax = 0.75;

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.texte,
    required this.deMoi,
    required this.palette,
    this.echoue = false,
    this.selectionnable = true,
  });

  final String texte;

  /// Vrai pour mes messages : ils vont à droite et portent l'autre couleur.
  final bool deMoi;

  /// Les couleurs du thème qui habille la conversation.
  final ThemePalette palette;

  /// L'envoi a échoué : la bulle le dit.
  final bool echoue;

  /// Un appui long ouvre les poignées de sélection.
  ///
  /// Faux pour la bulle qui passe pendant une partie : elle s'efface au bout
  /// de cinq secondes, et une sélection qu'on perd en la commençant vaudrait
  /// mieux ne pas être offerte. Le texte reste copiable dans la boîte de
  /// messages, où il demeure.
  final bool selectionnable;

  /// La photo, au sens de `ProfilePhoto`, que ce morceau dessine.
  ///
  /// Le thème de celui qui LIT ne sert qu'aux vieux jetons sans thème :
  /// les messages d'avant n'en nommaient pas.
  static String _photoDe(MorceauMessage m) =>
      photoDuMorceau(m, Settings.instance.themeAxes.general);

  /// Le message en morceaux : du texte, et des images dessinées.
  ///
  /// Une image occupe la place d'un ÉMOJI — Nino : « taille smiley » — et
  /// cette place se mesure au lieu de se deviner : un émoji déborde la taille
  /// de police qu'on lui donne, et de combien dépend de la police du système.
  static List<InlineSpan> _morceaux(String texte, double taille) => [
    for (final m in decoupeMessage(texte))
      if (m.texte == null)
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: ProfilePhoto(photo: _photoDe(m), size: tailleDUnEmoji(taille)),
        )
      else
        TextSpan(text: m.texte),
  ];

  @override
  Widget build(BuildContext context) {
    // Un message qui n'est QUE des images se montre en grand, sans bulle,
    // exactement comme un émoji seul — et quel qu'en soit le nombre.
    final images = compteImagesSeules(texte);
    if (images > 0 && !echoue) {
      // Les mêmes tailles qu'un émoji seul, mesurées de la même façon.
      final taille = tailleDUnEmoji(SF(16) * grossissementDe(images));
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: S(6), vertical: S(2)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * kBulleLargeurMax,
          ),
          // Wrap, et non Row : une pleine rangée de jetons passe à la ligne
          // au lieu de déborder de l'écran.
          child: Wrap(
            alignment: deMoi ? WrapAlignment.end : WrapAlignment.start,
            children: [
              for (final m in decoupeMessage(texte))
                if (m.texte == null)
                  ProfilePhoto(photo: _photoDe(m), size: taille),
            ],
          ),
        ),
      );
    }

    final grossi = grossissementEmoji(texte);
    // Un émoji seul se passe de bulle : rien à encadrer.
    if (grossi != null && !echoue) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: S(6), vertical: S(2)),
        child: Text(texte, style: TextStyle(fontSize: SF(16) * grossi)),
      );
    }

    final fond = echoue
        ? const Color.fromRGBO(120, 40, 40, 1)
        : (deMoi ? palette.clair : palette.fonce);
    final encre = echoue ? Colors.white : (deMoi ? Colors.black : Colors.white);
    final rayon = Radius.circular(S(18));
    final pointe = Radius.circular(S(4));
    final coins = BorderRadius.only(
      topLeft: rayon,
      topRight: rayon,
      // Le coin presque droit du côté du locuteur : c'est la pointe.
      bottomLeft: deMoi ? rayon : pointe,
      bottomRight: deMoi ? pointe : rayon,
    );

    final affiche = echoue ? '$texte  ${T("(non envoyé)")}' : texte;
    // SelectableText, et non Text : un appui long ouvre les poignées de
    // sélection et le menu « Copier ». C'est ce que Nino demande, et cela
    // vaut pour les messages reçus COMME pour les siens.
    final style = TextStyle(color: encre, fontSize: SF(16));
    // Le style reste SUR la touche de texte, et pas sur l'arbre de morceaux :
    // c'est là que le reste du code va le lire.
    final contenu = selectionnable
        ? SelectableText.rich(
            TextSpan(children: _morceaux(affiche, SF(16))),
            style: style,
            textAlign: TextAlign.left,
          )
        : Text.rich(
            TextSpan(children: _morceaux(affiche, SF(16))),
            style: style,
            textAlign: TextAlign.left,
          );

    final large = BoxConstraints(
      maxWidth: MediaQuery.of(context).size.width * kBulleLargeurMax,
    );

    if (estUnCri(texte)) {
      // La marge vaut la hauteur des pics : ils poussent vers l'extérieur de
      // la bulle, donc vers l'intérieur de la boîte qu'on peint. Le creux
      // s'y ajoute, sans quoi il mordrait sur la première lettre.
      final marge = S(kPicHaut);
      return ConstrainedBox(
        constraints: large,
        child: CustomPaint(
          painter: PeintreBulleCri(fond: fond, marge: marge),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: S(14) + marge + S(kPicCreux),
              vertical: S(10) + marge + S(kPicCreux),
            ),
            child: contenu,
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: large,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: S(14), vertical: S(10)),
        decoration: BoxDecoration(color: fond, borderRadius: coins),
        // LE MÊME TRAIT QUE LES TOUCHES, EN PREMIER PLAN. Nino : « les bulles
        // de messages partout où il en apparaît. »
        //
        // En premier plan, et c'est tout l'enjeu : une bordure posée dans la
        // décoration de FOND repousse l'enfant de son épaisseur, et la bulle
        // grandissait de deux pixels et demi. Peinte par-dessus, elle ne
        // pèse rien sur la mise en page.
        foregroundDecoration: BoxDecoration(
          border: const Border.fromBorderSide(kTraitDeTouche),
          borderRadius: coins,
        ),
        child: contenu,
      ),
    );
  }
}
