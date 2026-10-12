# -*- coding: utf-8 -*-
"""Compte EXACTEMENT combien de connexions SQLite et de requetes coutent les
deux routes que l'appli sonde en boucle, avec N parties de correspondance."""
import json, sys, urllib.request
JEU, CPT, N = sys.argv[1], sys.argv[2], int(sys.argv[3])
def post(path, payload):
    req = urllib.request.Request("http://127.0.0.1:%s%s" % (JEU, path),
        data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r: return json.loads(r.read())
def cpt(reset=False):
    u = "http://127.0.0.1:%s/%s" % (CPT, "reset" if reset else "")
    return json.loads(urllib.request.urlopen(u, timeout=10).read())
def compte(pseudo):
    try: r = post("/register", {"pseudo": pseudo, "password": "motdepasse"})
    except Exception: r = {}
    if not r.get("ok"): r = post("/login", {"pseudo": pseudo, "password": "motdepasse"})
    return r["token"]
ta, tb = compte("KNino"), compte("KAna")
for i in range(N):
    post("/corr_defier", {"token": ta, "pseudo": "KAna", "objectif": "3", "random": False})
r = post("/corr_list", {"token": tb})
for g in r.get("games", []):
    if g.get("statut") == "defi" and not g.get("is_defieur"):
        post("/corr_repondre", {"token": tb, "game_id": g["id"], "accepte": True})
for g in post("/corr_list", {"token": ta}).get("games", []):
    for k in range(3):
        post("/corr_chat_send", {"token": ta, "game_id": g["id"], "texte": "m%d" % k})
for k in range(20):
    post("/send_message", {"token": ta, "pseudo": "KAna", "text": "m%d" % k})
for route, payload in (("/corr_list", {"token": ta}),
                       ("/list_conversations", {"token": ta})):
    cpt(reset=True)
    post(route, payload)
    c = cpt()
    print("%-20s %d parties -> %2d connexions SQLite, %2d requetes"
          % (route, N, c["connect"], c["execute"]))
