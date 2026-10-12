# -*- coding: utf-8 -*-
"""Le matchmaking : qui s'apparie, et ce qu'une coupure de socket lui fait.

Nino : « Le match making ne marche pas. On est deux a attendre en 15min mais
ca ne trouve jamais l'autre. »

Le serveur, lui, apparie correctement. Ce qu'il fait AUSSI, c'est retirer un
joueur de sa file des que sa socket tombe — et le client d'alors ne s'y
remettait jamais. Une coupure d'une seconde suffisait donc a sortir un joueur
de la file sans rien lui dire.

Ce test montre les deux : l'appariement marche, la coupure le casse, et la
remise en file le repare.

USAGE
    python3 test_matchmaking.py <port>

Le serveur doit tourner en local (voir README.md). N'ecrit rien.
"""
import json
import sys
import time
import urllib.request

import socketio

PORT = sys.argv[1] if len(sys.argv) > 1 else "5200"
resultats = []


def http(path, payload):
    req = urllib.request.Request(
        "http://127.0.0.1:%s%s" % (PORT, path),
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read())


class Joueur(object):
    """Un client, avec ou sans la remise en file du correctif."""

    def __init__(self, pseudo, remet_en_file=True):
        self.pseudo = pseudo
        self.remet = remet_en_file
        self.recu = []
        self.recherche = None
        try:
            r = http("/register", {"pseudo": pseudo, "password": "motdepasse"})
        except Exception:
            r = {}
        if not r.get("ok"):
            r = http("/login", {"pseudo": pseudo, "password": "motdepasse"})
        self.token = r["token"]
        self.c = None
        self.connecter()

    def connecter(self):
        """Connexion, ou RECONNEXION apres une coupure."""
        if self.c:
            try:
                self.c.disconnect()
            except Exception:
                pass
        self.c = socketio.Client(reconnection=False)
        for ev in ("auth_ok", "auth_erreur", "recherche_en_cours",
                   "partie_trouvee", "recherche_timeout"):
            self.c.on(ev, self._noter(ev))
        self.c.connect("http://127.0.0.1:%s" % PORT,
                       transports=["websocket"], wait_timeout=10)
        # Exactement ce que fait le client : « auth », puis aussitot la
        # recherche encore en cours, sans aucune attente entre les deux.
        self.c.emit("auth", {"token": self.token})
        if self.remet and self.recherche is not None:
            self.c.emit("chercher_partie", self.recherche)

    def _noter(self, ev):
        def h(data=None):
            self.recu.append(ev)
        return h

    def cherche(self, params):
        self.recherche = params
        self.c.emit("chercher_partie", params)

    def annule(self):
        self.recherche = None
        self.c.emit("annuler_recherche", {})

    def trouve(self):
        return "partie_trouvee" in self.recu

    def ferme(self):
        try:
            self.c.disconnect()
        except Exception:
            pass


def verifie(titre, condition, detail=""):
    resultats.append(bool(condition))
    print("%-52s %s" % (titre, "OK" if condition else "ECHEC"))
    if detail:
        print("      %s" % detail)


PARAMS = {"objectif": "partie", "cadence": "5", "random": False}
n = int(time.time()) % 100000


def paire(suffixe, remet=True):
    a = Joueur("MmA%d%s" % (n, suffixe), remet)
    b = Joueur("MmB%d%s" % (n, suffixe), remet)
    time.sleep(0.5)
    return a, b


# ── 1. Le cas normal : ca marche ──────────────────────────────────────────
a, b = paire("x")
a.cherche(PARAMS)
time.sleep(0.4)
b.cherche(PARAMS)
time.sleep(1.5)
verifie("memes criteres : apparies", a.trouve() and b.trouve())
a.ferme(); b.ferme()

# ── 2. Criteres differents : jamais apparies, et c'est voulu ──────────────
for i, (titre, autre) in enumerate((
        ("cadences differentes", {"objectif": "partie", "cadence": "15",
                                  "random": False}),
        ("l'un en random, l'autre non", {"objectif": "partie",
                                         "cadence": "5", "random": True}))):
    # Suffixe SANS accent ni apostrophe : c'est un pseudo, le serveur les
    # refuse et le test echouait sur un 401 au lieu de mesurer quoi que ce
    # soit.
    a, b = paire("d%d" % i)
    a.cherche(PARAMS)
    time.sleep(0.4)
    b.cherche(autre)
    time.sleep(1.2)
    verifie("%s : PAS apparies (voulu)" % titre,
            not a.trouve() and not b.trouve())
    a.ferme(); b.ferme()

# ── 3. LE BUG : une coupure sort de la file, sans rien dire ───────────────
a, b = paire("bug", remet=False)
a.cherche(PARAMS)
time.sleep(0.5)
a.connecter()          # coupure + reconnexion, SANS se remettre dans la file
time.sleep(0.4)
b.cherche(PARAMS)
time.sleep(1.5)
verifie("sans remise en file, une coupure les separe a jamais",
        not a.trouve(),
        "c'est le bug : l'application affichait encore « recherche »")
a.ferme(); b.ferme()

# ── 4. LE CORRECTIF : on se remet dans la file ────────────────────────────
a, b = paire("fix", remet=True)
a.cherche(PARAMS)
time.sleep(0.5)
a.connecter()
time.sleep(0.4)
b.cherche(PARAMS)
time.sleep(1.5)
verifie("avec remise en file : apparies malgre la coupure",
        a.trouve() and b.trouve())
a.ferme(); b.ferme()

# ── 5. Et meme apres trois coupures d'affilee ─────────────────────────────
a, b = paire("ter", remet=True)
a.cherche(PARAMS)
for _ in range(3):
    time.sleep(0.3)
    a.connecter()
time.sleep(0.4)
b.cherche(PARAMS)
time.sleep(1.5)
verifie("trois coupures d'affilee : apparies quand meme",
        a.trouve() and b.trouve())
a.ferme(); b.ferme()

# ── 6. Une recherche ANNULEE ne revient pas toute seule ───────────────────
a, b = paire("ann", remet=True)
a.cherche(PARAMS)
time.sleep(0.3)
a.annule()
time.sleep(0.3)
a.connecter()
time.sleep(0.4)
b.cherche(PARAMS)
time.sleep(1.2)
verifie("une recherche annulee ne revient pas a la reconnexion",
        not a.trouve())
a.ferme(); b.ferme()

print("\n%d/%d" % (sum(resultats), len(resultats)))
sys.exit(0 if all(resultats) else 1)
