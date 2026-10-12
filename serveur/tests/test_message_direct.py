# -*- coding: utf-8 -*-
"""Un message envoye par HTTP arrive-t-il en TEMPS REEL au destinataire ?

C'est le maillon que la suite Flutter ne teste pas : ses tests injectent le
message directement dans la boite aux lettres du client. Ici on part d'un vrai
POST /send_message et on regarde si l'evenement `message_recu` sort du serveur.
"""
import json, sys, time, urllib.request
import socketio

PORT = sys.argv[1]
BASE = "http://127.0.0.1:%s" % PORT

def post(path, payload):
    req = urllib.request.Request(BASE + path, data=json.dumps(payload).encode(),
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

ta = compte("MsgA")
tb = compte("MsgB")

recus = []
cb = socketio.Client(reconnection=False)
cb.on("message_recu", lambda d: recus.append(d))
auth_ok = []
cb.on("auth_ok", lambda d=None: auth_ok.append(1))
cb.connect(BASE, transports=["websocket"], wait_timeout=10)
cb.emit("auth", {"token": tb})
time.sleep(1.0)
print("auth_ok recu par B    : %s" % bool(auth_ok))

# A ecrit a B, par HTTP, exactement comme l'application.
post("/send_message", {"token": ta, "pseudo": "MsgB", "text": "coucou direct"})
time.sleep(1.5)
print("message_recu par B    : %d  %s" % (len(recus), recus))

# Et B relit la conversation par HTTP : le message doit y etre de toute facon.
conv = post("/list_conversation", {"token": tb, "pseudo": "MsgA"})
print("dans /list_conversation: %d message(s)" % len(conv.get("messages", [])))

# Deuxieme envoi, pour verifier que ce n'est pas un coup de chance.
post("/send_message", {"token": ta, "pseudo": "MsgB", "text": "et un deuxieme"})
time.sleep(1.5)
print("apres 2e envoi        : %d evenement(s)" % len(recus))

cb.disconnect()
print("VERDICT: %s" % ("le serveur emet bien en direct" if len(recus) == 2
                       else "le serveur N'EMET PAS (ou pas a chaque fois)"))
