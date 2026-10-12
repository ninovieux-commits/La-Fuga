# -*- coding: utf-8 -*-
"""Une partie de correspondance peut-elle partir d'une position composee ?

Trois choses se verifient ici, et la troisieme est la moins evidente :

1. LA POSITION VOYAGE ET SURVIT. Le serveur l'accepte, la rend aux deux
   joueurs, en tire le trait, et l'ecrit dans l'archive .nmc a la fin de la
   partie — sans quoi la partie se rejouerait depuis la position standard,
   c'est-a-dire n'importe quoi.

2. LE SERVEUR REFUSE CE QU'IL NE SAIT PAS JOUER. Une position mal formee, un
   camp sans Heritier, des carrees qui ne peuvent pas bouger : trois refus, et
   AUCUNE partie creee. C'est le serveur qui garde la partie ; s'il accepte une
   position injouable, elle s'y installe pour de bon.

3. LA COULEUR ALEATOIRE SE TIRE A L'ACCEPTATION. « Aucun des deux joueurs ne
   doit savoir qui va avoir les blancs tant que la partie n'a pas demarre. »
   Cela ne se prouve pas sur une partie : il faut en lancer assez pour voir la
   couleur CHANGER entre le defi et le depart. Si le tirage avait lieu a la
   creation, elle ne changerait jamais.
   Et l'inverse se verifie aussi : un defi venu d'une ANCIENNE application ne
   doit jamais voir sa couleur changer — le client Kivy oriente son apercu
   selon elle.

USAGE
    python3 test_position.py <port>

Le serveur doit tourner en local (voir tests/README.md). Ecrit deux comptes de
sonde et une cinquantaine de parties dans SA base ; a lancer sur un serveur de
test, JAMAIS sur la production.
"""
import json
import sys
import urllib.error
import urllib.request

PORT = sys.argv[1] if len(sys.argv) > 1 else "5300"
BASE = "http://127.0.0.1:%s" % PORT
resultats = []

# ── Les positions de l'essai ────────────────────────────────────────────────
# Valide : un Heritier par camp, et des carrees cote a cote des deux cotes.
VALIDE = "B/sgshgsg/gnnnnns/---c---/-------/-------/---C---/GNNNNNS/SGSHGSG"
# La meme, aux Noirs de jouer : le trait de la partie doit en venir.
VALIDE_N = "N" + VALIDE[1:]
# Un seul Soldat par camp, aucun voisin carre : personne ne peut bouger.
BLOQUEE = "B/h-----s/-------/-------/-------/-------/-------/-------/H-----S"
# Plateau PLEIN, sauf deux cases : rien ne peut avancer. Les deux Heritiers sont
# la et les carrees peuvent bouger — c'est bien le manque de place qui refuse.
TROP_PLEINE = ("B/hgggggg/ggggggg/ggggggg/ggggggg/GGGGGGG/GGGGGGG/GGGGGGG/"
               "GGGGG-H")
# La meme, avec trois cases libres : elle doit passer.
ASSEZ_VIDE = ("B/hgggggg/ggggggg/ggggggg/ggggggg/GGGGGGG/GGGGGGG/GGGGGGG/"
              "GGG---H")
# Deux Chevaliers blancs : le composeur n'en pose jamais un second, un code
# ecrit a la main si.
DEUX_CHEVALIERS = ("B/sgshgsg/gnnnnns/c--c---/-------/-------/---C---/GNNNNNS/"
                   "SGSHGSG")
# Un seul par camp, et zero chez les Noirs : permis.
UN_CHEVALIER = ("B/sgshgsg/gnnnnns/c------/-------/-------/-------/GNNNNNS/"
                "SGSHGSG")
# Pas d'Heritier blanc (le `h` est devenu une Nurse).
SANS_HERITIER = "B/sgsngsg/gnnnnns/---c---/-------/-------/---C---/GNNNNNS/SGSHGSG"
# Deux Heritiers blancs.
DEUX_HERITIERS = "B/sgshhsg/gnnnnns/---c---/-------/-------/---C---/GNNNNNS/SGSHGSG"
# Mal formees : sept rangees, une rangee de six, une lettre inconnue, un trait
# qui n'est ni B ni N, et rien du tout.
MALFORMEES = {
    "sept rangees": "B/sgshgsg/gnnnnns/---c---/-------/-------/GNNNNNS/SGSHGSG",
    "rangee de six": "B/sgshgs/gnnnnns/---c---/-------/-------/---C---/GNNNNNS/SGSHGSG",
    "lettre inconnue": "B/sgshxsg/gnnnnns/---c---/-------/-------/---C---/GNNNNNS/SGSHGSG",
    "trait inconnu": "X/sgshgsg/gnnnnns/---c---/-------/-------/---C---/GNNNNNS/SGSHGSG",
    "vide": "",
}


def http(path, payload):
    req = urllib.request.Request(
        BASE + path, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        # Les refus sont des reponses comme les autres : on veut les lire.
        try:
            return json.loads(e.read())
        except Exception:
            return {"ok": False, "error": "HTTP %s" % e.code}


class Joueur(object):
    def __init__(self, pseudo):
        self.pseudo = pseudo
        r = http("/register", {"pseudo": pseudo, "password": "motdepasse"})
        if not r.get("ok"):
            r = http("/login", {"pseudo": pseudo, "password": "motdepasse"})
        self.token = r["token"]

    def post(self, path, payload):
        p = dict(payload)
        p["token"] = self.token
        return http(path, p)

    def partie(self, gid):
        for g in self.post("/corr_list", {}).get("games", []):
            if str(g.get("id")) == str(gid):
                return g
        return {}

    def parties(self):
        return self.post("/corr_list", {}).get("games", [])


def verifie(titre, condition, detail=""):
    resultats.append(bool(condition))
    print("%-64s %s" % (titre, "OK" if condition else "ECHEC"))
    if detail:
        print("      %s" % detail)


def menage(j):
    """Referme toutes les parties de ce joueur : dix au plus a la fois."""
    for g in j.parties():
        gid = g.get("id")
        if g.get("statut") == "defi":
            # Un defi se refuse par le DEFIE seulement ; sinon on abandonne.
            if not g.get("is_defieur"):
                j.post("/corr_repondre", {"game_id": gid, "accepte": False})
                continue
        if g.get("statut") != "termine":
            j.post("/corr_abandon", {"game_id": gid})
        j.post("/corr_close", {"game_id": gid})


def defier(a, b, **extra):
    """a defie b. Rend (reponse, game_id ou None)."""
    charge = {"pseudo": b.pseudo, "objectif": "partie"}
    charge.update(extra)
    r = a.post("/corr_defier", charge)
    return r, r.get("game_id")


def main():
    a = Joueur("sonde_pos_a")
    b = Joueur("sonde_pos_b")
    menage(a)
    menage(b)

    print("")
    print("── 1. La position composee voyage ──────────────────────────────")
    r, gid = defier(a, b, mode="personnalise", position=VALIDE, couleur="Blanc")
    verifie("un defi en position composee est accepte", r.get("ok"), str(r))
    if not gid:
        print("Sans partie creee, le reste n'a pas de sens.")
        return 1
    ga, gb = a.partie(gid), b.partie(gid)
    verifie("le mode est 'personnalise'", ga.get("mode") == "personnalise",
            "recu : %r" % ga.get("mode"))
    verifie("la position est rendue telle quelle", ga.get("position") == VALIDE,
            "recu : %r" % ga.get("position"))
    verifie("l'adversaire voit la meme position",
            gb.get("position") == VALIDE)
    verifie("une position composee n'a pas de code Random",
            ga.get("random_code") == "", "recu : %r" % ga.get("random_code"))
    verifie("le trait est aux Blancs quand le .fug dit B",
            ga.get("turn") == "Blanc", "recu : %r" % ga.get("turn"))

    print("")
    print("── 2. Le trait vient de la position ────────────────────────────")
    r2, gid2 = defier(a, b, mode="personnalise", position=VALIDE_N,
                      couleur="Blanc")
    g2 = a.partie(gid2)
    verifie("le trait est aux Noirs quand le .fug dit N",
            g2.get("turn") == "Noir", "recu : %r" % g2.get("turn"))
    b.post("/corr_repondre", {"game_id": gid2, "accepte": True})
    g2 = a.partie(gid2)
    verifie("et il le reste une fois la partie acceptee",
            g2.get("turn") == "Noir", "recu : %r" % g2.get("turn"))
    verifie("c'est donc aux NOIRS de jouer, pas au defieur blanc",
            g2.get("my_turn") is False and b.partie(gid2).get("my_turn") is True)
    # Et la partie se joue vraiment dans cet ordre : une partie qui COMMENCE
    # par les Noirs est un chemin que le serveur n'avait jamais pris.
    r_tot = a.post("/corr_jouer", {"game_id": gid2, "notation": "Do2-Do3"})
    verifie("le defieur blanc ne peut pas jouer avant les Noirs",
            not r_tot.get("ok"), "recu : %r" % r_tot)
    r_noir = b.post("/corr_jouer", {"game_id": gid2, "notation": "Do7-Do6"})
    verifie("les Noirs jouent le premier coup", r_noir.get("ok"),
            "recu : %r" % r_noir)
    verifie("et le trait passe ensuite aux Blancs",
            a.partie(gid2).get("turn") == "Blanc"
            and a.partie(gid2).get("my_turn") is True)

    print("")
    print("── 3. Le serveur refuse ce qu'il ne sait pas jouer ─────────────")
    avant = len(a.parties())
    for nom, pos in sorted(MALFORMEES.items()):
        r3, g3 = defier(a, b, mode="personnalise", position=pos)
        verifie("refus : %s" % nom,
                (not r3.get("ok")) and r3.get("error") == "position_illisible",
                "recu : %r" % r3)
    r3, _ = defier(a, b, mode="personnalise", position=SANS_HERITIER)
    verifie("refus : un camp sans Heritier",
            r3.get("error") == "position_heritier", "recu : %r" % r3)
    r3, _ = defier(a, b, mode="personnalise", position=DEUX_HERITIERS)
    verifie("refus : deux Heritiers du meme camp",
            r3.get("error") == "position_heritier", "recu : %r" % r3)
    r3, _ = defier(a, b, mode="personnalise", position=BLOQUEE)
    verifie("refus : des carrees qui ne peuvent pas bouger",
            r3.get("error") == "position_carrees", "recu : %r" % r3)
    r3, _ = defier(a, b, mode="personnalise", position=DEUX_CHEVALIERS)
    verifie("refus : deux Chevaliers du meme camp",
            r3.get("error") == "position_chevalier", "recu : %r" % r3)
    # Troisieme regle : au moins trois cases libres. Un plateau plein ne laisse
    # nulle part ou aller.
    r3, _ = defier(a, b, mode="personnalise", position=TROP_PLEINE)
    verifie("refus : moins de trois cases libres",
            r3.get("error") == "position_vides", "recu : %r" % r3)
    verifie("AUCUNE partie n'a ete creee par ces refus",
            len(a.parties()) == avant,
            "%d parties avant, %d apres" % (avant, len(a.parties())))
    # Et la meme position avec trois cases libres passe : la regle refuse ce
    # qu'il faut, pas tout.
    r3, g3 = defier(a, b, mode="personnalise", position=ASSEZ_VIDE,
                    couleur="Blanc")
    verifie("mais trois cases libres suffisent", r3.get("ok"),
            "recu : %r" % r3)
    # Un Chevalier chez l'un, aucun chez l'autre : permis. En mettre n'est pas
    # obligatoire, en mettre deux ne l'est pas.
    r3, _ = defier(a, b, mode="personnalise", position=UN_CHEVALIER,
                   couleur="Blanc")
    verifie("un seul Chevalier passe, et zero aussi", r3.get("ok"),
            "recu : %r" % r3)

    print("")
    print("── 4. Les autres modes ne changent pas ─────────────────────────")
    r4, gid4 = defier(a, b, mode="standard", couleur="Blanc")
    g4 = a.partie(gid4)
    verifie("standard : mode 'standard', pas de position, trait aux Blancs",
            g4.get("mode") == "standard" and g4.get("position") == ""
            and g4.get("turn") == "Blanc", str(g4.get("mode")))
    r5, gid5 = defier(a, b, mode="random", couleur="Blanc")
    g5 = a.partie(gid5)
    verifie("random : un code est tire et le mode le dit",
            g5.get("mode") == "random" and len(g5.get("random_code") or "") > 0,
            "code : %r" % g5.get("random_code"))
    verifie("random : aucune position composee",
            g5.get("position") == "")
    # Une position envoyee hors du mode personnalise ne doit pas etre gardee :
    # elle ne decrirait rien de ce qui se joue.
    r6, gid6 = defier(a, b, mode="standard", position=VALIDE, couleur="Blanc")
    verifie("une position envoyee en mode standard est ignoree",
            a.partie(gid6).get("position") == "",
            "recu : %r" % a.partie(gid6).get("position"))

    print("")
    print("── 5. La couleur demandee est respectee ────────────────────────")
    menage(a)
    menage(b)
    r7, gid7 = defier(a, b, mode="personnalise", position=VALIDE,
                      couleur="Blanc")
    verifie("couleur Blanc : le defieur a les Blancs",
            a.partie(gid7).get("ma_couleur") == "Blanc"
            and b.partie(gid7).get("ma_couleur") == "Noir")
    verifie("et le defi l'annonce",
            a.partie(gid7).get("couleur") == "Blanc",
            "recu : %r" % a.partie(gid7).get("couleur"))
    b.post("/corr_repondre", {"game_id": gid7, "accepte": True})
    verifie("elle ne change pas a l'acceptation",
            a.partie(gid7).get("ma_couleur") == "Blanc")
    r8, gid8 = defier(a, b, mode="personnalise", position=VALIDE,
                      couleur="Noir")
    verifie("couleur Noir : le defieur a les Noirs",
            a.partie(gid8).get("ma_couleur") == "Noir"
            and b.partie(gid8).get("ma_couleur") == "Blanc")
    b.post("/corr_repondre", {"game_id": gid8, "accepte": True})
    verifie("elle ne change pas non plus a l'acceptation",
            a.partie(gid8).get("ma_couleur") == "Noir")

    print("")
    print("── 6. La couleur aleatoire se tire A L'ACCEPTATION ─────────────")
    # Une partie ne prouve rien : on en lance assez pour voir la couleur
    # changer. Si le tirage avait lieu a la creation, elle ne changerait jamais.
    tours, changements, annoncee = 24, 0, True
    for _ in range(tours):
        menage(a)
        menage(b)
        _, g = defier(a, b, mode="personnalise", position=VALIDE)
        avant_c = a.partie(g).get("ma_couleur")
        if a.partie(g).get("couleur") != "":
            annoncee = False
        b.post("/corr_repondre", {"game_id": g, "accepte": True})
        if a.partie(g).get("ma_couleur") != avant_c:
            changements += 1
    verifie("le defi n'annonce AUCUNE couleur", annoncee)
    verifie("la couleur change entre le defi et le depart",
            changements > 0,
            "%d changements sur %d parties (0 = tirage a la creation)"
            % (changements, tours))
    verifie("elle ne change pas a tous les coups non plus",
            changements < tours,
            "%d sur %d" % (changements, tours))
    # Et apres le depart, les deux joueurs voient des couleurs opposees.
    menage(a)
    menage(b)
    _, g9 = defier(a, b, mode="personnalise", position=VALIDE)
    b.post("/corr_repondre", {"game_id": g9, "accepte": True})
    ca = a.partie(g9).get("ma_couleur")
    cb = b.partie(g9).get("ma_couleur")
    verifie("les deux joueurs ont des couleurs opposees",
            {ca, cb} == {"Blanc", "Noir"}, "%s / %s" % (ca, cb))

    print("")
    print("── 7. Une ANCIENNE application garde l'ancien comportement ─────")
    # Pas de `mode` envoye : la couleur est tiree a la creation, et ne doit
    # jamais changer — le client Kivy oriente son apercu selon elle.
    tours, changements = 24, 0
    for _ in range(tours):
        menage(a)
        menage(b)
        _, g = defier(a, b)
        avant_c = a.partie(g).get("ma_couleur")
        b.post("/corr_repondre", {"game_id": g, "accepte": True})
        if a.partie(g).get("ma_couleur") != avant_c:
            changements += 1
    verifie("sans `mode`, la couleur ne change JAMAIS a l'acceptation",
            changements == 0, "%d changements sur %d" % (changements, tours))
    menage(a)
    menage(b)
    _, g10 = defier(a, b)
    verifie("sans `mode`, le mode rendu est deduit : 'standard'",
            a.partie(g10).get("mode") == "standard",
            "recu : %r" % a.partie(g10).get("mode"))
    _, g11 = defier(a, b, random=True)
    verifie("sans `mode` mais `random`, le mode rendu est 'random'",
            a.partie(g11).get("mode") == "random",
            "recu : %r" % a.partie(g11).get("mode"))

    print("")
    print("── 8. L'archive .nmc garde la position ─────────────────────────")
    menage(a)
    menage(b)
    _, g12 = defier(a, b, mode="personnalise", position=VALIDE, couleur="Blanc")
    b.post("/corr_repondre", {"game_id": g12, "accepte": True})
    a.post("/corr_jouer", {"game_id": g12, "notation": "Do2-Do3"})
    b.post("/corr_jouer", {"game_id": g12, "notation": "Do7-Do6"})
    a.post("/corr_jouer", {"game_id": g12, "notation": "Fa8*",
                           "methode": "fugue", "gagnant": "Blanc"})
    nmc = a.post("/get_game", {"game_uid": "online_corr%s" % g12})
    texte = nmc.get("nmc_text") or ""
    verifie("la partie est archivee", nmc.get("ok"), str(nmc)[:120])
    verifie("l'en-tete porte [Position \"...\"]",
            '[Position "%s"]' % VALIDE in texte,
            "en-tete : %r" % texte.split("\n\n")[0][-120:])
    verifie("les coups y sont aussi", "Do2-Do3" in texte)
    # Une partie standard n'a PAS de ligne Position : rien n'est ajoute a ce
    # qui n'en a pas besoin.
    _, g13 = defier(a, b, mode="standard", couleur="Blanc")
    b.post("/corr_repondre", {"game_id": g13, "accepte": True})
    a.post("/corr_jouer", {"game_id": g13, "notation": "Fa8*",
                           "methode": "fugue", "gagnant": "Blanc"})
    t13 = (a.post("/get_game", {"game_uid": "online_corr%s" % g13})
           .get("nmc_text") or "")
    verifie("une partie standard n'a pas de ligne Position",
            "[Position" not in t13)

    menage(a)
    menage(b)
    print("")
    print("%d/%d" % (sum(1 for x in resultats if x), len(resultats)))
    return 0 if all(resultats) else 1


if __name__ == "__main__":
    sys.exit(main())
