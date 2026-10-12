# -*- coding: utf-8 -*-
"""Mesure le cout reel des deux routes que l'appli sonde en boucle :
corr_list (toutes les 3 s) et list_conversations. Compte aussi le nombre
d'ouvertures de la base par appel (via /proc, en echantillonnant les fd)."""
import json, os, statistics, sys, threading, time, urllib.request

PORT = sys.argv[1]; PID = int(sys.argv[2]); NGAMES = int(sys.argv[3])
BASE = "http://127.0.0.1:%s" % PORT

def post(path, payload):
    req = urllib.request.Request(BASE + path, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.perf_counter()
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read()), time.perf_counter() - t0

def compte(p, pseudo):
    r, _ = post(p, {"pseudo": pseudo, "password": "motdepasse"})
    return r.get("token")

tok_a = compte("/register", "BNino") or compte("/login", "BNino")
tok_b = compte("/register", "BAna") or compte("/login", "BAna")
if not tok_a: tok_a = compte("/login", "BNino")
if not tok_b: tok_b = compte("/login", "BAna")

# NGAMES parties de correspondance acceptees, avec du chat et des messages
gids = []
for i in range(NGAMES):
    r, _ = post("/corr_defier", {"token": tok_a, "pseudo": "BAna",
                                 "objectif": "3", "random": False})
    if r.get("game_id"): gids.append(r["game_id"])
r, _ = post("/corr_list", {"token": tok_b})
for g in r.get("games", []):
    if g.get("statut") == "defi" and not g.get("is_defieur"):
        post("/corr_repondre", {"token": tok_b, "game_id": g["id"], "accepte": True})
for g in gids:
    for k in range(5):
        post("/corr_chat_send", {"token": tok_a, "game_id": g, "texte": "msg %d" % k})
for k in range(30):
    post("/send_message", {"token": tok_a, "pseudo": "BAna", "text": "m%d" % k})

# ── nombre d'ouvertures de la base pendant UN appel ────────────────────────
maxfd = [0]
stop = [False]
def echantillonne():
    while not stop[0]:
        try:
            n = sum(1 for f in os.listdir("/proc/%d/fd" % PID)
                    if "lafuga.db" in (os.readlink("/proc/%d/fd/%s" % (PID, f))
                                       if os.path.exists("/proc/%d/fd/%s" % (PID, f))
                                       else ""))
            maxfd[0] = max(maxfd[0], n)
        except Exception:
            pass
th = threading.Thread(target=echantillonne, daemon=True); th.start()
lat = []
for i in range(120):
    _, d = post("/corr_list", {"token": tok_a}); lat.append(d)
stop[0] = True; th.join(timeout=1)
lat2 = []
for i in range(60):
    _, d = post("/list_conversations", {"token": tok_a}); lat2.append(d)

def stats(l):
    s = sorted(l)
    return (statistics.mean(s) * 1000, s[len(s)//2] * 1000, s[int(len(s)*0.95)] * 1000)

print("parties de correspondance : %d" % len(gids))
print("corr_list          : moy %.2f ms  med %.2f ms  p95 %.2f ms" % stats(lat))
print("list_conversations : moy %.2f ms  med %.2f ms  p95 %.2f ms" % stats(lat2))
print("connexions SQLite ouvertes simultanement (max observe) : %d" % maxfd[0])
