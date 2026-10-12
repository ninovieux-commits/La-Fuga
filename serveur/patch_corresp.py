# -*- coding: utf-8 -*-
"""Corrige DEUX bugs de la correspondance dans server.py.

1. LE GAGNANT. `corr_jouer` ecrivait `winner_uid = me["id"]` : la partie etait
   toujours donnee au joueur qui venait de jouer. Or le gagnant n'est pas
   toujours celui-la. Pousser l'Heritier ADVERSE dans son ralliement le fait
   fuguer, donc gagner ; ejecter son PROPRE Heritier est un mat contre
   soi-meme. Dans ces deux cas, la victoire allait au perdant.

   Le serveur ne peut pas le deviner a partir de la notation : il faut que le
   client le dise. La route accepte donc un champ `gagnant` ("Blanc"/"Noir").
   SANS ce champ, le comportement d'avant est conserve au caractere pres :
   une application qui ne l'envoie pas continue de marcher comme avant.

2. L'ARCHIVE INVISIBLE. La partie terminee etait rangee sous l'identifiant
   `corr_<id>`. L'historique du client ne montre que les identifiants
   `online_` (onglet En ligne) et `local_` : la partie etait bien enregistree
   pour les deux joueurs, et n'apparaissait NULLE PART. Elle est desormais
   rangee sous `online_corr<id>`, qui est aussi l'identifiant employe par
   l'application : les deux archives n'en font plus qu'une au lieu de se
   doubler.

   Les parties deja archivees gardent leur ancien identifiant ; la nouvelle
   version de l'application sait les afficher malgre tout.

Au passage : l'en-tete du .nmc annoncait 2 points pour une victoire par
« papatte », qui n'en vaut qu'un — le score, lui, comptait bien 1.

USAGE
    python3 patch_corresp.py /chemin/vers/server.py

Le script REFUSE d'ecrire si un seul des motifs n'est pas trouve exactement
une fois, y compris sur un fichier deja corrige. Une sauvegarde horodatee est
posee a cote avant toute ecriture.
"""
import datetime
import hashlib
import io
import os
import shutil
import sys

# (description, motif recherche, remplacement)
CORRECTIONS = [
    (
        "corr_jouer : le gagnant n'est pas toujours celui qui joue",
        '''    if methode:
        # Fin de partie
        winner_uid = me["id"]
        opp_uid = row["noir_user_id"] if my_color == "Blanc" else row["blanc_user_id"]
        if methode == "nulle":
            resultat = "nulle"
        else:
            resultat = "1-0" if my_color == "Blanc" else "0-1"
            pts = 1 if methode in ("mat", "papatte") else 2
            _add_corr_score(winner_uid, opp_uid, pts)''',
        '''    if methode:
        # Fin de partie. ATTENTION : le gagnant n'est PAS toujours celui qui
        # vient de jouer. Un coup peut pousser l'Heritier ADVERSE dans SON
        # ralliement (l'adversaire fugue, donc gagne), ou ejecter son PROPRE
        # Heritier hors du plateau (mat contre soi-meme). La partie etait alors
        # donnee a celui qui avait joue, c'est-a-dire au perdant.
        # Le client indique le camp gagnant ; sans indication, on garde
        # l'ancien comportement pour les clients qui ne l'envoient pas.
        gagnant = (data.get("gagnant") or "").strip()
        winner_color = gagnant if gagnant in ("Blanc", "Noir") else my_color
        winner_uid = (row["blanc_user_id"] if winner_color == "Blanc"
                      else row["noir_user_id"])
        opp_uid = (row["noir_user_id"] if winner_color == "Blanc"
                   else row["blanc_user_id"])
        if methode == "nulle":
            resultat = "nulle"
        else:
            resultat = "1-0" if winner_color == "Blanc" else "0-1"
            pts = 1 if methode in ("mat", "papatte") else 2
            _add_corr_score(winner_uid, opp_uid, pts)''',
    ),
    (
        "archive de correspondance : un identifiant que l'historique montre",
        '''    game_uid = "corr_%s" % row["id"]''',
        '''    # Prefixe "online_" : l'historique du client ne montre que les
    # identifiants "online_" (onglet En ligne) et "local_". Sous "corr_",
    # la partie etait bien archivee mais n'apparaissait NULLE PART. C'est
    # aussi l'identifiant que le client emploie de son cote, donc les deux
    # archives n'en font plus qu'une au lieu de se doubler.
    game_uid = "online_corr%s" % row["id"]''',
    ),
    (
        "en-tete du .nmc : une papatte vaut 1 point, pas 2",
        '''         resultat, methode, "2" if methode != "mat" else "1")''',
        '''         resultat, methode,
         "1" if methode in ("mat", "papatte") else "2")''',
    ),
]


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    chemin = sys.argv[1]
    if not os.path.isfile(chemin):
        print("Fichier introuvable : %s" % chemin)
        return 1

    with io.open(chemin, encoding="utf-8") as f:
        source = f.read()

    # Verifier TOUT avant d'ecrire quoi que ce soit.
    problemes = []
    for titre, motif, _ in CORRECTIONS:
        n = source.count(motif)
        if n != 1:
            problemes.append("  - %s : motif trouve %d fois (attendu 1)"
                             % (titre, n))
    if problemes:
        print("Rien n'a ete modifie. Motifs non conformes :")
        print("\n".join(problemes))
        print("\nSi le fichier est DEJA corrige, c'est normal : "
              "rien a faire.")
        return 1

    resultat = source
    for _, motif, remplacement in CORRECTIONS:
        resultat = resultat.replace(motif, remplacement, 1)

    # La syntaxe doit tenir avant de toucher au fichier en place.
    try:
        compile(resultat, chemin, "exec")
    except SyntaxError as e:
        print("Le resultat ne compile pas (%s). Rien n'a ete ecrit." % e)
        return 1

    horodatage = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    sauvegarde = "%s.avant-corresp-%s" % (chemin, horodatage)
    shutil.copy2(chemin, sauvegarde)
    with io.open(chemin, "w", encoding="utf-8") as f:
        f.write(resultat)

    empreinte = hashlib.sha256(resultat.encode("utf-8")).hexdigest()
    print("Sauvegarde : %s" % sauvegarde)
    print("%d corrections appliquees." % len(CORRECTIONS))
    print("sha256 du fichier corrige : %s" % empreinte)
    print("\nRedemarrez le service :  sudo systemctl restart lafuga")
    return 0


if __name__ == "__main__":
    sys.exit(main())
