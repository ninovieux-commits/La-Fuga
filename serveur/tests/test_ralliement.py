# -*- coding: utf-8 -*-
"""Le serveur lit-il un .fug qui porte ses zones de ralliement ?

CE TEST NE PARLE A AUCUN SERVEUR. Il applique `patch_ralliement.py` au texte
que `patch_position.py` installe, execute le `_fug_lire` obtenu, et le met a
l'epreuve. Rien n'est ecrit nulle part : il peut tourner n'importe ou, y
compris sur une machine qui n'a pas de base.

C'est voulu. Le defaut qu'il garde ne demandait pas de serveur pour se
produire — `_fug_lire` exigeait NEUF parties separees par des barres obliques,
un `.fug` a zones choisies en compte ONZE, et le defi etait refuse avec
`position_illisible` avant meme d'atteindre la base.

USAGE
    python3 test_ralliement.py
"""
import importlib.util
import os
import sys

ICI = os.path.dirname(os.path.abspath(__file__))
SERVEUR = os.path.dirname(ICI)

RANGEES = ["sgshgsg", "gnnnnns", "-------", "-------",
           "-------", "-------", "GNNNNNS", "SGSHGSG"]

resultats = []


def verifie(nom, condition, detail=""):
    resultats.append((nom, bool(condition), detail))
    print("%s  %s%s" % ("OK  " if condition else "ECHEC", nom,
                        ("  — %s" % detail) if detail and not condition
                        else ""))


def charge(nom):
    spec = importlib.util.spec_from_file_location(
        nom, os.path.join(SERVEUR, nom + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    position = charge("patch_position")
    ralliement = charge("patch_ralliement")

    # Le serveur porte le texte pose par patch_position : c'est la-dessus que
    # le nouveau patch doit s'appliquer, et exactement une fois.
    serveur = position.REMPLACEMENT_HELPERS
    verifie("le motif se trouve une fois dans le serveur corrige",
            serveur.count(ralliement.MOTIF_LIRE) == 1,
            "trouve %d fois" % serveur.count(ralliement.MOTIF_LIRE))
    if serveur.count(ralliement.MOTIF_LIRE) != 1:
        return 1

    corrige = serveur.replace(ralliement.MOTIF_LIRE,
                              ralliement.REMPLACEMENT_LIRE)
    debut = corrige.index("# Sept colonnes")
    fin = corrige.index("def _corr_tirage_a_lacceptation")
    espace = {}
    exec(compile(corrige[debut:fin], "<serveur>", "exec"), espace)
    lire = espace["_fug_lire"]
    refus = espace["_fug_refus"]

    rangees = "/".join(RANGEES)

    # ── Ce qui doit se lire ───────────────────────────────────────────────
    for nom, code, trait_attendu in [
        ("un .fug d'avant se lit comme avant", "B/" + rangees, "Blanc"),
        ("avec les deux lignes de ralliement",
         "rr-----/--r-r--/N/" + rangees, "Noir"),
        ("et des zones vides des deux cotes",
         "-------/-------/B/" + rangees, "Blanc"),
        ("et des zones pleines", "rrrrrrr/rrrrrrr/B/" + rangees, "Blanc"),
    ]:
        lu = lire(code)
        if lu is None:
            verifie(nom, False, "refuse")
            continue
        grille, trait = lu
        verifie(nom,
                trait == trait_attendu
                and len(grille) == 8
                and all(len(r) == 7 for r in grille)
                and refus(grille) is None,
                "trait=%s" % trait)

    # ── Ce qui doit etre refuse ───────────────────────────────────────────
    for nom, code in [
        ("une seule ligne de ralliement : refuse", "rr-----/B/" + rangees),
        ("une lettre qui n'est ni r ni tiret : refuse",
         "rx-----/--r-r--/B/" + rangees),
        ("une ligne de six cases : refuse", "rr----/--r-r--/B/" + rangees),
        ("une rangee manquante : refuse",
         "rr-----/--r-r--/B/" + "/".join(RANGEES[:7])),
        ("un trait inconnu : refuse", "rr-----/--r-r--/X/" + rangees),
    ]:
        verifie(nom, lire(code) is None, "accepte a tort")

    # ── Ce que le serveur juge, et ce qu'il ne juge pas ───────────────────
    sans_heritier = list(RANGEES)
    sans_heritier[7] = "-------"
    lu = lire("rr-----/--r-r--/B/" + "/".join(sans_heritier))
    verifie("un camp sans Heritier reste refuse",
            lu is not None and refus(lu[0]) == "heritier")

    deux_chevaliers = list(RANGEES)
    deux_chevaliers[2] = "cc-----"
    lu = lire("B/" + "/".join(deux_chevaliers))
    verifie("deux Chevaliers passent, comme chez le client",
            lu is not None and refus(lu[0]) is None)

    rates = [n for n, ok, _ in resultats if not ok]
    print("")
    print("%d verifications, %d echec(s)" % (len(resultats), len(rates)))
    return 1 if rates else 0


if __name__ == "__main__":
    sys.exit(main())
