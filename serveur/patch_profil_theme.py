# -*- coding: utf-8 -*-
"""Le profil d'un joueur dit aussi son THEME.

La boite de messages s'habille du decor de l'interlocuteur : son fond de menu
derriere la conversation, ses couleurs sur les bulles. Nino : « quand on accede
a une boite de message, on voit en fond de la conversation l'image de fond de
menu choisit par notre interlocuteur. »

Le serveur garde deja ce theme — c'est `/set_theme` qui l'enregistre — mais
`/get_profile` ne le rendait que pour soi-meme, enfoui dans la reponse de
`/login`. L'application ne pouvait donc pas connaitre celui des autres.

CE QUI CHANGE
    - /get_profile rend `theme`

UNE SEULE LIGNE, ET RIEN D'AUTRE. Le theme n'est pas une donnee privee : il
s'affiche deja sur chaque ecran de celui qui l'a choisi, et il ne dit rien de
plus que ses gouts.

N'ENLEVE RIEN. Une application pas encore corrigee ignore la cle et affiche la
conversation avec son propre decor, comme avant.

USAGE
    python3 patch_profil_theme.py /chemin/vers/server.py

Le script REFUSE d'ecrire si le motif n'est pas trouve exactement une fois, y
compris sur un fichier deja corrige. Une sauvegarde horodatee est posee a cote
avant toute ecriture.
"""
import datetime
import hashlib
import io
import os
import shutil
import sys


MOTIF = '''        "photo": u.get("photo") or "",
        "description": u.get("description") or "",'''

REMPLACEMENT = '''        "photo": u.get("photo") or "",
        # Le theme habille la boite de messages : on entre chez lui, on voit
        # son decor. Rien de prive la-dedans — c'est deja ce que son ecran
        # montre a qui regarde par-dessus son epaule.
        "theme": u.get("theme") or "original",
        "description": u.get("description") or "",'''


CORRECTIONS = [
    ("/get_profile rend le theme", MOTIF, REMPLACEMENT),
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

    for nom, motif, _ in CORRECTIONS:
        n = source.count(motif)
        if n != 1:
            print("REFUS : le motif « %s » apparait %d fois (attendu : 1)."
                  % (nom, n))
            print("Le fichier n'a PAS ete modifie.")
            print("Un fichier deja corrige donne 0 : il n'y a rien a refaire.")
            return 1

    corrige = source
    for _, motif, remplacement in CORRECTIONS:
        corrige = corrige.replace(motif, remplacement)

    horodatage = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    sauvegarde = "%s.avant-profil-theme-%s" % (chemin, horodatage)
    shutil.copy2(chemin, sauvegarde)
    with io.open(chemin, "w", encoding="utf-8") as f:
        f.write(corrige)

    print("Sauvegarde : %s" % sauvegarde)
    print("%d correction appliquee." % len(CORRECTIONS))
    print("sha256 du fichier corrige : %s"
          % hashlib.sha256(corrige.encode("utf-8")).hexdigest())
    print("")
    print("Redemarrez le service :  sudo systemctl restart lafuga")
    return 0


if __name__ == "__main__":
    sys.exit(main())
