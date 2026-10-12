# -*- coding: utf-8 -*-
"""La correspondance previent-elle EN DIRECT ?

Avant patch_direct.py, aucune route de correspondance n'emettait le moindre
evenement Socket.IO : l'application ouverte ne pouvait qu'attendre sa
prochaine relecture, jusqu'a quatre secondes plus tard.

Ce test prend deux VRAIS clients, leur fait jouer une partie en
correspondance, et mesure ce que l'adversaire recoit — et en combien de
temps.

USAGE
    python3 test_direct.py <port>

Le serveur doit tourner en local (voir README.md). Ecrit deux comptes de
sonde et une partie dans SA base ; a lancer sur un serveur de test.
"""
import json
import sys
import time
import urllib.request

import socketio

PORT = sys.argv[1] if len(sys.argv) > 1 else "5300"
BASE = "http://127.0.0.1:%s" % PORT
resultats = []


def http(path, payload):
    req = urllib.request.Request(
        BASE + path, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read())


class Joueur(object):
    def __init__(self, pseudo):
        self.pseudo = pseudo
        self.recu = []
        try:
            r = http("/register", {"pseudo": pseudo, "password": "motdepasse"})
        except Exception:
            r = {}
        if not r.get("ok"):
            r = http("/login", {"pseudo": pseudo, "password": "motdepasse"})
        self.token = r["token"]
        self.c = socketio.Client(reconnection=False)
        self.c.on("maj_directe", lambda d=None: self.recu.append(d or {}))
        self.c.connect(BASE, transports=["websocket"], wait_timeout=10)
        self.c.emit("auth", {"token": self.token})
        time.sleep(0.4)

    def post(self, path, payload):
        payload = dict(payload)
        payload["token"] = self.token
        return http(path, payload)

    def attend(self, *types, **kw):
        """Combien de temps pour recevoir l'un de ces evenements ? None si rien."""
        delai = kw.get("delai", 3.0)
        t0 = time.time()
        while time.time() - t0 < delai:
            for d in self.recu:
                if d.get("type") in types:
                    return time.time() - t0
            time.sleep(0.02)
        return None

    def oublie(self):
        self.recu = []

    def ferme(self):
        try:
            self.c.disconnect()
        except Exception:
            pass


def verifie(titre, condition, detail=""):
    resultats.append(bool(condition))
    print("%-54s %s" % (titre, "OK" if condition else "ECHEC"))
    if detail:
        print("      %s" % detail)


n = int(time.time()) % 100000
a = Joueur("DirA%d" % n)
b = Joueur("DirB%d" % n)

# ── Le defi : B doit l'apprendre tout de suite ────────────────────────────
r = a.post("/corr_defier", {"pseudo": b.pseudo, "objectif": "partie"})
t = b.attend("defi_corr")
verifie("un defi en correspondance arrive en direct", t is not None,
        "recu en %.3f s" % t if t else "RIEN recu en 3 s")
gid = r.get("game_id") or r.get("id")
if gid is None:
    liste = b.post("/corr_list", {})
    for g in liste.get("games", []):
        if g.get("statut") == "defi":
            gid = g.get("id")

# ── L'acceptation : A doit l'apprendre tout de suite ──────────────────────
a.oublie()
b.post("/corr_repondre", {"game_id": gid, "accepte": True})
# Le defieur a pu tirer les Noirs : il ne recoit alors aucune notification
# « a vous de jouer », mais son ecran doit quand meme apprendre que la partie
# a commence — c'est « corr_maj », en direct seulement.
t = a.attend("corr_turn", "corr_maj")
verifie("l'acceptation du defi arrive en direct", t is not None,
        "recu en %.3f s" % t if t else "RIEN recu en 3 s")

# ── Le coup : c'est LA plainte ────────────────────────────────────────────
# Qui joue en premier ? Celui dont c'est le tour d'apres le serveur.
etat = {g["id"]: g for g in a.post("/corr_list", {}).get("games", [])}
tour_a = etat.get(gid, {}).get("my_turn") or etat.get(gid, {}).get("myTurn")
joueur, autre = (a, b) if tour_a else (b, a)
autre.oublie()
joueur.post("/corr_jouer", {"game_id": gid, "notation": "Mi2-Mi3"})
t = autre.attend("corr_turn")
verifie("un coup joue arrive en direct chez l'adversaire", t is not None,
        "recu en %.3f s" % t if t else "RIEN recu en 3 s")
if t is not None:
    verifie("et il porte le game_id, pour savoir quoi relire",
            any(str(d.get("game_id")) == str(gid)
                for d in autre.recu if d.get("type") == "corr_turn"))
    verifie("en moins d'une demi-seconde", t < 0.5, "%.3f s" % t)

# ── Le chat de la partie ──────────────────────────────────────────────────
joueur.oublie()
autre.post("/corr_chat_send", {"game_id": gid, "texte": "bien joue"})
t = joueur.attend("corr_chat")
verifie("un message du chat de la partie arrive en direct", t is not None,
        "recu en %.3f s" % t if t else "RIEN recu en 3 s")

# ── La nulle ──────────────────────────────────────────────────────────────
autre.oublie()
joueur.post("/corr_proposer_nulle", {"game_id": gid})
t = autre.attend("corr_nulle")
verifie("une proposition de nulle arrive en direct", t is not None,
        "recu en %.3f s" % t if t else "RIEN recu en 3 s")

# ── Un message prive hors partie ──────────────────────────────────────────
b.oublie()
a.post("/send_message", {"pseudo": b.pseudo, "text": "coucou"})
t = b.attend("message")
verifie("un message prive arrive en direct", t is not None,
        "recu en %.3f s" % t if t else "RIEN recu en 3 s")

# ── Et jamais a soi-meme ──────────────────────────────────────────────────
a.oublie()
a.post("/send_message", {"pseudo": b.pseudo, "text": "encore"})
time.sleep(0.6)
verifie("l'expediteur n'est pas prevenu de son propre envoi", not a.recu,
        "recu : %s" % a.recu)

a.ferme()
b.ferme()
print("\n%d/%d" % (sum(resultats), len(resultats)))
sys.exit(0 if all(resultats) else 1)
