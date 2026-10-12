# -*- coding: utf-8 -*-
"""La vitesse de glissee suit-elle le COMPTE ?

Meme histoire que l'instrument, avec un piege de plus : ZERO EST UN CHOIX.
C'est la glissee instantanee, que des joueurs veulent. Le marqueur « ce compte
n'a jamais rien dit » ne peut donc pas etre zero — sinon leur choix serait
remplace par celui de l'appareil a chaque connexion. C'est -1.

USAGE
    python3 test_glissee.py <port>

Le serveur doit tourner en local (voir tests/README.md). Ecrit un compte de
sonde dans SA base ; a lancer sur un serveur de test, JAMAIS sur la production.
"""
import json
import sys
import time
import urllib.error
import urllib.request

PORT = sys.argv[1] if len(sys.argv) > 1 else "5300"
BASE = "http://127.0.0.1:%s" % PORT
resultats = []


def http(path, payload):
    req = urllib.request.Request(
        BASE + path, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
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


def main():
    pseudo = "sonde_gli_%d" % (int(time.time()) % 100000)
    mdp = "motdepasse"

    print("")
    print("── 1. Un compte neuf n'a rien dit ──────────────────────────────")
    r = http("/register", {"pseudo": pseudo, "password": mdp})
    verifie("l'inscription passe", r.get("ok"), str(r)[:110])
    if not r.get("ok"):
        return 1
    token = r["token"]
    verifie("elle rend `glissee`", "glissee" in r,
            "cles : %s" % sorted(r.keys()))
    verifie("et elle vaut -1, PAS zero", r.get("glissee") == -1,
            "recu : %r" % r.get("glissee"))

    print("")
    print("── 2. Le choix s'enregistre et revient ─────────────────────────")
    r = http("/set_glissee", {"token": token, "glissee": 0.42})
    verifie("la route repond", r.get("ok"), str(r)[:110])
    verifie("elle rend la valeur posee", abs(r.get("glissee", -9) - 0.42) < 1e-9,
            "recu : %r" % r.get("glissee"))
    r = http("/login", {"pseudo": pseudo, "password": mdp})
    verifie("une NOUVELLE connexion la retrouve",
            abs(r.get("glissee", -9) - 0.42) < 1e-9,
            "recu : %r" % r.get("glissee"))
    token2 = r["token"]
    r = http("/ping", {"token": token2})
    verifie("le ping la rend aussi", abs(r.get("glissee", -9) - 0.42) < 1e-9,
            "recu : %r" % r.get("glissee"))

    print("")
    print("── 3. ZERO est un choix, pas une absence ───────────────────────")
    # Le piege. `user.get("glissee") or -1` rendrait -1 pour un zero, et
    # l'application remplacerait la glissee instantanee par celle de
    # l'appareil a chaque connexion.
    http("/set_glissee", {"token": token2, "glissee": 0})
    r = http("/login", {"pseudo": pseudo, "password": mdp})
    verifie("zero revient comme zero, et non comme -1",
            r.get("glissee") == 0, "recu : %r" % r.get("glissee"))
    r = http("/ping", {"token": token2})
    verifie("le ping aussi", r.get("glissee") == 0,
            "recu : %r" % r.get("glissee"))

    print("")
    print("── 4. Le serveur borne et refuse ce qui n'est pas un nombre ────")
    r = http("/set_glissee", {"token": token2, "glissee": -5})
    verifie("une valeur negative est ramenee a zero", r.get("glissee") == 0,
            "recu : %r" % r.get("glissee"))
    r = http("/set_glissee", {"token": token2, "glissee": 9999})
    verifie("une valeur enorme est coupee a dix", r.get("glissee") == 10,
            "recu : %r" % r.get("glissee"))
    r = http("/set_glissee", {"token": token2, "glissee": "vite"})
    verifie("un texte est refuse", not r.get("ok"), str(r)[:80])
    r = http("/set_glissee", {"token": token2})
    verifie("une valeur absente est refusee", not r.get("ok"), str(r)[:80])
    r = http("/login", {"pseudo": pseudo, "password": mdp})
    verifie("et apres ces refus, le compte garde sa derniere valeur",
            r.get("glissee") == 10, "recu : %r" % r.get("glissee"))

    print("")
    print("── 5. Sans jeton, rien ─────────────────────────────────────────")
    r = http("/set_glissee", {"token": "faux", "glissee": 0.3})
    verifie("un jeton invalide est refuse", not r.get("ok"), str(r)[:80])
    r = http("/login", {"pseudo": pseudo, "password": mdp})
    verifie("le compte n'a pas bouge", r.get("glissee") == 10,
            "recu : %r" % r.get("glissee"))

    print("")
    print("%d/%d" % (sum(1 for x in resultats if x), len(resultats)))
    return 0 if all(resultats) else 1


if __name__ == "__main__":
    sys.exit(main())
