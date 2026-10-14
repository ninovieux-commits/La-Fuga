# -*- coding: utf-8 -*-
"""Le profil dit-il s'il est dans MES favoris, et si je l'ai bloque ?

L'application lisait deja `is_favorite` et `is_blocked`. Le serveur ne les a
jamais renvoyees : la touche « Favori » ne devenait donc jamais « Retirer ».

USAGE
    python3 test_favori.py <port>

Ecrit des comptes de sonde ; serveur de test, JAMAIS la production.
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
    moi, lui = "sonde_fv_a_%d" % marque, "sonde_fv_b_%d" % marque
    mdp = "motdepasse"

    print("")
    print("── 1. Deux comptes, aucun favori ───────────────────────────────")
    ra = http("/register", {"pseudo": moi, "password": mdp})
    rb = http("/register", {"pseudo": lui, "password": mdp})
    verifie("les deux inscriptions passent", ra.get("ok") and rb.get("ok"))
    if not (ra.get("ok") and rb.get("ok")):
        return 1
    ja = ra["token"]

    p = http("/get_profile", {"token": ja, "pseudo": lui})
    verifie("le profil rend `is_favorite`", "is_favorite" in p,
            "cles : %s" % sorted(p.keys()))
    verifie("et il vaut faux", p.get("is_favorite") is False,
            "recu : %r" % p.get("is_favorite"))
    verifie("le profil rend `is_blocked`", "is_blocked" in p)
    verifie("et il vaut faux", p.get("is_blocked") is False,
            "recu : %r" % p.get("is_blocked"))

    print("")
    print("── 2. Ajoute aux favoris : le profil le dit ────────────────────")
    http("/add_favorite", {"token": ja, "pseudo": lui})
    p = http("/get_profile", {"token": ja, "pseudo": lui})
    verifie("`is_favorite` est VRAI", p.get("is_favorite") is True,
            "recu : %r" % p.get("is_favorite"))

    print("")
    print("── 3. Retire : le profil le dit aussi ──────────────────────────")
    http("/remove_favorite", {"token": ja, "pseudo": lui})
    p = http("/get_profile", {"token": ja, "pseudo": lui})
    verifie("`is_favorite` est redevenu faux", p.get("is_favorite") is False,
            "recu : %r" % p.get("is_favorite"))

    print("")
    print("── 4. La relation est a SENS UNIQUE ────────────────────────────")
    # Lui me met en favori ; cela ne doit rien changer a ce que JE vois.
    http("/add_favorite", {"token": rb["token"], "pseudo": moi})
    p = http("/get_profile", {"token": ja, "pseudo": lui})
    verifie("ses favoris a lui ne sont pas les miens",
            p.get("is_favorite") is False, "recu : %r" % p.get("is_favorite"))
    q = http("/get_profile", {"token": rb["token"], "pseudo": moi})
    verifie("et de son cote a lui, c'est vrai",
            q.get("is_favorite") is True, "recu : %r" % q.get("is_favorite"))

    print("")
    print("── 5. Le blocage, pareil : celui que J'AI pose ─────────────────")
    http("/block_user", {"token": ja, "pseudo": lui})
    p = http("/get_profile", {"token": ja, "pseudo": lui})
    verifie("`is_blocked` est vrai de mon cote",
            p.get("is_blocked") is True, "recu : %r" % p.get("is_blocked"))
    q = http("/get_profile", {"token": rb["token"], "pseudo": moi})
    verifie("et faux du sien : il n'a rien bloque",
            q.get("is_blocked") is False, "recu : %r" % q.get("is_blocked"))

    print("")
    print("── 6. MON profil n'a ni l'une ni l'autre ───────────────────────")
    p = http("/get_profile", {"token": ja})
    verifie("c'est bien le mien", p.get("is_self") is True)
    verifie("pas de `is_favorite` sur soi-meme", "is_favorite" not in p,
            "cles : %s" % sorted(p.keys()))
    verifie("pas de `is_blocked` non plus", "is_blocked" not in p)

    print("")
    print("── 7. Rien d'autre n'a bouge ───────────────────────────────────")
    p = http("/get_profile", {"token": ja, "pseudo": lui})
    for cle in ("pseudo", "melo", "melo_random", "photo", "description",
                "online", "followers", "following", "theme"):
        verifie("la cle `%s` est toujours la" % cle, cle in p)

    print("")
    print("%d/%d" % (sum(1 for x in resultats if x), len(resultats)))
    return 0 if all(resultats) else 1


if __name__ == "__main__":
    sys.exit(main())
