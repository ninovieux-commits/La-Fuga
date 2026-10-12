# -*- coding: utf-8 -*-
"""Exporte les parties de correspondance terminees. NE MODIFIE RIEN.

Le bug corrige le 26 septembre donnait la victoire a celui qui jouait le coup
final, meme quand ce coup faisait gagner l'AUTRE (pousser l'Heritier adverse
dans son ralliement, ejecter son propre Heritier). Les parties jouees avant
cette correction gardent donc un resultat faux, dans leur fiche, dans
l'historique, et dans le score de confrontation.

La notation seule ne permet pas de trancher : une poussee s'ecrit « Do1-Do2> »
sans dire QUI a ete pousse. Il faut rejouer chaque partie avec le moteur du
jeu. Ce script se contente donc d'EXPORTER de quoi le faire.

Il ouvre la base en LECTURE SEULE (mode=ro) : meme un bug de ce script ne
peut rien abimer.

USAGE
    python3 exporter_corresp.py /chemin/vers/lafuga.db [sortie.json]

Ecrit un fichier JSON (par defaut « corresp_export.json » dans le dossier
courant) et affiche un resume.
"""
import io
import json
import os
import sqlite3
import sys


def colonnes(conn, table):
    try:
        return [r[1] for r in conn.execute("PRAGMA table_info(%s)" % table)]
    except Exception:
        return []


def lignes(conn, requete, params=()):
    cur = conn.execute(requete, params)
    noms = [d[0] for d in cur.description]
    return [dict(zip(noms, r)) for r in cur.fetchall()]


def main():
    if len(sys.argv) not in (2, 3):
        print(__doc__)
        return 2
    chemin = sys.argv[1]
    sortie = sys.argv[2] if len(sys.argv) == 3 else "corresp_export.json"
    if not os.path.isfile(chemin):
        print("Base introuvable : %s" % chemin)
        return 1

    # LECTURE SEULE. Si le fichier est verrouille par le serveur, on lit quand
    # meme : SQLite en WAL autorise les lecteurs pendant les ecritures.
    uri = "file:%s?mode=ro" % os.path.abspath(chemin).replace("?", "%3f")
    conn = sqlite3.connect(uri, uri=True, timeout=10)

    jeux = colonnes(conn, "corr_games")
    if not jeux:
        print("Table corr_games absente : mauvaise base ?")
        return 1

    parties = lignes(
        conn,
        "SELECT * FROM corr_games WHERE statut='termine' ORDER BY id")
    scores = lignes(conn, "SELECT * FROM corr_scores")
    users = lignes(conn, "SELECT id, pseudo FROM users")

    # Les archives d'historique correspondantes : c'est la qu'est ecrit le
    # resultat que le client affiche.
    archives = lignes(
        conn,
        "SELECT id, user_id, game_uid, resultat, methode, played_at "
        "FROM games WHERE cadence='corr' ORDER BY id")

    conn.close()

    donnees = {
        "version": 1,
        "parties": parties,
        "corr_scores": scores,
        "users": users,
        "archives": archives,
    }
    with io.open(sortie, "w", encoding="utf-8") as f:
        json.dump(donnees, f, ensure_ascii=False, indent=1)

    par_pseudo = {u["id"]: u["pseudo"] for u in users}
    print("Parties de correspondance terminees : %d" % len(parties))
    paires = {}
    for p in parties:
        cle = tuple(sorted([p.get("blanc_user_id"), p.get("noir_user_id")]))
        paires.setdefault(cle, 0)
        paires[cle] += 1
    print("Paires de joueurs concernees : %d" % len(paires))
    for (a, b), n in sorted(paires.items(), key=lambda kv: -kv[1]):
        print("  %-14s vs %-14s  %d partie(s)"
              % (par_pseudo.get(a, a), par_pseudo.get(b, b), n))
    print("Lignes corr_scores : %d" % len(scores))
    for s in scores:
        print("  %-14s %s  -  %-14s %s"
              % (par_pseudo.get(s.get("user_a"), s.get("user_a")),
                 s.get("score_a"),
                 par_pseudo.get(s.get("user_b"), s.get("user_b")),
                 s.get("score_b")))
    print("Archives d'historique (cadence corr) : %d" % len(archives))
    print("\nEcrit : %s (%d octets)"
          % (os.path.abspath(sortie), os.path.getsize(sortie)))
    print("La base n'a pas ete modifiee (ouverte en lecture seule).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
