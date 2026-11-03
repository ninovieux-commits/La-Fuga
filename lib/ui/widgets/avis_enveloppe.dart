/// « a envoyé une enveloppe » : l'avis qui suit le fil de la conversation.
///
/// Nino : « quand quelqu'un envoie une enveloppe, il doit y avoir écrit "a
/// envoyé une enveloppe" en dessous de la dernière bulle (suivant le fil de
/// la discussion). Ce ne doit pas être dans une bulle. Mets-le dans un petit
/// cadre en couleur 2 de la personne qui envoie. »
///
/// ## Pourquoi ce n'est pas une bulle
///
/// Une bulle porte des mots que quelqu'un a écrits ; ceci est un FAIT, pas
/// une parole — « il s'est passé quelque chose à cet endroit du fil ». D'où
/// la forme : pas de pointe, pas de couleur 1, et une place plus modeste.
///
/// Et c'est pour cela qu'il reste quand l'enveloppe, elle, s'en va : le
/// jeton disparaît de la boîte aux lettres dès qu'on l'ouvre, mais la
/// conversation garde la trace de l'envoi, comme elle garde les messages.
///
/// ## La couleur 2 de celui qui envoie
///
/// Les deux teintes du thème se partagent l'écran : couleur 1 pour toutes
/// les bulles, couleur 2 pour tout ce qui touche aux enveloppes — le jeton,
/// le symbole qui passe en partie, et cet avis. La palette, elle, est celle
/// de l'expéditeur, comme pour sa bulle.
library;

import 'package:flutter/material.dart';

import '../scale.dart';
import 'fuga_button.dart';

class AvisEnveloppe extends StatelessWidget {
  const AvisEnveloppe({
    super.key,
    required this.texte,
    required this.couleur,
    required this.deMoi,
  });

  final String texte;

  /// La SECONDE couleur du thème de l'expéditeur : voir `couleurEnveloppe`.
  final Color couleur;

  /// Vrai : c'est moi qui l'ai envoyée. L'avis se range de mon côté, comme
  /// ma bulle — le fil se lit de la même façon de haut en bas.
  final bool deMoi;

  @override
  Widget build(BuildContext context) => Align(
    alignment: deMoi ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: S(10), vertical: S(4)),
      decoration: BoxDecoration(
        color: couleur,
        borderRadius: BorderRadius.circular(S(8)),
        border: const Border.fromBorderSide(kTraitDeTouche),
      ),
      child: Text(
        texte,
        style: TextStyle(
          color: Colors.white,
          fontSize: SF(12),
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
}
