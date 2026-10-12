# -*- coding: utf-8 -*-
"""La nulle : zero point, et chacun prevenu.

Le serveur doit tourner sous `run_trace.py`.

    python3 test_nulle.py <port> <chemin/vers/trace.log>
"""
import io
import json
import re
import sys
import time
import urllib.request

PORT = sys.argv[1]
LOG = sys.argv[2]
BASE = "http://127.0.0.1:%s" % PORT
resultats = []


def post(path, payload):
    req = urllib.request.Request(
        BASE + path, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        return json.loads(e.read())


def compte(p):
    r = post("/register", {"pseudo": p, "password": "motdepasse"})
    if not r.get("ok"):
        r = post("/login", {"pseudo": p, "password": "motdepasse"})
    return r["token"]


def traces_depuis(n):
    lignes = io.open(LOG, encoding="utf-8", errors="replace").readlines()
    return [l[l.index("[TRACE]"):].rstrip("\n")
            for l in lignes[n:] if "[TRACE]" in l]


def marque():
    return len(io.open(LOG, encoding="utf-8", errors="replace").readlines())


def verifie(titre, condition, detail=""):
    resultats.append(bool(condition))
    print("%-42s %s" % (titre, "OK" if condition else "ECHEC"))
    if detail:
        print("      %s" % detail)


n = int(time.time()) % 100000
A, B = "NulA%d" % n, "NulB%d" % n
ta, tb = compte(A), compte(B)


def nouvelle_partie():
    post("/corr_defier", {"token": ta, "pseudo": B, "objectif": "partie"})
    d = [g for g in post("/corr_list", {"token": tb})["games"]
         if g["statut"] == "defi"][-1]
    post("/corr_repondre", {"token": tb, "game_id": d["id"], "accepte": True})
    return d["id"]


def etat(token, gid):
    for g in post("/corr_list", {"token": token})["games"]:
        if str(g["id"]) == str(gid):
            return g
    return None


def score():
    r = post("/search_user", {"token": ta, "pseudo": B})
    return (r.get("h2h_corr_moi"), r.get("h2h_corr_lui"))


avant = score()

# ── Une nulle proposee, refusee, reproposee, acceptee ──────────────────────
gid = nouvelle_partie()
m = etat(ta, gid)
tok_trait, tok_autre = (ta, tb) if m["my_turn"] else (tb, ta)
pseudo_trait, pseudo_autre = (A, B) if m["my_turn"] else (B, A)

post("/corr_jouer", {"token": tok_trait, "game_id": gid,
                     "notation": "Do1-Do2"})

d = marque()
post("/corr_proposer_nulle", {"token": tok_trait, "game_id": gid})
time.sleep(0.6)
t = traces_depuis(d)
verifie("proposer la nulle previent l adversaire",
        any("| %s | propose la nulle" % pseudo_trait in s for s in t),
        " / ".join(t) or "aucune trace")

vu = etat(tok_autre, gid)
verifie("l adversaire a bien une nulle a repondre",
        vu and vu.get("nulle_a_repondre") is True,
        "nulle_a_repondre=%s" % (vu or {}).get("nulle_a_repondre"))

post("/corr_repondre_nulle", {"token": tok_autre, "game_id": gid,
                              "accepte": False})
apres_refus = etat(tok_autre, gid)
verifie("refusee, la partie continue",
        apres_refus and apres_refus["statut"] == "en_cours"
        and not apres_refus.get("nulle_a_repondre"))

post("/corr_proposer_nulle", {"token": tok_trait, "game_id": gid})
d = marque()
post("/corr_repondre_nulle", {"token": tok_autre, "game_id": gid,
                              "accepte": True})
time.sleep(0.6)
t = traces_depuis(d)
verifie("accepter previent celui qui a propose",
        any("| %s | accepte la nulle" % pseudo_autre in s for s in t),
        " / ".join(t) or "aucune trace")

fin = etat(ta, gid)
verifie("la partie est nulle",
        fin and fin["resultat"] == "nulle",
        "resultat=%s" % (fin or {}).get("resultat"))

apres = score()
verifie("la nulle ne donne AUCUN point (0/0)",
        apres == avant,
        "avant %s -> apres %s" % (avant, apres))

nmc = post("/get_game", {"token": ta, "game_uid": "online_corr%s" % gid})
texte = nmc.get("nmc_text", "")
pts = re.search(r'\[Points "([^"]*)"\]', texte)
verifie("le .nmc archive la nulle a 0 point",
        pts and pts.group(1) == "0",
        "[Points \"%s\"]" % (pts.group(1) if pts else "absent"))

# ── L'abandon previent l'adversaire ────────────────────────────────────────
gid2 = nouvelle_partie()
d = marque()
post("/corr_abandon", {"token": ta, "game_id": gid2})
time.sleep(0.6)
t = traces_depuis(d)
verifie("abandonner previent l adversaire",
        any("| %s | abandonne" % A in s for s in t),
        " / ".join(t) or "aucune trace")

apres2 = score()
verifie("l abandon donne bien 2 points a l adversaire",
        apres2[1] == apres[1] + 2,
        "avant %s -> apres %s" % (apres, apres2))

print("\n%d/%d" % (sum(resultats), len(resultats)))
sys.exit(0 if all(resultats) else 1)
