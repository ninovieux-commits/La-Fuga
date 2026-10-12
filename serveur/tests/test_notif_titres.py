# -*- coding: utf-8 -*-
"""Le titre et le corps de CHAQUE notification, sur un vrai serveur.

Le serveur doit tourner sous `run_trace.py`, qui imprime une ligne

    [TRACE] kind | titre | corps

pour chaque notification, avant le filtre des preferences et avant Firebase.
Ce test provoque les six, puis affiche ce qui est sorti.

    python3 test_notif_titres.py <port> <chemin/vers/trace.log>
"""
import io
import json
import sys
import time
import urllib.request

PORT = sys.argv[1]
LOG = sys.argv[2]
BASE = "http://127.0.0.1:%s" % PORT


def post(path, payload):
    req = urllib.request.Request(
        BASE + path, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read())


def compte(p):
    try:
        r = post("/register", {"pseudo": p, "password": "motdepasse"})
    except Exception:
        r = {}
    if not r.get("ok"):
        r = post("/login", {"pseudo": p, "password": "motdepasse"})
    return r["token"]


def marque(n):
    return len(io.open(LOG, encoding="utf-8", errors="replace").readlines())


def traces_depuis(n):
    lignes = io.open(LOG, encoding="utf-8", errors="replace").readlines()
    # Le serveur HORODATE chaque ligne : « 2026-09-27 09:19:41 [TRACE] ... ».
    # Chercher le debut de ligne ne trouvait donc jamais rien.
    return [l[l.index("[TRACE]"):].rstrip("\n")
            for l in lignes[n:] if "[TRACE]" in l]


n = int(time.time()) % 100000
A, B = "Alice%d" % n, "Bob%d" % n
ta, tb = compte(A), compte(B)
attendus = []


def etape(titre, faire, attendu):
    d = marque(0)
    faire()
    time.sleep(0.6)
    sorties = traces_depuis(d)
    ok = any(attendu in s for s in sorties)
    attendus.append(ok)
    print("%-28s %s" % (titre, "OK" if ok else "ECHEC"))
    for s in sorties:
        print("      %s" % s)
    if not ok:
        print("      attendu un « %s »" % attendu)


# 1 ── message prive
etape("message prive", lambda: post("/send_message", {
    "token": ta, "pseudo": B, "text": "okay okay"}),
    "msg | %s | okay okay" % A)

# 2 ── defi de correspondance
etape("defi de correspondance", lambda: post("/corr_defier", {
    "token": ta, "pseudo": B, "objectif": "partie"}),
    "defi_corr | %s | vous" % A)


def dernier_defi(token):
    jeux = post("/corr_list", {"token": token})["games"]
    return [g for g in jeux if g["statut"] == "defi"][-1]


# 3 ── defi accepte : la notification ne part que si celui qui accepte
#      n'est PAS le joueur des Blancs (sinon il est deja dans l'appli). Les
#      couleurs sont tirees au hasard : on defie jusqu'a tomber sur ce cas.
gid = None
for _ in range(12):
    d = dernier_defi(tb)
    m = [g for g in post("/corr_list", {"token": tb})["games"]
         if g["id"] == d["id"]][0]
    if m.get("ma_couleur") == "Noir":
        gid = d["id"]
        break
    post("/corr_repondre", {"token": tb, "game_id": d["id"], "accepte": False})
    post("/corr_defier", {"token": ta, "pseudo": B, "objectif": "partie"})

if gid is None:
    print("defi accepte                 NON TESTE (couleur jamais tombee)")
else:
    etape("defi accepte", lambda: post("/corr_repondre", {
        "token": tb, "game_id": gid, "accepte": True}),
        "turn | %s | a accepté" % B)

# 4 ── un coup, puis 5 ── le coup qui termine la partie
if gid is not None:
    etape("coup joue (Blancs)", lambda: post("/corr_jouer", {
        "token": ta, "game_id": gid, "notation": "Do1-Do2"}),
        "turn | %s | a joué 1.Do1-Do2" % A)

    etape("coup joue (Noirs)", lambda: post("/corr_jouer", {
        "token": tb, "game_id": gid, "notation": "Do8-Do7"}),
        "turn | %s | a joué Do8-Do7" % B)

    etape("coup chat de partie", lambda: post("/corr_chat_send", {
        "token": ta, "game_id": gid, "texte": "bien joué"}),
        "msg | %s | bien joué" % A)

    etape("coup FINAL", lambda: post("/corr_jouer", {
        "token": ta, "game_id": gid, "notation": "Fa8*",
        "methode": "fugue", "gagnant": "Noir"}),
        "turn | %s | a joué 2.Fa8* — partie terminée" % A)

print("\n%d/%d" % (sum(attendus), len(attendus)))
sys.exit(0 if all(attendus) and len(attendus) == 7 else 1)
