# -*- coding: utf-8 -*-
"""Point le plus sensible du menage : une partie EN COURS ne doit JAMAIS etre
oubliee, meme si elle dure plus longtemps que GAME_IDLE_TTL. On maintient une
partie avec des evenements pendant 5 fois le delai, et on verifie qu'elle est
toujours la ; une seconde partie, laissee muette, doit disparaitre."""
import json, sys, time, urllib.request
import socketio
PORT = sys.argv[1]
BASE = "http://127.0.0.1:%s" % PORT

def post(path, payload):
    req = urllib.request.Request(BASE + path, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read())

def sante():
    return json.loads(urllib.request.urlopen(BASE + "/health", timeout=20).read())

def compte(p):
    try:
        r = post("/register", {"pseudo": p, "password": "motdepasse"})
    except Exception:
        r = {}
    if not r.get("ok"):
        r = post("/login", {"pseudo": p, "password": "motdepasse"})
    return r["token"]

t1, t2 = compte("VNino"), compte("VAna")
vus1 = []
c1 = socketio.Client(reconnection=False); c2 = socketio.Client(reconnection=False)
c1.on("partie_trouvee", lambda d: vus1.append(d["game_id"]))
c1.connect(BASE, transports=["websocket"], wait_timeout=10)
c2.connect(BASE, transports=["websocket"], wait_timeout=10)
c1.emit("auth", {"token": t1}); c2.emit("auth", {"token": t2}); time.sleep(0.4)

# partie 1 : celle qu'on maintient vivante
c1.emit("chercher_partie", {"objectif": "3", "cadence": "5"}); time.sleep(0.3)
c2.emit("chercher_partie", {"objectif": "3", "cadence": "5"}); time.sleep(0.8)
assert vus1, "aucune partie creee : test invalide"
vivante = vus1[-1]
# partie 2 : muette
c1.emit("chercher_partie", {"objectif": "9", "cadence": "9"}); time.sleep(0.3)
c2.emit("chercher_partie", {"objectif": "9", "cadence": "9"}); time.sleep(0.8)
muette = [g for g in vus1 if g != vivante]
print("partie maintenue : %s | partie muette : %s | parties en memoire : %d"
      % (vivante[:8], (muette[-1][:8] if muette else "aucune"),
         sante()["etat"]["parties"]))

# on joue des coups pendant 5 x GAME_IDLE_TTL (ici 5 s -> 25 s)
t0 = time.time()
n = 0
while time.time() - t0 < 26:
    c1.emit("jouer_coup", {"game_id": vivante, "notation": "a1-b2", "clock_me": 200})
    n += 1
    time.sleep(1.5)
ap = sante()["etat"]["parties"]
print("apres 26 s et %d coups joues : %d partie(s) en memoire" % (n, ap))
ok = (ap == 1)
if not ok:
    print("ECHEC : attendu 1 (la partie active conservee, la muette oubliee)")
else:
    print("OK — la partie active est intacte, la muette a ete oubliee")
try:
    c1.disconnect(); c2.disconnect()
except Exception:
    pass
sys.exit(0 if ok else 1)
