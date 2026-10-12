# -*- coding: utf-8 -*-
"""Le menage ne doit JAMAIS retirer un joueur reellement connecte de CONNECTED.
(Piege : le sid Socket.IO et le sid engine.io ne sont pas le meme identifiant.)"""
import json, sys, time, urllib.request
import socketio
PORT = sys.argv[1]
BASE = "http://127.0.0.1:%s" % PORT
def post(path, payload):
    req = urllib.request.Request(BASE + path, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r: return json.loads(r.read())
def sante():
    return json.loads(urllib.request.urlopen(BASE + "/health", timeout=20).read())
def compte(p):
    try: r = post("/register", {"pseudo": p, "password": "motdepasse"})
    except Exception: r = {}
    if not r.get("ok"): r = post("/login", {"pseudo": p, "password": "motdepasse"})
    return r["token"]
toks = [compte("XJ%d" % i) for i in range(3)]
cs = []
for t in toks:
    c = socketio.Client(reconnection=False)
    c.connect(BASE, transports=["websocket"], wait_timeout=10)
    c.emit("auth", {"token": t})
    cs.append(c)
time.sleep(0.8)
av = sante()["etat"]
print("juste apres auth      : connectes=%d sockets_eio=%d" % (av["connectes"], av["sockets_eio"]))
# on laisse passer plusieurs tours de menage
time.sleep(12)
ap = sante()["etat"]
print("apres 12 s de menage  : connectes=%d sockets_eio=%d" % (ap["connectes"], ap["sockets_eio"]))
# les joueurs peuvent-ils toujours agir ? (chercher_partie exige CONNECTED)
recu = []
cs[0].on("recherche_en_cours", lambda d=None: recu.append(1))
cs[0].on("auth_erreur", lambda d=None: recu.append("erreur"))
cs[0].emit("chercher_partie", {"objectif": "3", "cadence": "5"})
time.sleep(0.8)
ok = (ap["connectes"] == 3) and recu == [1]
print("le joueur est toujours reconnu : %s (%r)" % (recu == [1], recu))
for c in cs:
    try: c.disconnect()
    except Exception: pass
print("OK" if ok else "ECHEC : le menage a purge des joueurs connectes")
sys.exit(0 if ok else 1)
