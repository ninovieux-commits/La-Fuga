# -*- coding: utf-8 -*-
"""La nulle vaut ZERO point, et l'adversaire est prevenu.

Quatre corrections, toutes dans la correspondance :

  1. Une nulle etait archivee « [Points "2"] ». La regle du fichier est
     pourtant claire : mat et papatte valent 1, fugue/temps/abandon valent 2,
     une nulle n'en donne AUCUN. Le score de confrontation, lui, etait deja
     juste — rien n'y est ajoute pour une nulle. C'est le .nmc qui mentait.

  2. Proposer la nulle ne prevenait personne. L'adversaire ne l'apprenait
     qu'en ouvrant l'application, sans savoir qu'il avait quelque chose a y
     faire.

  3. Accepter la nulle ne prevenait personne non plus : celui qui avait
     propose ne savait pas que sa partie etait finie.

  4. Abandonner ne prevenait personne : l'adversaire gagnait deux points sans
     l'apprendre.

Les textes suivent la meme forme que les autres notifications : le pseudo en
titre, le reste en corps.

NE COUVRE PAS le refus d'une nulle : la partie continue, c'est au tour de
l'autre de jouer, et il le verra en ouvrant la partie.

USAGE
    python3 patch_nulle.py /chemin/vers/server.py

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

CORRECTIONS = [
    (
        "1. une nulle vaut zero point dans le .nmc",
        '''         resultat, methode,
         "1" if methode in ("mat", "papatte") else "2")''',
        '''         resultat, methode,
         # Mat et papatte valent 1, fugue/temps/abandon valent 2, une nulle
         # n'en donne AUCUN. Elle etait archivee a 2, comme une fugue.
         "0" if methode == "nulle"
         else ("1" if methode in ("mat", "papatte") else "2"))''',
    ),
    (
        "2. proposer la nulle previent l'adversaire",
        '''    conn.execute("UPDATE corr_games SET nulle_par=? WHERE id=?", (me["id"], gid))
    conn.commit()
    conn.close()
    return jsonify({"ok": True})''',
        '''    conn.execute("UPDATE corr_games SET nulle_par=? WHERE id=?", (me["id"], gid))
    conn.commit()
    conn.close()
    # Notification push : sans elle, l'adversaire ne decouvrait la proposition
    # qu'en ouvrant l'application, sans savoir qu'il avait a y repondre.
    try:
        _autre = (row["noir_user_id"] if me["id"] == row["blanc_user_id"]
                  else row["blanc_user_id"])
        _notify_user(_autre, "turn", me["pseudo"], "propose la nulle",
                     {"type": "corr_nulle", "game_id": str(gid)})
    except Exception:
        pass
    return jsonify({"ok": True})''',
    ),
    (
        "3. accepter la nulle previent celui qui l'a proposee",
        '''        try:
            if final_row:
                _archive_corr_game(final_row, "nulle", "nulle")
        except Exception as e:
            print("[corr archive] erreur :", e)
        return jsonify({"ok": True, "nulle": True})''',
        '''        try:
            if final_row:
                _archive_corr_game(final_row, "nulle", "nulle")
        except Exception as e:
            print("[corr archive] erreur :", e)
        # Celui qui avait propose ne savait pas que sa partie etait finie.
        try:
            _notify_user(nulle_par, "turn", me["pseudo"],
                         "accepte la nulle — partie terminée",
                         {"type": "corr_fin", "game_id": str(gid),
                          "resultat": "nulle"})
        except Exception:
            pass
        return jsonify({"ok": True, "nulle": True})''',
    ),
    (
        "4. abandonner previent l'adversaire",
        '''    # Archiver dans l'historique (sauf si c'était juste un refus de défi)
    try:
        if final_row and row["statut"] == "en_cours":
            _archive_corr_game(final_row, resultat, "abandon")
    except Exception as e:
        print("[corr archive] erreur :", e)
    return jsonify({"ok": True})''',
        '''    # Archiver dans l'historique (sauf si c'était juste un refus de défi)
    try:
        if final_row and row["statut"] == "en_cours":
            _archive_corr_game(final_row, resultat, "abandon")
    except Exception as e:
        print("[corr archive] erreur :", e)
    # L'adversaire gagnait deux points sans jamais l'apprendre. Un refus de
    # defi, lui, ne notifie rien : il n'y avait pas de partie.
    try:
        if row["statut"] == "en_cours":
            _notify_user(opp_uid, "turn", me["pseudo"],
                         "abandonne — partie terminée",
                         {"type": "corr_fin", "game_id": str(gid),
                          "resultat": resultat})
    except Exception:
        pass
    return jsonify({"ok": True})''',
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

    problemes = []
    for titre, motif, _ in CORRECTIONS:
        n = source.count(motif)
        if n != 1:
            problemes.append("  - %s : motif trouve %d fois (attendu 1)"
                             % (titre, n))
    if problemes:
        print("Rien n'a ete modifie. Motifs non conformes :")
        print("\n".join(problemes))
        print("\nSi le fichier est DEJA corrige, c'est normal : rien a faire.")
        print("Sinon, appliquez d'abord patch_notifs.py.")
        return 1

    resultat = source
    for _, motif, remplacement in CORRECTIONS:
        resultat = resultat.replace(motif, remplacement, 1)

    # Garde-fou : les notifications ajoutees passent toutes le pseudo en
    # titre, comme les six autres. Aucun titre en dur ne doit reapparaitre.
    if '"La Fuga"' in resultat:
        print("Un titre « La Fuga » subsiste : patch_notifs.py n'a pas ete "
              "applique. Rien n'a ete ecrit.")
        return 1
    # Six notifications d'avant, plus les trois ajoutees ici.
    trouves = (resultat.count('_notify_user(')
               - resultat.count('def _notify_user('))
    if trouves != 9:
        print("Attendu 9 appels a _notify_user, trouve %d : rien n'a ete "
              "ecrit." % trouves)
        return 1

    try:
        compile(resultat, chemin, "exec")
    except SyntaxError as e:
        print("Le resultat ne compile pas (%s). Rien n'a ete ecrit." % e)
        return 1

    horodatage = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    sauvegarde = "%s.avant-nulle-%s" % (chemin, horodatage)
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
