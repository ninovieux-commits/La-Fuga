# -*- coding: utf-8 -*-
"""Le pre-coup part-il quand mon telephone est eteint ?

C'est toute la question. Un pre-coup qui ne se declenche qu'a l'ouverture de
l'application ne sert a rien : a ce moment-la, on pourrait jouer. Ce test ne
fait donc JAMAIS semblant d'etre le client qui a prejoue — il enregistre un
plan, puis ferme sa socket, et regarde si le serveur joue tout seul.

USAGE
    python3 test_premove.py <port>

Le serveur doit tourner en local (voir tests/README.md). Ecrit deux comptes
de sonde et quelques parties dans SA base ; a lancer sur un serveur de test.
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
        # Les refus sont des reponses comme les autres : on veut les lire.
        # Une route absente rend une page HTML : on la lit comme un echec, pour
        # que ce fichier sache aussi s'executer contre un serveur NON patche.
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


def verifie(titre, condition, detail=""):
    resultats.append(bool(condition))
    print("%-62s %s" % (titre, "OK" if condition else "ECHEC"))
    if detail:
        print("      %s" % detail)


def coups(g):
    return [l.strip() for l in (g.get("moves_text") or "").split("\n")
            if l.strip()]


n = int(time.time()) % 100000
a = Joueur("PreA%d" % n)
b = Joueur("PreB%d" % n)


def nouvelle_partie():
    """Une partie en cours entre a et b. Renvoie (gid, celui_qui_joue, autre)."""
    r = a.post("/corr_defier", {"pseudo": b.pseudo, "objectif": "partie"})
    gid = r.get("game_id") or r.get("id")
    if gid is None:
        for g in b.post("/corr_list", {}).get("games", []):
            if g.get("statut") == "defi":
                gid = g.get("id")
    b.post("/corr_repondre", {"game_id": gid, "accepte": True})
    joueur = a if a.partie(gid).get("my_turn") else b
    autre = b if joueur is a else a
    return gid, joueur, autre


V = "variantes"


# ── 1. Le cas qui justifie tout : la reponse part sans moi ──────────────────
gid, joueur, autre = nouvelle_partie()
# `autre` attend. Il prepare sa reponse a deux coups possibles, puis s'en va.
r = autre.post("/corr_premove", {"game_id": gid, "plan": {V: [
    {"coups": ["Mi2-Mi3", "Mi7-Mi6"]},
    {"coups": ["Fa2-Fa3", "Fa7-Fa6"]},
]}})
verifie("un plan de deux variantes s'enregistre", r.get("ok"), str(r))

# Le serveur a pose la base lui-meme, sur la position REELLE.
verifie("la base vient du serveur, pas du client",
        r.get("base") == len(coups(autre.partie(gid))),
        "base=%s, coups joues=%d" % (r.get("base"),
                                     len(coups(autre.partie(gid)))))

joueur.post("/corr_jouer", {"game_id": gid, "notation": "Mi2-Mi3"})
g = joueur.partie(gid)
verifie("le coup prejoue est joue par le SERVEUR",
        coups(g) == ["Mi2-Mi3", "Mi7-Mi6"], str(coups(g)))
verifie("et c'est deja de nouveau a celui qui vient de jouer",
        g.get("my_turn") is True, "turn=%s" % g.get("turn"))
verifie("on lui doit le popup « il avait prejoue »",
        g.get("premove_adverse") is True, str(g.get("premove_adverse")))
verifie("le popup nomme l'adversaire",
        g.get("premove_par") == autre.pseudo, str(g.get("premove_par")))
verifie("celui qui a prejoue, lui, n'a pas de popup",
        autre.partie(gid).get("premove_adverse") is not True)

# Le popup s'eteint quand on l'a vu — sinon il reviendrait sans fin.
joueur.post("/corr_premove_vu", {"game_id": gid})
verifie("[Ok] eteint le popup pour de bon",
        joueur.partie(gid).get("premove_adverse") is not True)

# Le plan n'avait qu'une reponse par ligne : il a fini son office.
verifie("un plan epuise est range",
        autre.partie(gid).get("premove") in (None, {}),
        str(autre.partie(gid).get("premove")))


# ── 2. L'autre variante aurait repondu autre chose ──────────────────────────
gid, joueur, autre = nouvelle_partie()
autre.post("/corr_premove", {"game_id": gid, "plan": {V: [
    {"coups": ["Mi2-Mi3", "Mi7-Mi6"]},
    {"coups": ["Fa2-Fa3", "Fa7-Fa6"]},
]}})
joueur.post("/corr_jouer", {"game_id": gid, "notation": "Fa2-Fa3"})
verifie("c'est la variante jouee qui repond, pas la premiere",
        coups(joueur.partie(gid)) == ["Fa2-Fa3", "Fa7-Fa6"],
        str(coups(joueur.partie(gid))))


# ── 3. Il joue autre chose : rien ne part, et le plan meurt ─────────────────
gid, joueur, autre = nouvelle_partie()
autre.post("/corr_premove", {"game_id": gid, "plan": {V: [
    {"coups": ["Mi2-Mi3", "Mi7-Mi6"]},
]}})
joueur.post("/corr_jouer", {"game_id": gid, "notation": "Re2-Re3"})
g = joueur.partie(gid)
verifie("un coup imprevu ne declenche rien", coups(g) == ["Re2-Re3"],
        str(coups(g)))
verifie("et le tour passe normalement a l'adversaire",
        g.get("my_turn") is False, "turn=%s" % g.get("turn"))
verifie("aucun popup a devoir", g.get("premove_adverse") is not True)
verifie("le plan, devenu inatteignable, est efface",
        autre.partie(gid).get("premove") in (None, {}),
        str(autre.partie(gid).get("premove")))


# ── 4. Une variante profonde : il suit, on repond trois fois ───────────────
gid, joueur, autre = nouvelle_partie()
autre.post("/corr_premove", {"game_id": gid, "plan": {V: [
    {"coups": ["Mi2-Mi3", "Mi7-Mi6", "Fa2-Fa3", "Fa7-Fa6",
               "Re2-Re3", "Re7-Re6"]},
]}})
for coup in ("Mi2-Mi3", "Fa2-Fa3", "Re2-Re3"):
    joueur.post("/corr_jouer", {"game_id": gid, "notation": coup})
verifie("une variante de six demi-coups se deroule entierement",
        coups(joueur.partie(gid)) == ["Mi2-Mi3", "Mi7-Mi6", "Fa2-Fa3",
                                      "Fa7-Fa6", "Re2-Re3", "Re7-Re6"],
        str(coups(joueur.partie(gid))))
verifie("et le plan est range au bout",
        autre.partie(gid).get("premove") in (None, {}))


# ── 5. Un mat prejoue clot la partie comme un mat joue a la main ────────────
# Les deux chemins (le bloc `if methode:` de corr_jouer, et _premove_terminer)
# sont des jumeaux. On les compare sur deux parties identiques : si l'un
# derive de l'autre, cela se voit ici.
def fin_a_la_main():
    gid, joueur, autre = nouvelle_partie()
    joueur.post("/corr_jouer", {"game_id": gid, "notation": "Mi2-Mi3"})
    autre.post("/corr_jouer", {"game_id": gid, "notation": "Mi7-Mi6",
                               "methode": "mat",
                               "gagnant": autre.partie(gid).get("ma_couleur")})
    return gid, joueur.partie(gid), autre


def fin_prejouee():
    gid, joueur, autre = nouvelle_partie()
    ma_couleur = autre.partie(gid).get("ma_couleur")
    autre.post("/corr_premove", {"game_id": gid, "plan": {V: [
        {"coups": ["Mi2-Mi3", "Mi7-Mi6"], "methode": "mat",
         "gagnant": ma_couleur},
    ]}})
    joueur.post("/corr_jouer", {"game_id": gid, "notation": "Mi2-Mi3"})
    return gid, joueur.partie(gid), autre


gid_m, main, autre_m = fin_a_la_main()
gid_p, pre, autre_p = fin_prejouee()
comparables = ("statut", "resultat", "methode", "moves_text", "gagne")
ecarts = [k for k in comparables if main.get(k) != pre.get(k)]
verifie("un mat prejoue clot la partie comme un mat joue",
        not ecarts,
        "diffe sur %s : main=%s prejoue=%s"
        % (ecarts, [main.get(k) for k in ecarts], [pre.get(k) for k in ecarts])
        if ecarts else "statut=%s resultat=%s methode=%s"
        % (pre.get("statut"), pre.get("resultat"), pre.get("methode")))
verifie("le perdant voit la meme chose des deux cotes",
        autre_m.partie(gid_m).get("gagne") == autre_p.partie(gid_p).get("gagne"),
        "main=%s prejoue=%s" % (autre_m.partie(gid_m).get("gagne"),
                                autre_p.partie(gid_p).get("gagne")))
verifie("et la partie finie n'a plus de plan",
        autre_p.partie(gid_p).get("premove") in (None, {}))


# ── 6. La methode ne vaut que pour le DERNIER coup de la variante ───────────
gid, joueur, autre = nouvelle_partie()
autre.post("/corr_premove", {"game_id": gid, "plan": {V: [
    {"coups": ["Mi2-Mi3", "Mi7-Mi6", "Fa2-Fa3", "Fa7-Fa6"],
     "methode": "mat", "gagnant": autre.partie(gid).get("ma_couleur")},
]}})
joueur.post("/corr_jouer", {"game_id": gid, "notation": "Mi2-Mi3"})
g = joueur.partie(gid)
verifie("au premier coup d'une variante qui finit par un mat, "
        "la partie continue",
        g.get("statut") == "en_cours", "statut=%s" % g.get("statut"))
joueur.post("/corr_jouer", {"game_id": gid, "notation": "Fa2-Fa3"})
g = joueur.partie(gid)
verifie("et elle se termine au DERNIER", g.get("statut") == "termine",
        "statut=%s" % g.get("statut"))


# ── 7. La regle de Nino : rien ne doit se contredire ────────────────────────
gid, joueur, autre = nouvelle_partie()


def refuse(titre, plan, attendu=None):
    r = autre.post("/corr_premove", {"game_id": gid, "plan": plan})
    verifie(titre, r.get("ok") is not True,
            "accepte alors qu'il fallait refuser" if r.get("ok")
            else "refus : %s" % r.get("error"))


refuse("deux reponses au meme coup : refuse", {V: [
    {"coups": ["Mi2-Mi3", "Mi7-Mi6"]},
    {"coups": ["Mi2-Mi3", "Fa7-Fa6"]},
]})
refuse("la contradiction au fond de la variante aussi", {V: [
    {"coups": ["Mi2-Mi3", "Mi7-Mi6", "Fa2-Fa3", "Fa7-Fa6"]},
    {"coups": ["Mi2-Mi3", "Mi7-Mi6", "Fa2-Fa3", "Re7-Re6"]},
]})
refuse("une variante identique a une autre", {V: [
    {"coups": ["Mi2-Mi3", "Mi7-Mi6"]},
    {"coups": ["Mi2-Mi3", "Mi7-Mi6"]},
]})
refuse("une variante qui commence une autre", {V: [
    {"coups": ["Mi2-Mi3", "Mi7-Mi6", "Fa2-Fa3", "Fa7-Fa6"]},
    {"coups": ["Mi2-Mi3", "Mi7-Mi6"]},
]})
refuse("sept variantes", {V: [
    {"coups": ["c%d" % i, "r%d" % i]} for i in range(7)
]})
refuse("huit demi-coups", {V: [
    {"coups": ["a", "b", "c", "d", "e", "f", "g", "h"]},
]})
refuse("une variante qui s'arrete sur SON coup", {V: [
    {"coups": ["Mi2-Mi3", "Mi7-Mi6", "Fa2-Fa3"]},
]})
refuse("un coup vide", {V: [{"coups": ["Mi2-Mi3", "  "]}]})
refuse("un plan qui n'est pas un plan", {V: "n'importe quoi"})

# Celles-la ne se contredisent pas : elles se separent sur SON coup.
r = autre.post("/corr_premove", {"game_id": gid, "plan": {V: [
    {"coups": ["Mi2-Mi3", "Mi7-Mi6", "Fa2-Fa3", "Fa7-Fa6"]},
    {"coups": ["Mi2-Mi3", "Mi7-Mi6", "Re2-Re3", "Re7-Re6"]},
]}})
verifie("deux lignes qui se separent sur SON coup : acceptees",
        r.get("ok") is True, str(r))
verifie("six variantes, c'est permis",
        autre.post("/corr_premove", {"game_id": gid, "plan": {V: [
            {"coups": ["c%d" % i, "r%d" % i]} for i in range(6)
        ]}}).get("ok") is True)


# ── 8. On ne prejoue que pendant que l'adversaire reflechit ─────────────────
gid, joueur, autre = nouvelle_partie()
r = joueur.post("/corr_premove", {"game_id": gid, "plan": {V: [
    {"coups": ["Mi2-Mi3", "Mi7-Mi6"]},
]}})
verifie("prejouer quand on a soi-meme le trait : refuse",
        r.get("ok") is not True, "refus : %s" % r.get("error"))


# ── 9. Annuler ce qu'on avait prepare ──────────────────────────────────────
gid, joueur, autre = nouvelle_partie()
autre.post("/corr_premove", {"game_id": gid, "plan": {V: [
    {"coups": ["Mi2-Mi3", "Mi7-Mi6"]},
]}})
verifie("mon plan me revient avec la partie",
        (autre.partie(gid).get("premove") or {}).get(V),
        str(autre.partie(gid).get("premove")))
verifie("un plan vide efface le plan",
        autre.post("/corr_premove", {"game_id": gid, "plan": {V: []}})
        .get("ok") is True)
verifie("et il n'y a plus rien a jouer",
        autre.partie(gid).get("premove") in (None, {}))
joueur.post("/corr_jouer", {"game_id": gid, "notation": "Mi2-Mi3"})
verifie("le coup annule ne part pas",
        coups(joueur.partie(gid)) == ["Mi2-Mi3"],
        str(coups(joueur.partie(gid))))


# ── 10. Un plan n'est pas une porte d'entree ────────────────────────────────
gid, joueur, autre = nouvelle_partie()
tiers = Joueur("PreC%d" % n)
r = tiers.post("/corr_premove", {"game_id": gid, "plan": {V: [
    {"coups": ["Mi2-Mi3", "Mi7-Mi6"]},
]}})
verifie("un tiers ne prejoue pas dans la partie des autres",
        r.get("ok") is not True, "refus : %s" % r.get("error"))
r = http("/corr_premove", {"token": "faux", "game_id": gid, "plan": {V: []}})
verifie("un jeton invalide est refuse", r.get("ok") is not True)
verifie("le plan d'en face ne m'est pas montre",
        joueur.partie(gid).get("premove") in (None, {}),
        str(joueur.partie(gid).get("premove")))


print("\n%d/%d" % (sum(resultats), len(resultats)))
sys.exit(0 if all(resultats) else 1)
