# -*- coding: utf-8 -*-
"""Le melo annonce dans un DEFI est-il celui du mode defie ?

Deux comptes, des classements volontairement tres differents dans les deux
colonnes, et un defi envoye deux fois : une fois en standard, une fois en
Random Fuga. Le popup « X vous defie » doit annoncer le classement du mode.

A lancer contre un serveur LOCAL : il cree des comptes.

    python3 test_defi_melo.py 5400 lafuga.db
"""
import json
import sqlite3
import sys
import time
import urllib.error
import urllib.request

import socketio

PORT = sys.argv[1] if len(sys.argv) > 1 else "5400"
DB = sys.argv[2] if len(sys.argv) > 2 else "lafuga.db"
BASE = "http://127.0.0.1:%s" % PORT

STANDARD = {"DefiA": 1900, "DefiB": 1100}
RANDOM = {"DefiA": 1250, "DefiB": 1750}

resultats = []


def verifie(nom, obtenu, attendu):
    ok = (obtenu == attendu)
    resultats.append(ok)
    print("  %s %-44s obtenu %s, attendu %s"
          % ("ok " if ok else "ECHEC", nom, obtenu, attendu))


def http(path, payload):
    req = urllib.request.Request(
        BASE + path, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        try:
            return json.loads(e.read())
        except Exception:
            return {"ok": False}


class Joueur:
    def __init__(self, pseudo):
        self.pseudo = pseudo
        self.recu = []
        r = http("/register", {"pseudo": pseudo, "password": "motdepasse"})
        if not r.get("ok"):
            r = http("/login", {"pseudo": pseudo, "password": "motdepasse"})
        self.token = r["token"]
        self.c = socketio.Client(reconnection=False)
        for ev in ("auth_ok", "defi_recu", "defi_envoye", "defi_echec"):
            self.c.on(ev, self._faire(ev))
        self.c.connect(BASE, transports=["websocket"], wait_timeout=10)

    def _faire(self, ev):
        def h(data=None):
            self.recu.append((ev, data))
        return h

    def emit(self, ev, data=None):
        self.c.emit(ev, data or {})

    def dernier(self, ev):
        for e, d in reversed(self.recu):
            if e == ev:
                return d
        return None


def main():
    conn = sqlite3.connect(DB)
    a = Joueur("DefiA")
    b = Joueur("DefiB")
    for pseudo in STANDARD:
        conn.execute("UPDATE users SET melo=?, melo_random=? "
                     "WHERE pseudo_lower=?",
                     (STANDARD[pseudo], RANDOM[pseudo], pseudo.lower()))
    conn.commit()
    conn.close()

    # L'authentification socket relit les melos en base : on la fait APRES
    # les avoir poses, sinon CONNECTED garde ceux d'avant.
    a.emit("auth", {"token": a.token})
    b.emit("auth", {"token": b.token})
    time.sleep(1.2)

    print("Defi STANDARD")
    a.emit("defier", {"pseudo_cible": "DefiB", "objectif": "partie",
                      "cadence": "15", "random": False})
    time.sleep(1.2)
    recu = b.dernier("defi_recu") or {}
    verifie("DefiB voit le standard de DefiA",
            recu.get("defieur_melo"), STANDARD["DefiA"])
    a.emit("annuler_defi", {"defi_id": recu.get("defi_id")})
    time.sleep(0.6)

    print("Defi RANDOM")
    b.recu = []
    a.emit("defier", {"pseudo_cible": "DefiB", "objectif": "partie",
                      "cadence": "15", "random": True})
    time.sleep(1.2)
    recu = b.dernier("defi_recu") or {}
    verifie("DefiB voit le RANDOM de DefiA",
            recu.get("defieur_melo"), RANDOM["DefiA"])
    verifie("et le defi se dit bien Random", recu.get("random"), True)

    for j in (a, b):
        try:
            j.c.disconnect()
        except Exception:
            pass

    rates = [r for r in resultats if not r]
    print("\n%d verifications, %d echecs" % (len(resultats), len(rates)))
    return 1 if rates else 0


if __name__ == "__main__":
    sys.exit(main())
