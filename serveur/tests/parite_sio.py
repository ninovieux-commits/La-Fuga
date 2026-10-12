# -*- coding: utf-8 -*-
"""Parite Socket.IO : rejoue le meme scenario temps reel sur A (original) et
B (corrige), enregistre TOUS les evenements recus par chaque client, et compare
les deux sequences (les identifiants tires au hasard sont normalises)."""
import json, re, sys, time, urllib.request
import socketio

PA, PB = sys.argv[1], sys.argv[2]
VOLATILE_K = {"created_at", "updated_at", "ts", "adversaire_melo", "mon_melo"}


def http(port, path, payload):
    req = urllib.request.Request("http://127.0.0.1:%s%s" % (port, path),
                                 data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read())


class Joueur(object):
    def __init__(self, port, pseudo):
        self.pseudo = pseudo
        self.recu = []                      # [(pseudo, evenement, donnees)]
        try:
            r = http(port, "/register", {"pseudo": pseudo, "password": "motdepasse"})
        except Exception:
            r = {}
        if not r.get("ok"):
            r = http(port, "/login", {"pseudo": pseudo, "password": "motdepasse"})
        self.token = r["token"]
        self.c = socketio.Client(reconnection=False)
        for ev in ("auth_ok", "auth_erreur", "recherche_en_cours", "partie_trouvee",
                   "recherche_timeout", "coup_adverse", "chat_recu", "nulle_proposee",
                   "partie_terminee", "melo_maj", "match_continue", "match_over",
                   "match_abandonne", "adversaire_pret", "adversaire_deconnecte",
                   "adversaire_revenu", "reprise_partie", "defi_recu", "defi_envoye",
                   "defi_echec", "defi_refuse", "defi_annule", "message_recu",
                   "etat_partie"):
            self.c.on(ev, self._faire(ev))
        self.c.connect("http://127.0.0.1:%s" % port, transports=["websocket"],
                       wait_timeout=10)

    def _faire(self, ev):
        def h(data=None):
            self.recu.append((self.pseudo, ev, data))
        return h

    def emit(self, ev, data=None):
        self.c.emit(ev, data or {})


def scenario(port):
    n = Joueur(port, "SNino")
    a = Joueur(port, "SAna")
    n.emit("auth", {"token": n.token}); a.emit("auth", {"token": a.token})
    time.sleep(0.4)
    # matchmaking
    n.emit("chercher_partie", {"objectif": "3", "cadence": "5"})
    time.sleep(0.3)
    a.emit("chercher_partie", {"objectif": "3", "cadence": "5"})
    time.sleep(0.6)
    # retrouver le game_id et qui est Blanc
    gid, blanc = None, None
    for who, ev, d in n.recu + a.recu:
        if ev == "partie_trouvee":
            gid = d["game_id"]
            if d["couleur"] == "Blanc":
                blanc = who
    par = {"SNino": n, "SAna": a}
    b = par[blanc]; noir = par["SAna" if blanc == "SNino" else "SNino"]
    # un coup, un chat, un etat, une nulle
    b.emit("jouer_coup", {"game_id": gid, "notation": "a1-b2", "clock_me": 240})
    time.sleep(0.25)
    noir.emit("jouer_coup", {"game_id": gid, "notation": "c3-d4", "clock_me": 238})
    time.sleep(0.25)
    b.emit("chat", {"game_id": gid, "texte": "bien joue"})
    time.sleep(0.25)
    b.emit("envoyer_etat", {"game_id": gid, "plateau": "xyz"})
    time.sleep(0.25)
    noir.emit("proposer_nulle", {"game_id": gid})
    time.sleep(0.25)
    # fin de partie : le Noir perd par mat -> match a 3 points, il continue
    b.emit("fin_partie", {"game_id": gid, "methode": "mat", "loser_color": "Noir"})
    time.sleep(0.8)
    # partie suivante
    b.emit("pret_partie_suivante", {"game_id": gid})
    time.sleep(0.4)
    noir.emit("pret_partie_suivante", {"game_id": gid})
    time.sleep(0.8)
    gid2 = None
    for who, ev, d in n.recu + a.recu:
        if ev == "partie_trouvee" and d["game_id"] != gid:
            gid2 = d["game_id"]
    # abandon du match
    if gid2:
        noir.emit("abandonner_match", {"game_id": gid2})
        time.sleep(0.6)
    # defi direct
    n.emit("defier", {"pseudo_cible": "SAna", "objectif": "3", "cadence": "5"})
    time.sleep(0.5)
    did = None
    for who, ev, d in a.recu:
        if ev == "defi_recu":
            did = d.get("defi_id")
    if did:
        a.emit("repondre_defi", {"defi_id": did, "accepte": False})
        time.sleep(0.5)
    n.emit("defier", {"pseudo_cible": "Fantome", "objectif": "3", "cadence": "5"})
    time.sleep(0.3)
    n.emit("defier", {"pseudo_cible": "SNino", "objectif": "3", "cadence": "5"})
    time.sleep(0.3)
    # recherche annulee
    n.emit("chercher_partie", {"objectif": "9", "cadence": "10"})
    time.sleep(0.3)
    n.emit("annuler_recherche", {})
    time.sleep(0.3)
    # nouveau match puis deconnexion brutale d'un joueur
    n.emit("chercher_partie", {"objectif": "3", "cadence": "5"})
    time.sleep(0.2)
    a.emit("chercher_partie", {"objectif": "3", "cadence": "5"})
    time.sleep(0.6)
    a.c.disconnect()
    time.sleep(0.8)
    evs = n.recu + a.recu
    try:
        n.c.disconnect()
    except Exception:
        pass
    return evs


def normalise(evs):
    """Remplace les identifiants tires au hasard (game_id, defi_id, sid) par des
    jetons stables, dans l'ordre d'apparition."""
    table = {}
    def jeton(v):
        if v not in table:
            table[v] = "<id%d>" % (len(table) + 1)
        return table[v]
    def n(o):
        if isinstance(o, dict):
            out = {}
            for k, v in o.items():
                if k in VOLATILE_K:
                    out[k] = "<v>"
                elif k in ("game_id", "defi_id", "new_gid") and isinstance(v, str):
                    out[k] = jeton(v)
                elif k in ("sid",) :
                    out[k] = "<sid>"
                else:
                    out[k] = n(v)
            return out
        if isinstance(o, list):
            return [n(x) for x in o]
        if isinstance(o, str) and re.fullmatch(r"[0-9a-f]{12,16}", o):
            return jeton(o)
        return o
    return [(w, e, n(d)) for w, e, d in evs]


ra = normalise(scenario(PA))
rb = normalise(scenario(PB))
# on compare l'ENSEMBLE trie (l'ordre d'arrivee entre deux clients distincts
# n'est pas deterministe, le contenu si)
ka = sorted(json.dumps(x, sort_keys=True, ensure_ascii=False) for x in ra)
kb = sorted(json.dumps(x, sort_keys=True, ensure_ascii=False) for x in rb)
print("A : %d evenements  |  B : %d evenements" % (len(ka), len(kb)))
if ka == kb:
    print("IDENTIQUES")
    for x in ka:
        print("   ", x[:150])
    sys.exit(0)
import difflib
print("DIFFERENCES :")
for l in difflib.unified_diff(ka, kb, "A", "B", n=1, lineterm=""):
    print(l[:220])
sys.exit(1)
