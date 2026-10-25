# -*- coding: utf-8 -*-
"""Les zones de ralliement choisies, cote serveur.

Une position composee peut desormais dire OU chaque camp rallie. Le `.fug`
porte alors deux lignes de plus, en tete, avant la lettre du trait :

    rr-----/--r-r--/B/sgshgsg/gnnnnns/.../SGSHGSG

Sept caracteres chacune, `r` pour une case de ralliement et `-` pour le
reste ; la premiere est celle des Blancs, la seconde celle des Noirs. Un
`.fug` qui ne les porte pas decrit la position d'origine (`--rrr--` des deux
cotes), et se lit donc exactement comme avant.

POURQUOI CE PATCH EXISTE. `_fug_lire` comptait les parties separees par des
barres obliques et en exigeait NEUF. Un `.fug` a zones choisies en compte
onze : le serveur repondait `position_illisible` et le defi n'etait jamais
cree. C'est tout ce qui lui manquait — il ne juge pas les zones, il n'a pas a
les connaitre : elles voyagent avec la position et chaque client les applique.

CE QUI CHANGE, ET RIEN D'AUTRE
    - `_fug_lire` accepte NEUF ou ONZE parties, et verifie les deux lignes de
      ralliement quand elles sont la : sept caracteres, `r` ou `-`, pas
      d'autre lettre.
    - une seule des deux lignes reste un refus : elles vont par deux, et une
      position a moitie decrite vaut moins que rien.

N'ENLEVE RIEN. Les positions deja enregistrees n'ont pas les deux lignes et
continuent de se lire. Le refus d'une position injouable ne bouge pas : un
Heritier par camp, des carrees qui peuvent bouger des deux cotes.

USAGE
    python3 patch_ralliement.py /chemin/vers/server.py

Le script REFUSE d'ecrire si un motif n'est pas trouve exactement une fois, y
compris sur un fichier deja corrige. Une sauvegarde horodatee est posee a
cote avant toute ecriture.
"""
import datetime
import hashlib
import io
import os
import shutil
import sys

# ── _fug_lire accepte les deux lignes de ralliement ─────────────────────────
MOTIF_LIRE = '''def _fug_lire(ligne):
    """Lit un .fug d'une ligne. Rend (grille, trait) ou None si mal forme.

    `grille[r][c]` porte la lettre telle qu'ecrite — la casse dit le camp —
    et la rangee 0 est do1..si1.
    """
    parties = (ligne or "").strip().split("/")
    if len(parties) != _FUG_RANGEES + 1:
        return None
    trait = parties[0].strip().upper()'''

REMPLACEMENT_LIRE = '''def _fug_ligne_ralliement(ligne):
    """Vrai si cette partie est une ligne de ralliement bien formee.

    Sept caracteres, `r` pour une case de ralliement et `-` pour le reste.
    Aucune ambiguite avec la ligne du trait, qui n'en fait qu'un.
    """
    if len(ligne) != _FUG_COLS:
        return False
    for ch in ligne:
        if ch.lower() not in ("r", "-"):
            return False
    return True


def _fug_lire(ligne):
    """Lit un .fug d'une ligne. Rend (grille, trait) ou None si mal forme.

    `grille[r][c]` porte la lettre telle qu'ecrite — la casse dit le camp —
    et la rangee 0 est do1..si1.

    Les deux lignes de ralliement, quand elles sont la, precedent la lettre
    du trait. Le serveur ne les juge pas : il verifie seulement qu'elles sont
    lisibles, et les laisse voyager avec la position. Ce sont les clients qui
    savent ce qu'une zone de ralliement veut dire.
    """
    parties = (ligne or "").strip().split("/")
    # Neuf parties : le trait et les huit rangees. Onze : les deux lignes de
    # ralliement d'abord. Rien d'autre ne se lit.
    if len(parties) == _FUG_RANGEES + 3:
        for rall in parties[:2]:
            if not _fug_ligne_ralliement(rall.strip()):
                return None
        parties = parties[2:]
    elif len(parties) != _FUG_RANGEES + 1:
        return None
    trait = parties[0].strip().upper()'''

CORRECTIONS = [
    ("_fug_lire", MOTIF_LIRE, REMPLACEMENT_LIRE),
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
    sauvegarde = "%s.avant-ralliement-%s" % (chemin, horodatage)
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
