# -*- coding: utf-8 -*-
"""L'instrument suit-il le COMPTE, et non le telephone ?

Deux choses a verifier, et la seconde est celle qu'on oublie :

1. Un compte qui a choisi rend son choix a chaque connexion, depuis n'importe
   quel appareil.
2. Un compte qui n'a JAMAIS choisi rend une chaine VIDE — et non 'piano'. C'est
   ce vide qui dit a l'application d'y poser l'instrument de l'appareil au lieu
   d'en adopter un. Les confondre remettrait le piano a quelqu'un qui venait de
   choisir la harpe.

USAGE
    python3 test_instrument.py <port>

Le serveur doit tourner en local (voir tests/README.md). Ecrit deux comptes de
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
        # Une route absente rend une page HTML : on la lit comme un echec, pour
        # que ce fichier sache aussi s'executer contre un serveur NON patche.
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
    # Un pseudo neuf a chaque passage : on veut un compte qui n'a JAMAIS choisi,
    # et un compte deja cree en aurait gardé un du passage precedent.
    pseudo = "sonde_inst_%d" % (int(time.time()) % 100000)
    mdp = "motdepasse"

    print("")
    print("── 1. Un compte tout juste cree n'a RIEN choisi ────────────────")
    r = http("/register", {"pseudo": pseudo, "password": mdp})
    verifie("l'inscription passe", r.get("ok"), str(r)[:120])
    if not r.get("ok"):
        print("Sans compte, le reste n'a pas de sens.")
        return 1
    token = r["token"]
    verifie("elle rend `instrument`", "instrument" in r,
            "cles : %s" % sorted(r.keys()))
    verifie("et il est VIDE, pas 'piano'", r.get("instrument") == "",
            "recu : %r" % r.get("instrument"))

    print("")
    print("── 2. Le choix s'enregistre et revient ─────────────────────────")
    r = http("/set_instrument", {"token": token, "instrument": "harpe"})
    verifie("la route repond", r.get("ok"), str(r)[:120])
    verifie("elle rend l'instrument pose", r.get("instrument") == "harpe",
            "recu : %r" % r.get("instrument"))
    r = http("/login", {"pseudo": pseudo, "password": mdp})
    verifie("une NOUVELLE connexion le retrouve",
            r.get("instrument") == "harpe", "recu : %r" % r.get("instrument"))
    token2 = r["token"]
    r = http("/ping", {"token": token2})
    verifie("le ping le rend aussi", r.get("instrument") == "harpe",
            "recu : %r" % r.get("instrument"))

    print("")
    print("── 3. On peut changer d'avis, et effacer ───────────────────────")
    http("/set_instrument", {"token": token2, "instrument": "xylophone"})
    r = http("/login", {"pseudo": pseudo, "password": mdp})
    verifie("le dernier choix gagne", r.get("instrument") == "xylophone",
            "recu : %r" % r.get("instrument"))
    http("/set_instrument", {"token": token2, "instrument": ""})
    r = http("/login", {"pseudo": pseudo, "password": mdp})
    verifie("un envoi vide efface le choix", r.get("instrument") == "",
            "recu : %r" % r.get("instrument"))

    print("")
    print("── 4. Le serveur nettoie sans tenir de liste ───────────────────")
    # Il ne connait pas les instruments qui existent — sinon, ajouter une flute
    # a l'application demanderait de le redeployer. Il se contente de nettoyer.
    r = http("/set_instrument", {"token": token2, "instrument": "  HaRpE  "})
    verifie("espaces et majuscules sont nettoyes",
            r.get("instrument") == "harpe", "recu : %r" % r.get("instrument"))
    r = http("/set_instrument",
             {"token": token2, "instrument": "harpe'; DROP TABLE users;--"})
    # La propriete, et non une chaine exacte : le serveur coupe a vingt
    # caracteres PUIS ne garde que les lettres, et l'ordre des deux est son
    # affaire. Ce qui compte, c'est qu'il ne reste que des lettres minuscules.
    rendu = r.get("instrument") or ""
    verifie("il ne reste que des lettres minuscules",
            rendu != "" and all("a" <= ch <= "z" for ch in rendu),
            "recu : %r" % rendu)
    verifie("ni guillemet, ni point-virgule, ni espace",
            not any(ch in rendu for ch in "\"';- "),
            "recu : %r" % rendu)
    verifie("et la table users est toujours la",
            http("/login", {"pseudo": pseudo, "password": mdp}).get("ok"))
    r = http("/set_instrument", {"token": token2, "instrument": "a" * 40})
    verifie("un nom trop long est coupe a vingt",
            len(r.get("instrument") or "") == 20,
            "longueur : %d" % len(r.get("instrument") or ""))
    # Un instrument que le serveur ne connait pas est accepte : c'est voulu.
    r = http("/set_instrument", {"token": token2, "instrument": "flute"})
    verifie("un instrument inconnu du serveur est accepte",
            r.get("instrument") == "flute", "recu : %r" % r.get("instrument"))

    print("")
    print("── 5. Sans jeton, rien ─────────────────────────────────────────")
    r = http("/set_instrument", {"token": "faux", "instrument": "orgue"})
    verifie("un jeton invalide est refuse", not r.get("ok"), str(r)[:80])
    r = http("/login", {"pseudo": pseudo, "password": mdp})
    verifie("et le choix du compte n'a pas bouge",
            r.get("instrument") == "flute", "recu : %r" % r.get("instrument"))

    print("")
    print("%d/%d" % (sum(1 for x in resultats if x), len(resultats)))
    return 0 if all(resultats) else 1


if __name__ == "__main__":
    sys.exit(main())
