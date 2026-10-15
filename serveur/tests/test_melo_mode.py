# -*- coding: utf-8 -*-
"""Le melo annonce est-il celui du MODE joue ?

Nino : « il faudrait que le melo indique durant une partie soit le melo du
mode correspondant (soit standard soit random) ».

Ce test donne a deux comptes des classements VOLONTAIREMENT tres differents
dans les deux colonnes, puis regarde ce que le serveur annonce :

  - sur une partie de correspondance STANDARD : le melo standard ;
  - sur une partie de correspondance RANDOM   : le melo random ;
  - sur un defi en direct RANDOM              : le melo random ;
  - et `_get_user_melo`, qui sert de base a l'Elo de la partie suivante d'un
    match, doit lire la colonne du mode.

Il se lance contre un serveur LOCAL, jamais la production : il cree des
comptes et ecrit dans la base.

    python3 test_melo_mode.py 5400
"""
import json
import os
import sqlite3
import sys
import urllib.error
import urllib.request

PORT = sys.argv[1] if len(sys.argv) > 1 else "5400"
BASE = "http://127.0.0.1:%s" % PORT
DB = sys.argv[2] if len(sys.argv) > 2 else "lafuga.db"

MELO_STANDARD = {"Mode1": 1800, "Mode2": 1200}
MELO_RANDOM = {"Mode1": 1310, "Mode2": 1690}

resultats = []


def verifie(nom, obtenu, attendu):
    ok = (obtenu == attendu)
    resultats.append((ok, nom, obtenu, attendu))
    print("  %s %-52s obtenu %s, attendu %s"
          % ("ok " if ok else "ECHEC", nom, obtenu, attendu))


def http(path, payload):
    req = urllib.request.Request(
        BASE + path, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        try:
            return json.loads(e.read())
        except Exception:
            return {"ok": False, "_code": e.code}
    except Exception as e:
        return {"ok": False, "_err": repr(e)[:120]}


def compte(pseudo):
    """Cree le compte s'il n'existe pas, et rend son jeton."""
    r = http("/register", {"pseudo": pseudo, "password": "mdp-essai"})
    if not r.get("ok"):
        r = http("/login", {"pseudo": pseudo, "password": "mdp-essai"})
    return r.get("token", "")


def pose_les_melos():
    """Ecrit les deux colonnes en base, pour que la difference saute aux yeux."""
    conn = sqlite3.connect(DB)
    for pseudo in MELO_STANDARD:
        conn.execute("UPDATE users SET melo=?, melo_random=? "
                     "WHERE pseudo_lower=?",
                     (MELO_STANDARD[pseudo], MELO_RANDOM[pseudo],
                      pseudo.lower()))
    conn.commit()
    conn.close()


def partie_corr(jeton_a, pseudo_b, jeton_b, random):
    """Un defi par correspondance, accepte. Rend l'id de la partie."""
    r = http("/corr_defier", {"token": jeton_a, "pseudo": pseudo_b,
                              "objectif": "partie", "couleur": "Blanc",
                              "mode": "random" if random else "",
                              "cadence": "15"})
    gid = r.get("game_id") or r.get("id")
    if gid is None:
        for g in http("/corr_list", {"token": jeton_b}).get("games", []):
            if g.get("statut") == "defi":
                gid = g.get("id")
    # `accepte`, et non `reponse` : le serveur ne lit que ce mot-la, et un
    # defi non accepte reste au statut « defi » — visible dans la liste, mais
    # invisible de la route publique, qui ne montre que les parties en cours.
    http("/corr_repondre", {"token": jeton_b, "game_id": gid,
                            "accepte": True})
    return gid


def melo_vu_par(jeton, gid):
    """Le melo de l'adversaire, tel que la liste des parties l'annonce."""
    for g in http("/corr_list", {"token": jeton}).get("games", []):
        if g.get("id") == gid:
            return g.get("adversaire_melo")
    return None


def main():
    print("Serveur %s, base %s" % (BASE, DB))
    jeton_a = compte("Mode1")
    jeton_b = compte("Mode2")
    if not jeton_a or not jeton_b:
        print("ECHEC : comptes impossibles a creer")
        return 1
    pose_les_melos()

    print("\nCorrespondance")
    gid_std = partie_corr(jeton_a, "Mode2", jeton_b, random=False)
    verifie("partie standard : Mode1 voit le standard de Mode2",
            melo_vu_par(jeton_a, gid_std), MELO_STANDARD["Mode2"])
    verifie("partie standard : Mode2 voit le standard de Mode1",
            melo_vu_par(jeton_b, gid_std), MELO_STANDARD["Mode1"])

    gid_rnd = partie_corr(jeton_a, "Mode2", jeton_b, random=True)
    verifie("partie RANDOM : Mode1 voit le random de Mode2",
            melo_vu_par(jeton_a, gid_rnd), MELO_RANDOM["Mode2"])
    verifie("partie RANDOM : Mode2 voit le random de Mode1",
            melo_vu_par(jeton_b, gid_rnd), MELO_RANDOM["Mode1"])

    # La meme chose SANS le cache de `_corr_bulk` : une partie demandee seule
    # passe par l'autre branche du code, et elle doit dire la meme chose.
    print("\nLa meme, vue par quelqu un qui REGARDE jouer")
    for jeton, pseudo, gid, attendu in (
            (jeton_a, "Mode2", gid_rnd, MELO_RANDOM["Mode2"]),
            (jeton_a, "Mode2", gid_std, MELO_STANDARD["Mode2"])):
        vu = None
        for g in http("/corr_list_public",
                      {"token": jeton_b, "pseudo": "Mode1"}).get("games", []):
            if g.get("id") == gid:
                vu = g.get("adversaire_melo")
        verifie("route publique, partie %s" % ("random" if gid == gid_rnd
                                               else "standard"), vu, attendu)

    print("\n_get_user_melo : la base de l'Elo de la partie suivante")
    sys.path.insert(0, os.path.dirname(os.path.abspath(DB)) or ".")
    try:
        import server as srv
        conn = sqlite3.connect(DB)
        uid = conn.execute("SELECT id FROM users WHERE pseudo_lower='mode1'"
                           ).fetchone()[0]
        conn.close()
        verifie("mode standard", srv._get_user_melo(uid),
                MELO_STANDARD["Mode1"])
        try:
            vu = srv._get_user_melo(uid, True)
        except TypeError:
            vu = "ne prend pas le mode"
        verifie("mode random", vu, MELO_RANDOM["Mode1"])

        # `_corr_game_dict` a DEUX chemins : avec le cache d'une liste, et
        # sans. Les deux routes passent un cache ; seule une lecture directe
        # emprunte l'autre, et elle doit dire la meme chose.
        print("\n_corr_game_dict sans cache")
        conn = sqlite3.connect(DB)
        conn.row_factory = sqlite3.Row
        uid_b = conn.execute("SELECT id FROM users WHERE pseudo_lower='mode2'"
                             ).fetchone()[0]
        for gid, attendu in ((gid_std, MELO_STANDARD["Mode1"]),
                             (gid_rnd, MELO_RANDOM["Mode1"])):
            row = conn.execute("SELECT * FROM corr_games WHERE id=?",
                               (gid,)).fetchone()
            d = srv._corr_game_dict(row, uid_b)
            verifie("sans cache, partie %s" % ("random" if gid == gid_rnd
                                               else "standard"),
                    d.get("adversaire_melo"), attendu)
        conn.close()
    except Exception as e:
        verifie("import du serveur", repr(e)[:60], "importable")

    rates = [r for r in resultats if not r[0]]
    print("\n%d verifications, %d echecs" % (len(resultats), len(rates)))
    return 1 if rates else 0


if __name__ == "__main__":
    sys.exit(main())
