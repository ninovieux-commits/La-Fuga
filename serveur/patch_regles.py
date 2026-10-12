# -*- coding: utf-8 -*-
"""Deux regles de plus pour une position composee : la place, et le Chevalier.

Apres « un Heritier par camp » et « des carrees qui peuvent bouger des deux
cotes », une position composee doit aussi :

  - laisser AU MOINS TROIS CASES LIBRES. Un plateau presque plein ne laisse
    nulle part ou aller : rien ne peut avancer, et la partie serait nulle
    d'entree comme avec des carrees bloquees.

  - n'avoir QU'UN CHEVALIER AU PLUS PAR CAMP. Il n'en existe qu'un par camp ;
    zero est permis, deux ne l'est pas. Le composeur ne sait pas en poser un
    second — il deplace celui qui est la — mais un code .fug ecrit a la main,
    lui, peut en contenir autant qu'il veut.

CE QUI CHANGE
    - _fug_refus rend aussi 'vides' et 'chevalier'
    - /corr_defier refuse donc : position_vides, position_chevalier

POURQUOI LE SERVEUR LES VERIFIE AUSSI. L'application les verifie deja, mais
c'est le serveur qui garde la partie : s'il accepte une position que
l'application refuse, elle s'installe pour de bon et chaque client la relit de
travers. Comme les autres, ces deux regles ne demandent pas de connaitre le
jeu : compter des lettres suffit.

N'ENLEVE RIEN. Les parties deja en cours ne sont pas relues : les regles ne
s'appliquent qu'a la creation d'un defi. Et `_fug_refus` n'est appele que dans
la branche `mode == "personnalise"` : tout le reste du serveur ne voit pas la
difference.

A APPLIQUER APRES patch_position.py, qui installe `_fug_refus`.

USAGE
    python3 patch_regles.py /chemin/vers/server.py

Le script REFUSE d'ecrire si un motif n'est pas trouve exactement une fois, y
compris sur un fichier deja corrige. Une sauvegarde horodatee est posee a cote
avant toute ecriture.
"""
import datetime
import hashlib
import io
import os
import shutil
import sys


MOTIF = '''def _fug_refus(grille):
    """Pourquoi cette position ne peut pas servir de depart, ou None.

    Les deux regles de Nino, et elles seules : un Heritier par camp, et des
    carrees qui peuvent bouger des deux cotes. Pour le reste on ne juge rien —
    dix Gardes d'un cote, c'est permis.
    """
    plat = "".join(grille)
    if plat.count("h") != 1 or plat.count("H") != 1:
        return "heritier"
    for majuscule in (False, True):
        if not _fug_carree_mobile(grille, majuscule):
            return "carrees"
    return None'''

REMPLACEMENT = '''# Combien de cases doivent rester libres pour qu'une position se joue.
_FUG_VIDES_MIN = 3


def _fug_refus(grille):
    """Pourquoi cette position ne peut pas servir de depart, ou None.

    Les regles de Nino, et elles seules : un Heritier par camp, un Chevalier au
    plus par camp, des carrees qui peuvent bouger des deux cotes, et au moins
    trois cases libres. Pour le reste on ne juge rien — dix Gardes d'un cote,
    c'est permis.
    """
    plat = "".join(grille)
    if plat.count("h") != 1 or plat.count("H") != 1:
        return "heritier"
    # Un Chevalier au plus par camp. Zero est permis : en mettre n'est pas
    # obligatoire. Deux ne l'est pas — le composeur n'en pose jamais un second,
    # mais un code ecrit a la main peut en porter dix.
    if plat.count("c") > 1 or plat.count("C") > 1:
        return "chevalier"
    for majuscule in (False, True):
        if not _fug_carree_mobile(grille, majuscule):
            return "carrees"
    # Un plateau presque plein ne laisse nulle part ou aller : rien ne peut
    # avancer, et la partie serait nulle d'entree comme avec des carrees
    # bloquees. Un tiret par case libre, il suffit de les compter.
    if plat.count("-") < _FUG_VIDES_MIN:
        return "vides"
    return None'''


CORRECTIONS = [
    ("_fug_refus : trois cases libres et un Chevalier", MOTIF, REMPLACEMENT),
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
            print("patch_position.py doit avoir ete applique avant celui-ci.")
            return 1

    corrige = source
    for _, motif, remplacement in CORRECTIONS:
        corrige = corrige.replace(motif, remplacement)

    horodatage = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    sauvegarde = "%s.avant-regles-%s" % (chemin, horodatage)
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
