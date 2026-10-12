# -*- coding: utf-8 -*-
"""Quand l'ADVERSAIRE joue le coup qui me fait gagner, qui gagne ?

Cas reels : il pousse mon Heritier dans MON ralliement (je fugue, je gagne), ou
il ejecte son PROPRE Heritier (mat contre lui-meme). Dans les deux cas c'est le
joueur qui N'A PAS joue qui gagne.

On verifie aussi sous quel identifiant la partie est archivee : l'historique du
client ne montre que "online_" et "local_".
"""
import json, sys, time, urllib.request
PORT = sys.argv[1]
BASE = "http://127.0.0.1:%s" % PORT

def post(path, payload):
    req = urllib.request.Request(BASE + path, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read())

def compte(p):
    try:
        r = post("/register", {"pseudo": p, "password": "motdepasse"})
    except Exception:
        r = {}
    if not r.get("ok"):
        r = post("/login", {"pseudo": p, "password": "motdepasse"})
    return r["token"]

n = int(time.time()) % 100000
A, B = "GagA%d" % n, "GagB%d" % n
ta, tb = compte(A), compte(B)

def nouvelle_partie():
    post("/corr_defier", {"token": ta, "pseudo": B, "objectif": "partie"})
    jeux = post("/corr_list", {"token": tb})["games"]
    defi = [g for g in jeux if g["statut"] == "defi"][-1]
    post("/corr_repondre", {"token": tb, "game_id": defi["id"], "accepte": True})
    return defi["id"]

def etat(token, gid):
    for g in post("/corr_list", {"token": token})["games"]:
        if str(g["id"]) == str(gid):
            return g
    return None

def historique(token):
    return post("/list_games", {"token": token}).get("games", [])

# ── Cas 1 : celui qui joue annonce que c'est l'AUTRE qui gagne ──────────────
gid = nouvelle_partie()
mien = etat(ta, gid)
qui_commence = ta if mien["my_turn"] else tb
pseudo_joueur = A if mien["my_turn"] else B
ma_couleur = mien["ma_couleur"] if mien["my_turn"] else (
    "Noir" if mien["ma_couleur"] == "Blanc" else "Blanc")
autre_couleur = "Noir" if ma_couleur == "Blanc" else "Blanc"

post("/corr_jouer", {"token": qui_commence, "game_id": gid,
                     "notation": "Fa8*", "methode": "fugue",
                     "gagnant": autre_couleur})
fin = etat(ta, gid)
attendu = "0-1" if autre_couleur == "Noir" else "1-0"
print("joueur  : %s (%s)" % (pseudo_joueur, ma_couleur))
print("annonce : gagnant = %s" % autre_couleur)
print("resultat: %s   (attendu %s)  -> %s" % (
    fin["resultat"], attendu, "OK" if fin["resultat"] == attendu else "FAUX"))

uids = [g["game_uid"] for g in historique(ta)]
visibles = [u for u in uids if u.startswith("online_") or u.startswith("local_")]
print("archive : %s" % uids)
print("visible dans un onglet : %s" % ("OUI" if visibles else "NON"))

# ── Cas 2 : sans indication, l'ancien comportement tient (compatibilite) ───
gid2 = nouvelle_partie()
m2 = etat(ta, gid2)
tok2 = ta if m2["my_turn"] else tb
coul2 = m2["ma_couleur"] if m2["my_turn"] else (
    "Noir" if m2["ma_couleur"] == "Blanc" else "Blanc")
post("/corr_jouer", {"token": tok2, "game_id": gid2,
                     "notation": "Fa8*", "methode": "fugue"})
fin2 = etat(ta, gid2)
attendu2 = "1-0" if coul2 == "Blanc" else "0-1"
print("sans indication : %s (attendu %s) -> %s" % (
    fin2["resultat"], attendu2, "OK" if fin2["resultat"] == attendu2 else "FAUX"))
