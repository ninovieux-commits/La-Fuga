# -*- coding: utf-8 -*-
"""Un evenement malformé ne doit ni couper la connexion du joueur, ni faire
tomber le serveur. On envoie volontairement des donnees aberrantes sur chaque
evenement, puis on verifie que le serveur repond toujours et que le joueur peut
continuer a jouer normalement."""
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

tok = compte("RNino")
recu = []
c = socketio.Client(reconnection=False)
for ev in ("auth_ok", "auth_erreur", "recherche_en_cours", "defi_echec"):
    c.on(ev, lambda d=None, e=ev: recu.append(e))
c.connect(BASE, transports=["websocket"], wait_timeout=10)
c.emit("auth", {"token": tok}); time.sleep(0.4)
assert "auth_ok" in recu, "auth de depart ratee : test invalide"

ABERRANT = [
    ("auth", None), ("auth", "pas un dict"), ("auth", 42), ("auth", []),
    ("chercher_partie", None), ("chercher_partie", {"objectif": {"a": 1}}),
    ("chercher_partie", "x"),
    ("annuler_recherche", None), ("annuler_recherche", 7),
    ("defier", None), ("defier", {"pseudo_cible": None}), ("defier", {}),
    ("repondre_defi", None), ("repondre_defi", {"defi_id": ["liste"]}),
    ("annuler_defi", None),
    ("jouer_coup", None), ("jouer_coup", {"game_id": {"dict": "interdit"}}),
    ("jouer_coup", {"game_id": "inexistant", "notation": None}),
    ("fin_partie", None), ("fin_partie", {"game_id": "x", "methode": 12}),
    ("pret_partie_suivante", None), ("pret_partie_suivante", {"game_id": []}),
    ("abandonner_match", None), ("proposer_nulle", None),
    ("chat", None), ("chat", {"game_id": None, "texte": {"non": "texte"}}),
    ("envoyer_etat", None), ("envoyer_etat", "brut"),
]
for ev, data in ABERRANT:
    try:
        c.emit(ev, data)
    except Exception as e:
        print("  (emit refuse cote client : %s %r)" % (ev, e))
    time.sleep(0.05)
time.sleep(1.5)

# Le serveur repond-il toujours, et la session est-elle toujours utilisable ?
vivant = sante()
recu.clear()
c.emit("chercher_partie", {"objectif": "3", "cadence": "5"}); time.sleep(0.6)
c.emit("annuler_recherche", {}); time.sleep(0.3)
r = post("/ping", {"token": tok})
ok = vivant.get("ok") and r.get("ok") and "recherche_en_cours" in recu and c.connected
print("serveur vivant : %s | HTTP toujours OK : %s | session toujours utilisable : %s"
      % (bool(vivant.get("ok")), bool(r.get("ok")),
         "recherche_en_cours" in recu and c.connected))
print("erreurs attrapees et comptees : %s" % json.dumps(vivant.get("erreurs_sio", {})))
try:
    c.disconnect()
except Exception:
    pass
print("OK" if ok else "PROBLEME")
sys.exit(0 if ok else 1)
