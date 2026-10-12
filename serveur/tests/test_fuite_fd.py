# -*- coding: utf-8 -*-
"""Reproduit la panne de production : compte les descripteurs de fichiers qui
pointent sur lafuga.db pendant un usage normal de l'appli (corr_list sonde
toutes les 3 s). C'est CE chiffre qui montait jusqu'a 1024 sur le serveur."""
import json, os, sys, time, urllib.request
PORT = sys.argv[1]; PID = int(sys.argv[2]); NG = int(sys.argv[3]); TOURS = int(sys.argv[4])
BASE = "http://127.0.0.1:%s" % PORT

def post(path, payload):
    req = urllib.request.Request(BASE + path, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

def fd_db():
    """Descripteurs du serveur pointant sur la base."""
    n = 0
    d = "/proc/%d/fd" % PID
    for f in os.listdir(d):
        try:
            if "lafuga.db" in os.readlink(os.path.join(d, f)):
                n += 1
        except OSError:
            pass
    return n

def compte(p):
    try: r = post("/register", {"pseudo": p, "password": "motdepasse"})
    except Exception: r = {}
    if not r.get("ok"): r = post("/login", {"pseudo": p, "password": "motdepasse"})
    return r["token"]

ta, tb = compte("FNino"), compte("FAna")
# NG parties de correspondance acceptees (chacune coute 3 requetes dans corr_list)
for i in range(NG):
    post("/corr_defier", {"token": ta, "pseudo": "FAna", "objectif": "3", "random": False})
for g in post("/corr_list", {"token": tb}).get("games", []):
    if g.get("statut") == "defi" and not g.get("is_defieur"):
        post("/corr_repondre", {"token": tb, "game_id": g["id"], "accepte": True})
parties = len(post("/corr_list", {"token": ta}).get("games", []))

time.sleep(1)
depart = fd_db()
print("parties de correspondance : %d" % parties)
print("descripteurs sur la base, au repos : %d" % depart)
print()
print(" appels   fd base   pic")
pic = depart
for t in range(TOURS):
    for k in range(25):
        post("/corr_list", {"token": ta})
        post("/corr_list", {"token": tb})
        n = fd_db()
        if n > pic: pic = n
    print("%7d %9d %5d" % ((t + 1) * 50, fd_db(), pic), flush=True)
time.sleep(2)
fin = fd_db()
print()
print("au repos apres %d appels : %d descripteurs (depart %d, pic %d)"
      % (TOURS * 50, fin, depart, pic))
