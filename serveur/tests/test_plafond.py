# -*- coding: utf-8 -*-
"""Une boite de discussion garde-t-elle ses 200 derniers messages ?

Nino : « une fois qu'une boite contient 200 messages, les plus anciens doivent
etre effaces ».

USAGE
    python3 test_plafond.py <port>

Le serveur doit tourner en local (voir tests/README.md). Ecrit DEUX comptes de
sonde et quelques centaines de messages dans SA base ; a lancer sur un serveur
de test, JAMAIS sur la production.
"""
import json
import sys
import time
import urllib.error
import urllib.request

PORT = sys.argv[1] if len(sys.argv) > 1 else "5300"
BASE = "http://127.0.0.1:%s" % PORT
PLAFOND = 200
resultats = []


def http(path, payload):
    req = urllib.request.Request(
        BASE + path, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        try:
            return json.loads(e.read())
        except Exception:
            return {"ok": False, "error": "HTTP %s" % e.code}


def verifie(titre, condition, detail=""):
    resultats.append(bool(condition))
    print("%-64s %s" % (titre, "OK" if condition else "ECHEC"))
    if detail:
        print("      %s" % detail)


def textes(jeton, autre):
    """Les textes de la boite, du plus ancien au plus recent."""
    r = http("/list_conversation", {"token": jeton, "pseudo": autre})
    return [m["texte"] for m in r.get("messages", [])]


def main():
    marque = int(time.time()) % 100000
    a, b = "sonde_pl_a_%d" % marque, "sonde_pl_b_%d" % marque
    mdp = "motdepasse"

    print("")
    print("── 1. Deux comptes ─────────────────────────────────────────────")
    ra = http("/register", {"pseudo": a, "password": mdp})
    rb = http("/register", {"pseudo": b, "password": mdp})
    verifie("les deux inscriptions passent", ra.get("ok") and rb.get("ok"),
            "%s / %s" % (str(ra)[:50], str(rb)[:50]))
    if not (ra.get("ok") and rb.get("ok")):
        return 1
    ja, jb = ra["token"], rb["token"]

    print("")
    print("── 2. Sous le plafond, rien ne disparait ───────────────────────")
    for i in range(50):
        http("/send_message", {"token": ja, "pseudo": b, "text": "a%d" % i})
    vus = textes(ja, b)
    verifie("cinquante messages, cinquante messages", len(vus) == 50,
            "recu : %d" % len(vus))
    verifie("le tout premier est encore la", vus and vus[0] == "a0",
            "premier : %r" % (vus[0] if vus else None))

    print("")
    print("── 3. Au plafond pile, rien ne disparait non plus ──────────────")
    for i in range(50, PLAFOND):
        http("/send_message", {"token": ja, "pseudo": b, "text": "a%d" % i})
    vus = textes(ja, b)
    verifie("deux cents messages tiennent", len(vus) == PLAFOND,
            "recu : %d" % len(vus))
    verifie("le premier est TOUJOURS la", vus and vus[0] == "a0",
            "premier : %r" % (vus[0] if vus else None))

    print("")
    print("── 4. Le deux cent unieme chasse le premier ────────────────────")
    http("/send_message", {"token": ja, "pseudo": b, "text": "de trop"})
    vus = textes(ja, b)
    verifie("la boite reste a deux cents", len(vus) == PLAFOND,
            "recu : %d" % len(vus))
    verifie("le plus ancien est parti", "a0" not in vus)
    verifie("le suivant est devenu le plus ancien", vus and vus[0] == "a1",
            "premier : %r" % (vus[0] if vus else None))
    verifie("et le dernier envoye est bien la", vus and vus[-1] == "de trop",
            "dernier : %r" % (vus[-1] if vus else None))

    print("")
    print("── 5. La BOITE compte, pas l'expediteur ────────────────────────")
    # Les deux sens partagent le meme plafond : c'est une boite, pas deux.
    for i in range(30):
        http("/send_message", {"token": jb, "pseudo": a, "text": "b%d" % i})
    vus = textes(ja, b)
    verifie("toujours deux cents en tout", len(vus) == PLAFOND,
            "recu : %d" % len(vus))
    verifie("les trente derniers sont les siens",
            vus[-30:] == ["b%d" % i for i in range(30)],
            "fin : %r" % vus[-3:])
    verifie("trente de PLUS ont donc disparu du debut", "a30" not in vus,
            "premier : %r" % (vus[0] if vus else None))
    verifie("l'autre voit la MEME boite", textes(jb, a) == vus)

    print("")
    print("── 6. Les non-lus suivent ──────────────────────────────────────")
    # Un message efface n'est plus a lire.
    r = http("/list_conversations", {"token": ja})
    conv = [c for c in r.get("conversations", []) if c.get("pseudo") == b]
    verifie("la conversation est listee", len(conv) == 1, str(r)[:90])
    if conv:
        verifie("ses non-lus ne depassent pas le plafond",
                conv[0].get("unread", 0) <= PLAFOND,
                "non-lus : %r" % conv[0].get("unread"))

    print("")
    print("── 7. Une autre boite n'est pas touchee ────────────────────────")
    c = "sonde_pl_c_%d" % marque
    rc = http("/register", {"pseudo": c, "password": mdp})
    if rc.get("ok"):
        http("/send_message", {"token": ja, "pseudo": c, "text": "coucou"})
        verifie("la boite avec un tiers garde son message",
                textes(ja, c) == ["coucou"], "recu : %r" % textes(ja, c))
        verifie("et celle d'avant n'a pas bouge", len(textes(ja, b)) == PLAFOND)

    print("")
    print("%d/%d" % (sum(1 for x in resultats if x), len(resultats)))
    return 0 if all(resultats) else 1


if __name__ == "__main__":
    sys.exit(main())
