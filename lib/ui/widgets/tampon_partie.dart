/// Le TAMPON : la date et les deux joueurs, posés sur l'image.
///
/// Nino : « en modifier, il faut ajouter un bouton [tampon] qui crée un texte
/// automatique comprenant la date et les noms des deux joueurs. […] Il doit y
/// avoir un rond blanc à côté d'un des noms et un rond noir à côté de
/// l'autre, avec un petit bouton pour inverser ces deux ronds. »
///
/// Les deux ronds disent qui tenait les Blancs et qui tenait les Noirs. Ce
/// sont de vrais ronds peints, et non des émojis : à cette taille un émoji
/// change de dessin d'un téléphone à l'autre, et le blanc y est rarement
/// blanc.
library;

import 'package:flutter/material.dart';

import '../../game/date_locale.dart';
import '../../i18n/translations.dart';

/// Ce que le tampon raconte : une date, deux noms, et qui avait les Blancs.
final class Tampon {
  const Tampon({
    required this.date,
    required this.gauche,
    required this.droite,
    this.blancAGauche = true,
  });

  /// Le jour, tel qu'il s'écrira. On le fige à la pose : une image qu'on
  /// modifie le lendemain garde la date de la partie, pas celle du jour.
  final DateTime date;

  final String gauche;
  final String droite;

  /// Le rond BLANC est-il du côté du nom de gauche ? Le petit bouton
  /// l'échange.
  final bool blancAGauche;

  Tampon echange() => copie(blancAGauche: !blancAGauche);

  /// Le même, avec ce qu'on vient de corriger.
  Tampon copie({
    DateTime? date,
    String? gauche,
    String? droite,
    bool? blancAGauche,
  }) => Tampon(
    date: date ?? this.date,
    gauche: gauche ?? this.gauche,
    droite: droite ?? this.droite,
    blancAGauche: blancAGauche ?? this.blancAGauche,
  );

  /// La date au format court, sans nom de mois — il changerait de langue
  /// selon le téléphone, et le tampon est posé sur une image qui voyage —
  /// mais DANS LE SENS DE LA LANGUE. Nino : « lorsqu'un joueur a l'app
  /// réglée en anglais, ça doit mettre la date dans le sens anglais, idem
  /// pour les autres langues où le sens est différent. »
  String get dateEcrite => dateEcriteSelon(date, Translations.current.language);
}

/// Le tampon dessiné : la date au-dessus, les deux noms et leurs ronds en
/// dessous.
class TamponPartie extends StatelessWidget {
  const TamponPartie({
    super.key,
    required this.tampon,
    required this.taille,
    this.encre = Colors.white,
    this.surLaDate,
    this.surGauche,
    this.surDroite,
  });

  final Tampon tampon;

  /// La hauteur des lettres. Tout le reste en découle : le tampon se
  /// redimensionne d'un seul nombre.
  final double taille;

  /// L'encre des mots. Nino, sur l'éditeur : « si on sélectionne une couleur
  /// pendant qu'il y a un cadre bleu, ça change la couleur de l'objet en
  /// question » — le tampon en est un.
  ///
  /// Les deux ronds, eux, ne changent pas : ils disent qui tient les Blancs
  /// et qui tient les Noirs, et une autre couleur leur ôterait leur sens.
  final Color encre;

  /// Ce qu'on fait quand on touche la date ou l'un des noms.
  ///
  /// Nino : « les noms et la date doivent être cliquables pour
  /// modification. » Nuls — le cas du tampon qu'on ne fait que regarder —
  /// les trois morceaux ne prennent aucun appui, et le doigt passe au
  /// travers pour déplacer le tampon entier.
  final VoidCallback? surLaDate;
  final VoidCallback? surGauche;
  final VoidCallback? surDroite;

  /// Enveloppe un morceau d'une prise, si prise il y a — ET LE MONTRE.
  ///
  /// Nino : « lorsqu'un tampon est sélectionné, les données modifiables
  /// doivent apparaître dans des genres de barre de recherche pour qu'on
  /// comprenne que c'est modifiable. » Rien ne distinguait un mot qu'on
  /// peut corriger d'un mot qui est là : il fallait le savoir pour le
  /// toucher.
  ///
  /// Le cadre ne paraît QUE quand le morceau est prenable, c'est-à-dire
  /// quand le tampon est choisi. Posé, puis désélectionné, le tampon
  /// redevient ce qu'il sera sur l'image envoyée : trois lignes nues.
  Widget _prenable(Widget enfant, VoidCallback? quoiFaire) => quoiFaire == null
      ? enfant
      : GestureDetector(
          onTap: quoiFaire,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: taille * 0.3,
              vertical: taille * 0.1,
            ),
            decoration: BoxDecoration(
              // Un fond à peine plus clair que le voile du tampon, et un
              // trait de l'encre : de quoi lire un champ sans que le champ
              // se lise plus que le mot.
              color: const Color(0x26FFFFFF),
              borderRadius: BorderRadius.circular(taille * 0.3),
              border: Border.all(
                color: encre.withValues(alpha: 0.8),
                width: taille * 0.055,
              ),
            ),
            child: enfant,
          ),
        );

  @override
  Widget build(BuildContext context) {
    final rond = taille * 0.78;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: taille * 0.5,
        vertical: taille * 0.3,
      ),
      decoration: BoxDecoration(
        // Un voile sombre : le tampon doit se lire sur une photo claire
        // comme sur une photo sombre.
        color: const Color(0xA6000000),
        borderRadius: BorderRadius.circular(taille * 0.4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _prenable(
            Text(
              tampon.dateEcrite,
              style: TextStyle(
                color: encre,
                fontSize: taille * 0.8,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
            ),
            surLaDate,
          ),
          SizedBox(height: taille * 0.2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _camp(
                tampon.gauche,
                blanc: tampon.blancAGauche,
                rond: rond,
                encre: encre,
                quoiFaire: surGauche,
              ),
              SizedBox(width: taille * 0.7),
              _camp(
                tampon.droite,
                blanc: !tampon.blancAGauche,
                rond: rond,
                encre: encre,
                quoiFaire: surDroite,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Un nom et son rond. Le rond porte toujours un trait de l'autre couleur :
  /// sans lui, le noir disparaîtrait dans le voile sombre.
  ///
  /// LE ROND RESTE DEHORS. Nino : « les points noirs et blancs ne doivent
  /// pas être inclus. » Le champ dit « ceci se corrige » ; or le rond ne se
  /// corrige pas ici — il s'échange avec la touche à droite du cadre. Seul
  /// le NOM entre dans le champ.
  Widget _camp(
    String nom, {
    required bool blanc,
    required double rond,
    required Color encre,
    VoidCallback? quoiFaire,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: rond,
        height: rond,
        decoration: BoxDecoration(
          color: blanc ? Colors.white : Colors.black,
          shape: BoxShape.circle,
          border: Border.all(
            color: blanc ? Colors.black : Colors.white,
            width: rond * 0.12,
          ),
        ),
      ),
      SizedBox(width: rond * 0.4),
      _prenable(
        Text(
          nom,
          maxLines: 1,
          style: TextStyle(
            color: encre,
            fontSize: taille,
            fontWeight: FontWeight.bold,
            height: 1.1,
          ),
        ),
        quoiFaire,
      ),
    ],
  );
}
