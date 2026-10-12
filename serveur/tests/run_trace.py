"""Lance server.py en TRACANT chaque notification, sans rien envoyer.

Enveloppe `_notify_user` : la trace est prise AVANT le filtre des preferences
et avant Firebase, donc elle montre exactement le titre et le corps que le
code produit, sans compte configure ni jeton FCM.

    [TRACE] kind | titre | corps

Usage :  PORT=5150 python3 run_trace.py
"""
import random
import runpy
import sys

random.seed(424242)

src = open("server.py", encoding="utf-8").read()

ancien = "def _notify_user(user_id, kind, title, body, data=None):"
assert src.count(ancien) == 1, "definition de _notify_user introuvable"
src = src.replace(
    ancien, "def _notify_user_reel(user_id, kind, title, body, data=None):", 1)

sonde = '''def _notify_user(user_id, kind, title, body, data=None):
    print("[TRACE] %s | %s | %s" % (kind, title, body), flush=True)
    return _notify_user_reel(user_id, kind, title, body, data)


'''
suivant = "def _notify_user_sync(user_id, kind, title, body, data=None):"
assert src.count(suivant) == 1, "_notify_user_sync introuvable"
src = src.replace(suivant, sonde + suivant, 1)

with open("server_trace_genere.py", "w", encoding="utf-8") as f:
    f.write(src)

sys.argv = ["server.py"]
runpy.run_path("server_trace_genere.py", run_name="__main__")
