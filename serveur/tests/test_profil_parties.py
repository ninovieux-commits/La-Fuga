# -*- coding: utf-8 -*-
"""Les parties de correspondance EN COURS d'un joueur, vues par un visiteur.

Nino : « le "parties" vers le milieu affiche les parties par correspondance en
cours de la personne. »

`/corr_list` ne rend que les miennes. `/corr_list_public` repond pour un
pseudo, en lecture seule, du point de vue du joueur REGARDE — et ne laisse
sortir que ce qu'on verrait en regardant par-dessus son epaule.

USAGE
    python3 test_profil_parties.py <port>

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

# Ce qui ne doit JAMAIS sortir : de quoi aider a jouer contre quelqu'un, ou
# lire par-dessus son epaule ce qui ne se voit pas sur un plateau.
PRIVE = ("premove", "premove_adverse", "premove_par", "chat_non_lus",
         "nulle_a_repondre", "nulle_proposeur", "nulle_proposee_par_moi",
         "is_defieur")


def http(path, payload):
    req = urllib.request.Request(
        BASE + path, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        try:
            d = json.loads(e.read())
        except Exception:
            d = {"ok": False}
        d["_code"] = e.code
        return d


def verifie(titre, condition, detail=""):
    resultats.append(bool(condition))
    print("%-64s %s" % (titre, "OK" if condition else "ECHEC"))
    if detail:
        print("      %s" % detail)


def partie_de(jeton):
    """La liste des parties de correspondance d'un joueur, par corr_list."""
    return http("/corr_list", {"token": jeton}).get("games", [])


def main():
    marque = int(time.time()) % 100000
    visiteur = "sonde_pp_v_%d" % marque
    lui = "sonde_pp_l_%d" % marque
    contre = "sonde_pp_c_%d" % marque
    mdp = "motdepasse"

    print("")
    print("── 1. Trois comptes, aucune partie ─────────────────────────────")
    jv = http("/register", {"pseudo": visiteur, "password": mdp})
    jl = http("/register", {"pseudo": lui, "password": mdp})
    jc = http("/register", {"pseudo": contre, "password": mdp})
    verifie("les trois inscriptions passent",
            jv.get("ok") and jl.get("ok") and jc.get("ok"))
    if not (jv.get("ok") and jl.get("ok") and jc.get("ok")):
        return 1
    tv, tl, tc = jv["token"], jl["token"], jc["token"]

    r = http("/corr_list_public", {"token": tv, "pseudo": lui})
    verifie("la route repond", r.get("ok") is True, "recu : %r" % r)
    verifie("et il n'a aucune partie", r.get("games") == [],
            "recu : %r" % r.get("games"))

    print("")
    print("── 2. Un defi NON accepte ne se montre pas ─────────────────────")
    d = http("/corr_defier", {"token": tl, "pseudo": contre,
                              "objectif": "partie", "mode": "standard"})
    verifie("le defi part", d.get("ok") is True, "recu : %r" % d)
    r = http("/corr_list_public", {"token": tv, "pseudo": lui})
    verifie("un defi en attente n'est PAS une partie en cours",
            r.get("games") == [], "recu : %r" % r.get("games"))

    print("")
    print("── 3. Accepte : la partie paraît ───────────────────────────────")
    defis = [g for g in partie_de(tc) if g["statut"] == "defi"]
    verifie("le defie voit le defi", len(defis) == 1)
    if not defis:
        return 1
    gid = defis[0]["id"]
    a = http("/corr_repondre", {"token": tc, "game_id": gid, "accepte": True})
    verifie("il accepte", a.get("ok") is True, "recu : %r" % a)

    r = http("/corr_list_public", {"token": tv, "pseudo": lui})
    jeux = r.get("games", [])
    verifie("le visiteur voit UNE partie", len(jeux) == 1,
            "recu : %d" % len(jeux))
    if not jeux:
        return 1
    g = jeux[0]

    print("")
    print("── 4. Elle est vue du point de vue du JOUEUR REGARDE ───────────")
    verifie("son adversaire est l'autre joueur", g.get("adversaire") == contre,
            "recu : %r" % g.get("adversaire"))
    verifie("sa couleur est la sienne, pas la mienne",
            g.get("ma_couleur") in ("Blanc", "Noir"),
            "recu : %r" % g.get("ma_couleur"))
    verifie("la partie est en cours", g.get("statut") == "en_cours")
    verifie("les coups sont la (l'apercu dessine la position)",
            "moves_text" in g)
    verifie("le trait est dit", g.get("turn") in ("Blanc", "Noir"))
    verifie("le score entre eux aussi",
            "mon_score" in g and "score_adverse" in g)

    # Le meme jeu, vu par son proprietaire : c'est bien la meme partie.
    sien = [x for x in partie_de(tl) if x["id"] == g["id"]]
    verifie("c'est la meme partie que la sienne", len(sien) == 1)
    if sien:
        verifie("meme couleur que ce qu'il voit, lui",
                sien[0]["ma_couleur"] == g["ma_couleur"],
                "lui : %r / visiteur : %r"
                % (sien[0]["ma_couleur"], g["ma_couleur"]))
        verifie("meme adversaire", sien[0]["adversaire"] == g["adversaire"])

    print("")
    print("── 5. Ce qui ne regarde pas un visiteur n'y est PAS ────────────")
    for cle in PRIVE:
        verifie("pas de `%s`" % cle, cle not in g,
                "cles recues : %s" % sorted(g.keys()))

    print("")
    print("── 6. Un blocage ferme la porte ────────────────────────────────")
    http("/block_user", {"token": tl, "pseudo": visiteur})
    r = http("/corr_list_public", {"token": tv, "pseudo": lui})
    verifie("bloque par lui : la liste est vide", r.get("games") == [],
            "recu : %r" % r.get("games"))
    http("/unblock_user", {"token": tl, "pseudo": visiteur})
    r = http("/corr_list_public", {"token": tv, "pseudo": lui})
    verifie("debloque : elle revient", len(r.get("games", [])) == 1)

    http("/block_user", {"token": tv, "pseudo": lui})
    r = http("/corr_list_public", {"token": tv, "pseudo": lui})
    verifie("et dans l'autre sens aussi", r.get("games") == [],
            "recu : %r" % r.get("games"))
    http("/unblock_user", {"token": tv, "pseudo": lui})

    print("")
    print("── 7. Sur son propre profil, elle repond aussi ─────────────────")
    r = http("/corr_list_public", {"token": tl, "pseudo": lui})
    verifie("il voit sa propre partie", len(r.get("games", [])) == 1,
            "recu : %r" % r.get("games"))

    print("")
    print("── 8. Les refus ────────────────────────────────────────────────")
    r = http("/corr_list_public", {"token": "jeton_bidon", "pseudo": lui})
    verifie("jeton invalide : refuse", r.get("ok") is False
            and r.get("_code") == 401, "recu : %r" % r)
    r = http("/corr_list_public", {"token": tv, "pseudo": "personne_ici_xyz"})
    verifie("joueur introuvable : 404", r.get("_code") == 404,
            "recu : %r" % r)
    r = http("/corr_list_public", {"token": tv, "pseudo": ""})
    verifie("pseudo vide : liste vide, pas d'erreur",
            r.get("ok") is True and r.get("games") == [], "recu : %r" % r)

    print("")
    print("── 9. Une partie finie n'est plus « en cours » ─────────────────")
    http("/corr_abandon", {"token": tc, "game_id": gid})
    r = http("/corr_list_public", {"token": tv, "pseudo": lui})
    verifie("abandonnee : elle disparait du profil", r.get("games") == [],
            "recu : %r" % r.get("games"))
    verifie("mais elle reste dans SA liste a lui",
            any(x["id"] == gid for x in partie_de(tl)))

    print("")
    print("── 10. /corr_list n'a pas bouge ────────────────────────────────")
    sien = partie_de(tl)
    verifie("il voit toujours ses parties", len(sien) >= 1)
    if sien:
        for cle in ("chat_non_lus", "nulle_a_repondre", "is_defieur"):
            verifie("sa liste a lui garde `%s`" % cle, cle in sien[0],
                    "cles : %s" % sorted(sien[0].keys()))

    print("")
    print("%d/%d" % (sum(1 for x in resultats if x), len(resultats)))
    return 0 if all(resultats) else 1


if __name__ == "__main__":
    sys.exit(main())
