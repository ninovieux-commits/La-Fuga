# -*- coding: utf-8 -*-
"""Remet leur vrai resultat aux parties de correspondance mal enregistrees.

Le serveur donnait la victoire a celui qui jouait le coup final. Trois parties
en ont ete faussees, etablies en les REJOUANT une a une avec le moteur du jeu
(`tool/verifier_corresp.dart`), pas en les devinant :

  partie 2  (random /18-52)  0-1 -> 1-0   nino fugue au coup 29 ; celia joue
                                          son coup de rattrapage sans egaliser
  partie 8                   0-1 -> 1-0   celia ejecte son PROPRE Heritier au
                                          coup 36 : mat contre elle-meme
  partie 18                  1-0 -> 0-1   celia pousse l'Heritier de nino dans
                                          le ralliement de nino : il fugue

  score nino/celia           7-5  -> 12-0

Les quinze autres parties terminees sont justes, et les scores nino/lilou
(2-0) et nino/mesange (4-0) ne bougent pas.

CE QUI EST MODIFIE
  - corr_games.resultat        des trois parties
  - games.resultat             des six lignes d'archive (deux par partie)
  - games.nmc_text             la ligne [Resultat "..."] de ces archives
  - corr_scores                la ligne nino/celia, remise a 12-0

GARDE-FOUS
  - une SAUVEGARDE de la base entiere est posee a cote avant toute ecriture ;
  - chaque partie est reconnue a l'empreinte de ses coups : si un seul coup
    a change depuis l'analyse, le script REFUSE tout ;
  - chaque valeur attendue avant correction est verifiee ; deja corrige, il
    ne fait rien ;
  - tout se joue dans UNE transaction : en cas de pepin, rien n'est ecrit.

USAGE
    python3 corriger_resultats.py /chemin/vers/lafuga.db          (essai a blanc)
    python3 corriger_resultats.py /chemin/vers/lafuga.db --ecrire (pour de vrai)

Sans --ecrire, le script ne fait que verifier et montrer ce qu'il ferait.
"""
import datetime
import hashlib
import io
import os
import re
import shutil
import sqlite3
import sys

# partie -> (empreinte des coups, resultat attendu AVANT, resultat APRES)
PARTIES = {
    2: ("87463ce0846613e50576a42cf942a47d9dfb5b4be78e40451ffe7b3e68de72d0",
        "0-1", "1-0"),
    8: ("ef51444ceda25ab732579c136e693a9487ef5055dc892b09f1a6183061ca62cd",
        "0-1", "1-0"),
    18: ("eb5724cda391850dad22b0509a15fff25b54500b9f352575aa7ad871b355783d",
         "1-0", "0-1"),
}

# (user_a, user_b) -> (score_a attendu, score_b attendu, score_a, score_b)
SCORES = {
    (1, 2): (7, 5, 12, 0),
}


def main():
    if len(sys.argv) not in (2, 3):
        print(__doc__)
        return 2
    chemin = sys.argv[1]
    ecrire = len(sys.argv) == 3 and sys.argv[2] == "--ecrire"
    if len(sys.argv) == 3 and not ecrire:
        print("Second argument inconnu : %s (attendu --ecrire)" % sys.argv[2])
        return 2
    if not os.path.isfile(chemin):
        print("Base introuvable : %s" % chemin)
        return 1

    conn = sqlite3.connect(chemin, timeout=15)
    conn.row_factory = sqlite3.Row

    problemes = []
    plan = []

    for gid, (empreinte, avant, apres) in sorted(PARTIES.items()):
        row = conn.execute(
            "SELECT id, resultat, methode, moves_text, blanc_pseudo, "
            "noir_pseudo FROM corr_games WHERE id=?", (gid,)).fetchone()
        if row is None:
            problemes.append("partie %d : introuvable" % gid)
            continue
        vue = hashlib.sha256((row["moves_text"] or "").encode("utf-8")) \
            .hexdigest()
        if vue != empreinte:
            problemes.append(
                "partie %d : les coups ont change depuis l'analyse\n"
                "            attendu %s\n            trouve  %s"
                % (gid, empreinte, vue))
            continue
        if row["resultat"] == apres:
            print("partie %d : deja corrigee (%s)" % (gid, apres))
            continue
        if row["resultat"] != avant:
            problemes.append(
                "partie %d : resultat inattendu « %s » (attendu « %s »)"
                % (gid, row["resultat"], avant))
            continue
        plan.append((gid, avant, apres, row["blanc_pseudo"],
                     row["noir_pseudo"]))

    scores_a_faire = []
    for (ua, ub), (aa, ab, na, nb) in sorted(SCORES.items()):
        row = conn.execute(
            "SELECT score_a, score_b FROM corr_scores "
            "WHERE user_a=? AND user_b=?", (ua, ub)).fetchone()
        if row is None:
            problemes.append("score %d/%d : ligne absente" % (ua, ub))
            continue
        if (row["score_a"], row["score_b"]) == (na, nb):
            print("score %d/%d : deja corrige (%d-%d)" % (ua, ub, na, nb))
            continue
        if (row["score_a"], row["score_b"]) != (aa, ab):
            problemes.append(
                "score %d/%d : %d-%d inattendu (attendu %d-%d)"
                % (ua, ub, row["score_a"], row["score_b"], aa, ab))
            continue
        scores_a_faire.append((ua, ub, aa, ab, na, nb))

    if problemes:
        print("\nRIEN N'A ETE MODIFIE. Verifications en echec :")
        for p in problemes:
            print("  - %s" % p)
        conn.close()
        return 1

    if not plan and not scores_a_faire:
        print("\nTout est deja a jour : rien a faire.")
        conn.close()
        return 0

    print("\nCe qui sera corrige :")
    for gid, avant, apres, bp, np_ in plan:
        n = conn.execute("SELECT COUNT(*) c FROM games WHERE game_uid IN "
                         "(?,?)", ("corr_%d" % gid,
                                   "online_corr%d" % gid)).fetchone()["c"]
        print("  partie %-3d %s (B) vs %s (N) : %s -> %s  "
              "(%d ligne(s) d'historique)" % (gid, bp, np_, avant, apres, n))
    for ua, ub, aa, ab, na, nb in scores_a_faire:
        print("  score %d/%d : %d-%d -> %d-%d" % (ua, ub, aa, ab, na, nb))

    if not ecrire:
        print("\nEssai a blanc : la base n'a pas ete touchee.")
        print("Relancez avec --ecrire pour appliquer.")
        conn.close()
        return 0

    conn.close()
    horodatage = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    sauvegarde = "%s.avant-resultats-%s" % (chemin, horodatage)
    shutil.copy2(chemin, sauvegarde)
    for suffixe in ("-wal", "-shm"):
        if os.path.exists(chemin + suffixe):
            shutil.copy2(chemin + suffixe, sauvegarde + suffixe)
    print("\nSauvegarde : %s" % sauvegarde)

    conn = sqlite3.connect(chemin, timeout=15)
    conn.row_factory = sqlite3.Row
    touches = 0
    try:
        conn.execute("BEGIN IMMEDIATE")
        for gid, _avant, apres, _bp, _np in plan:
            conn.execute("UPDATE corr_games SET resultat=? WHERE id=?",
                         (apres, gid))
            uids = ("corr_%d" % gid, "online_corr%d" % gid)
            for arch in conn.execute(
                    "SELECT id, nmc_text FROM games WHERE game_uid IN (?,?)",
                    uids).fetchall():
                texte = arch["nmc_text"] or ""
                neuf = re.sub(r'\[Resultat "[^"]*"\]',
                              '[Resultat "%s"]' % apres, texte, count=1)
                conn.execute(
                    "UPDATE games SET resultat=?, nmc_text=? WHERE id=?",
                    (apres, neuf, arch["id"]))
                touches += 1
        for ua, ub, _aa, _ab, na, nb in scores_a_faire:
            conn.execute("UPDATE corr_scores SET score_a=?, score_b=? "
                         "WHERE user_a=? AND user_b=?", (na, nb, ua, ub))
        conn.commit()
    except Exception as e:
        conn.rollback()
        conn.close()
        print("ECHEC : %s\nRien n'a ete ecrit (transaction annulee)." % e)
        print("La sauvegarde reste : %s" % sauvegarde)
        return 1

    print("%d partie(s) corrigee(s), %d ligne(s) d'historique, "
          "%d score(s)." % (len(plan), touches, len(scores_a_faire)))
    print("\nVerification apres coup :")
    for gid, _a, apres, _b, _n in plan:
        r = conn.execute("SELECT resultat FROM corr_games WHERE id=?",
                         (gid,)).fetchone()
        print("  partie %-3d -> %s  %s"
              % (gid, r["resultat"], "OK" if r["resultat"] == apres else "FAUX"))
    for ua, ub, _aa, _ab, na, nb in scores_a_faire:
        r = conn.execute("SELECT score_a, score_b FROM corr_scores "
                         "WHERE user_a=? AND user_b=?", (ua, ub)).fetchone()
        print("  score %d/%d -> %d-%d  %s"
              % (ua, ub, r["score_a"], r["score_b"],
                 "OK" if (r["score_a"], r["score_b"]) == (na, nb) else "FAUX"))
    conn.close()
    print("\nRedemarrez le service :  sudo systemctl restart lafuga")
    return 0


if __name__ == "__main__":
    sys.exit(main())
