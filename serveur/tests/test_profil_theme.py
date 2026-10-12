# -*- coding: utf-8 -*-
"""Le profil d'un joueur dit-il son THEME ?

La boite de messages s'habille du decor de l'interlocuteur. Le serveur garde
deja ce theme — `/set_theme` l'enregistre — mais `/get_profile` ne le rendait
pas, donc l'application ne pouvait connaitre que le sien.

USAGE
    python3 test_profil_theme.py <port>

Le serveur doit tourner en local (voir tests/README.md). Ecrit DEUX comptes de
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
    marque = int(time.time()) % 100000
    lui = "sonde_th_a_%d" % marque
    moi = "sonde_th_b_%d" % marque
    mdp = "motdepasse"

    print("")
    print("── 1. Deux comptes, et LUI choisit un theme ────────────────────")
    a = http("/register", {"pseudo": lui, "password": mdp})
    b = http("/register", {"pseudo": moi, "password": mdp})
    verifie("les deux inscriptions passent", a.get("ok") and b.get("ok"),
            "%s / %s" % (str(a)[:60], str(b)[:60]))
    if not (a.get("ok") and b.get("ok")):
        return 1
    jeton_lui, jeton_moi = a["token"], b["token"]

    r = http("/set_theme", {"token": jeton_lui, "theme": "insectes"})
    verifie("il enregistre son theme", r.get("theme") == "insectes",
            "recu : %r" % r.get("theme"))

    print("")
    print("── 2. SON profil, vu par MOI, dit son theme ────────────────────")
    r = http("/get_profile", {"token": jeton_moi, "pseudo": lui})
    verifie("le profil repond", r.get("ok"), str(r)[:110])
    verifie("il n'est pas le mien", r.get("is_self") is False,
            "is_self : %r" % r.get("is_self"))
    verifie("il rend `theme`", "theme" in r,
            "cles : %s" % sorted(r.keys()))
    verifie("et c'est bien LE SIEN", r.get("theme") == "insectes",
            "recu : %r" % r.get("theme"))

    print("")
    print("── 3. Un theme composite passe entier ──────────────────────────")
    compose = "fleurs|dragon|original|insectes|bataille"
    http("/set_theme", {"token": jeton_lui, "theme": compose})
    r = http("/get_profile", {"token": jeton_moi, "pseudo": lui})
    verifie("les cinq axes reviennent sans etre tronques",
            r.get("theme") == compose, "recu : %r" % r.get("theme"))

    print("")
    print("── 4. Un compte qui n'a rien choisi rend `original` ────────────")
    r = http("/get_profile", {"token": jeton_lui, "pseudo": moi})
    verifie("et non une chaine vide ni null", r.get("theme") == "original",
            "recu : %r" % r.get("theme"))

    print("")
    print("── 5. Mon propre profil le dit aussi ───────────────────────────")
    r = http("/get_profile", {"token": jeton_lui})
    verifie("sans pseudo, c'est le mien", r.get("is_self") is True,
            "is_self : %r" % r.get("is_self"))
    verifie("et il porte mon theme", r.get("theme") == compose,
            "recu : %r" % r.get("theme"))

    print("")
    print("── 6. Rien d'autre n'a bouge ───────────────────────────────────")
    r = http("/get_profile", {"token": jeton_moi, "pseudo": lui})
    for cle in ("pseudo", "melo", "melo_random", "photo", "description",
                "online", "followers", "following"):
        verifie("la cle `%s` est toujours la" % cle, cle in r,
                "" if cle in r else "cles : %s" % sorted(r.keys()))
    verifie("un joueur inconnu reste introuvable",
            not http("/get_profile",
                     {"token": jeton_moi, "pseudo": "personne_%d" % marque}
                     ).get("ok"))
    verifie("sans jeton, rien",
            not http("/get_profile", {"token": "faux"}).get("ok"))

    print("")
    print("%d/%d" % (sum(1 for x in resultats if x), len(resultats)))
    return 0 if all(resultats) else 1


if __name__ == "__main__":
    sys.exit(main())
