/// Un message écrit SANS QUITTER LE PLATEAU DES YEUX.
///
/// Nino : « j'aimerai l'ajout d'un bouton […] un bouton texte rapide avec un
/// dessin de bulle dessus. Lorsqu'on clique sur ce bouton, le clavier sort et
/// on peut écrire un message rapide sans quitter le plateau des yeux. On
/// clique sur envoyer et le message part dans la boîte de chat. »
///
/// C'est une feuille posée en bas de l'écran, et rien d'autre : le clavier la
/// pousse, le plateau reste visible au-dessus. Ouvrir la conversation
/// remplirait l'écran et ferait perdre la position de vue — c'est tout ce
/// qu'on veut éviter ici.
///
/// Le champ et la touche sont ceux de la boîte de messages, au détail près :
/// même invite, même libellé, mêmes couleurs. Ce n'est pas un autre
/// composeur, c'est le même, ouvert ailleurs.
library;

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../scale.dart';

/// Ouvre le composeur rapide. Rend le texte écrit, ou `null` si on renonce.
///
/// Le texte rendu est déjà élagué et n'est jamais vide : appuyer sur
/// « Envoyer » sans rien écrire ne ferme même pas la feuille.
Future<String?> ouvrirMessageRapide(
  BuildContext context, {
  required ThemePalette palette,
}) => showModalBottomSheet<String>(
  context: context,
  // Sans cela, la feuille garderait la hauteur d'un demi-écran et le clavier
  // passerait par-dessus le champ.
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => _MessageRapide(palette: palette),
);

class _MessageRapide extends StatefulWidget {
  const _MessageRapide({required this.palette});

  final ThemePalette palette;

  @override
  State<_MessageRapide> createState() => _MessageRapideState();
}

class _MessageRapideState extends State<_MessageRapide> {
  final TextEditingController _texte = TextEditingController();

  @override
  void dispose() {
    _texte.dispose();
    super.dispose();
  }

  void _envoie() {
    final texte = _texte.text.trim();
    // Rien à envoyer : on ne ferme pas, le doigt a sans doute glissé.
    if (texte.isEmpty) return;
    Navigator.of(context).pop(texte);
  }

  @override
  Widget build(BuildContext context) => Padding(
    // Le clavier pousse la feuille, au lieu de la recouvrir.
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Container(
      padding: EdgeInsets.all(S(8)),
      color: const Color.fromRGBO(32, 32, 32, 1),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _texte,
                // Le clavier sort tout seul : la touche a déjà été pressée,
                // en demander une seconde pour écrire serait une de trop.
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: T('Votre message…'),
                  hintStyle: const TextStyle(color: Colors.white38),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                // La touche d'envoi du clavier fait la même chose que celle
                // de l'écran : on ne quitte pas le clavier pour envoyer.
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _envoie(),
              ),
            ),
            SizedBox(width: S(8)),
            FilledButton(
              onPressed: _envoie,
              style: FilledButton.styleFrom(
                backgroundColor: widget.palette.clair,
              ),
              child: Text(T('Envoyer')),
            ),
          ],
        ),
      ),
    ),
  );
}
