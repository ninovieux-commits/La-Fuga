# -*- coding: utf-8 -*-
"""Le classement met les melos egaux au MEME rang.

Nino, capture a l'appui : « les personnes qui ont le meme melo doivent avoir
le meme classement. » Deux comptes a 1500 derriere un seul a 1530 se
lisaient deuxieme et troisieme ; ils sont deuxiemes tous les deux.

LA NUMEROTATION DES COMPETITIONS, dite 1-2-2-4. Le rang d'un compte est le
nombre de comptes qui font STRICTEMENT mieux, plus un. Deux ex aequo
deuxiemes sont donc suivis d'un quatrieme : la place sautee dit qu'il y a
trois personnes devant, et aucun des deux rangs affiches ne ment. L'autre
convention possible — 1-2-2-3 — garde les rangs serres mais fait croire au
quatrieme qu'il n'a que deux personnes devant lui.

ET MA LIGNE SUIT LA MEME REGLE, ce qui corrige un desaccord au passage :
elle departageait les melos egaux par le pseudo, si bien que le meme compte
pouvait se lire troisieme dans la liste et deuxieme sur sa propre ligne, en
bas du volet. Les deux calculs sont desormais le meme.

L'ORDRE D'AFFICHAGE NE CHANGE PAS : les ex aequo restent ranges par pseudo
croissant, et la liste reste celle des trente meilleurs.

USAGE
    python3 patch_classement_exaequo.py /chemin/vers/server.py

Le script REFUSE d'ecrire si le motif n'est pas trouve exactement une fois,
y compris sur un fichier deja corrige. Une sauvegarde horodatee est posee a
cote avant toute ecriture. Il demande `patch_classement.py` d'abord.
"""
import datetime
import hashlib
import io
import os
import shutil
import sys


# Le calcul des rangs, tel que `patch_classement.py` l'a pose.
MOTIF = '''        devant = base.execute(
            "SELECT COUNT(*) AS n FROM users WHERE %s > ?"
            " OR (%s = ? AND pseudo < ?)" % (colonne, colonne),
            (mon_melo, mon_melo, moi.get("pseudo") or "")).fetchone()["n"]
    except Exception:
        return jsonify({"ok": False, "error": "Classement indisponible"}), 500
    joueurs = [
        {
            "rang": rang,
            "pseudo": dict(ligne).get("pseudo") or "",
            "melo": _classement_melo(dict(ligne), colonne),
            "photo": dict(ligne).get("photo") or "",
        }
        for rang, ligne in enumerate(lignes, 1)
    ]'''

AJOUT = '''        # COMBIEN FONT STRICTEMENT MIEUX, et rien d'autre. Le pseudo ne
        # departage plus : a melo egal, le rang est egal.
        devant = base.execute(
            "SELECT COUNT(*) AS n FROM users WHERE %s > ?" % colonne,
            (mon_melo,)).fetchone()["n"]
    except Exception:
        return jsonify({"ok": False, "error": "Classement indisponible"}), 500
    # EX AEQUO. Nino : « les personnes qui ont le meme melo doivent avoir le
    # meme classement. » La liste arrive triee par melo decroissant : un
    # melo egal au precedent reprend donc son rang, et un melo inferieur
    # prend sa propre place. C'est le nombre de comptes qui font
    # strictement mieux, plus un.
    joueurs = []
    for place, ligne in enumerate(lignes, 1):
        brute = dict(ligne)
        melo = _classement_melo(brute, colonne)
        rang = joueurs[-1]["rang"] if joueurs and joueurs[-1]["melo"] == melo \\
            else place
        joueurs.append({
            "rang": rang,
            "pseudo": brute.get("pseudo") or "",
            "melo": melo,
            "photo": brute.get("photo") or "",
        })'''


def main():
    if len(sys.argv) < 2:
        print("usage: python3 patch_classement_exaequo.py /chemin/server.py")
        return 2
    chemin = sys.argv[1]
    if not os.path.isfile(chemin):
        print("introuvable : %s" % chemin)
        return 2

    source = io.open(chemin, encoding="utf-8").read()
    print("avant : %d lignes, sha256 %s"
          % (source.count("\n") + 1,
             hashlib.sha256(source.encode("utf-8")).hexdigest()))

    if "/classement" not in source:
        print("REFUS : la route /classement n'existe pas encore.")
        print("        Appliquer patch_classement.py d'abord.")
        return 1

    n = source.count(MOTIF)
    if n != 1:
        print("REFUS : le motif a ete trouve %d fois au lieu d'une." % n)
        print("        Le fichier n'est pas celui attendu, ou il est deja")
        print("        corrige. Rien n'a ete ecrit.")
        return 1

    sortie = source.replace(MOTIF, AJOUT, 1)

    try:
        compile(sortie, chemin, "exec")
    except SyntaxError as e:
        print("REFUS : le resultat ne compile pas (%s). Rien n'a ete ecrit." % e)
        return 1

    horodatage = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    sauvegarde = "%s.avant-exaequo-%s" % (chemin, horodatage)
    shutil.copy2(chemin, sauvegarde)
    print("sauvegarde : %s" % sauvegarde)

    io.open(chemin, "w", encoding="utf-8").write(sortie)
    print("apres : %d lignes, sha256 %s"
          % (sortie.count("\n") + 1,
             hashlib.sha256(sortie.encode("utf-8")).hexdigest()))
    print("ECRIT.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
