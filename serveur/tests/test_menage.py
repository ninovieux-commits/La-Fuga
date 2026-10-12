# -*- coding: utf-8 -*-
"""Verifie que le menage fait vraiment son travail :
 1. un defi direct jamais resolu disparait de DEFIS,
 2. un jeton expire est supprime de la base,
 3. une partie sans aucun evenement est oubliee,
 4. une partie AVEC des evenements n'est JAMAIS oubliee."""
import json, sqlite3, sys, time, urllib.request
import socketio
PORT = sys.argv[1]; DB = sys.argv[2]
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

t1, t2 = compte("MNino"), compte("MAna")
c1 = socketio.Client(reconnection=False); c2 = socketio.Client(reconnection=False)
c1.connect(BASE, transports=["websocket"], wait_timeout=10)
c2.connect(BASE, transports=["websocket"], wait_timeout=10)
c1.emit("auth", {"token": t1}); c2.emit("auth", {"token": t2}); time.sleep(0.4)

# 1. defi jamais resolu
c1.emit("defier", {"pseudo_cible": "MAna", "objectif": "3", "cadence": "5"})
time.sleep(0.5)
avant = sante()["etat"]["defis"]

# 3+4. deux parties : une muette, une active
gids = []
for _ in range(2):
    c1.emit("chercher_partie", {"objectif": "3", "cadence": "5"}); time.sleep(0.2)
    c2.emit("chercher_partie", {"objectif": "3", "cadence": "5"}); time.sleep(0.6)
etat_av = sante()["etat"]["parties"]

# 2. jeton expire insere a la main
conn = sqlite3.connect(DB)
conn.execute("INSERT INTO tokens (token, user_id, created_at) VALUES (?,?,?)",
             ("jeton_perime", 1, 1))       # created_at = 1970 -> largement expire
conn.commit()
n_av = conn.execute("SELECT COUNT(*) FROM tokens WHERE token='jeton_perime'").fetchone()[0]
conn.close()

print("avant menage : defis=%d parties=%d jeton_perime=%d" % (avant, etat_av, n_av))

# On garde UNE partie vivante en envoyant des evenements pendant l'attente.
vivante = None
# on retrouve un game_id en demandant un etat : on prend le dernier
# partie_trouvee vu par c1
recu = []
c1.on("partie_trouvee", lambda d: recu.append(d["game_id"]))
c1.emit("chercher_partie", {"objectif": "9", "cadence": "9"}); time.sleep(0.2)
c2.emit("chercher_partie", {"objectif": "9", "cadence": "9"}); time.sleep(0.6)
if recu:
    vivante = recu[-1]
etat_av2 = sante()["etat"]["parties"]
print("parties avant attente : %d (dont 1 maintenue vivante : %s)"
      % (etat_av2, bool(vivante)))

t0 = time.time()
while time.time() - t0 < 14:
    if vivante:
        c1.emit("envoyer_etat", {"game_id": vivante, "plateau": "ping"})
    time.sleep(1)

ap = sante()
conn = sqlite3.connect(DB)
n_ap = conn.execute("SELECT COUNT(*) FROM tokens WHERE token='jeton_perime'").fetchone()[0]
conn.close()
print("apres menage : defis=%d parties=%d jeton_perime=%d" % (
    ap["etat"]["defis"], ap["etat"]["parties"], n_ap))
ok = True
if ap["etat"]["defis"] != 0:
    print("ECHEC : le defi non resolu n'a pas ete purge"); ok = False
if n_ap != 0:
    print("ECHEC : le jeton expire n'a pas ete supprime"); ok = False
if vivante and ap["etat"]["parties"] < 1:
    print("ECHEC : la partie ACTIVE a ete oubliee (grave)"); ok = False
if ap["etat"]["parties"] > 1:
    print("ECHEC : les parties muettes n'ont pas ete oubliees (%d restent)"
          % ap["etat"]["parties"]); ok = False
try:
    c1.disconnect(); c2.disconnect()
except Exception:
    pass
print("OK — le menage purge ce qu'il faut et rien de plus" if ok else "PROBLEME")
sys.exit(0 if ok else 1)
