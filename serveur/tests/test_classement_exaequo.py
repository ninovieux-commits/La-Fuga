# -*- coding: utf-8 -*-
"""Les melos egaux font le meme rang — et ma ligne dit la meme chose.

Nino : « les personnes qui ont le meme melo doivent avoir le meme
classement. »

CE TEST NE TOUCHE RIEN. Il n'a besoin ni du serveur de production, ni meme
d'un `server.py` : il fabrique un serveur de poche reduit a l'ancre des
patches, y applique `patch_classement.py` puis
`patch_classement_exaequo.py`, et execute la route obtenue sur une base
SQLite en memoire. C'est donc le VRAI code livre qui est mesure, et non une
copie de sa logique.

    python3 tests/test_classement_exaequo.py
"""
import os
import sqlite3
import subprocess
import sys
import tempfile

ICI = os.path.dirname(os.path.abspath(__file__))
SERVEUR = os.path.dirname(ICI)

# L'ancre dont `patch_classement.py` a besoin, et rien de plus.
POCHE = '''@flask_app.route("/env_liste", methods=["POST"])
def env_liste():
    return jsonify({"ok": True})
'''

# pseudo, melo. Deux paires d'ex aequo, pour verifier que la place sautee
# est bien sautee les deux fois.
COMPTES = [
    ("nino", 1530),
    ("Vem", 1500),
    ("mesange", 1500),
    ("lilou", 1491),
    ("celia", 1449),
    ("corbeau", 1449),
    ("alouette", 1400),
]

# La numerotation des competitions : le rang est le nombre de comptes qui
# font strictement mieux, plus un.
ATTENDU = [1, 2, 2, 4, 5, 5, 7]


def _route(chemin):
    """Execute la route `classement` du fichier, et rend sa reponse."""
    base = sqlite3.connect(":memory:")
    base.row_factory = sqlite3.Row
    base.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, pseudo TEXT,"
                 " melo INTEGER, melo_random INTEGER, photo TEXT)")
    for i, (pseudo, melo) in enumerate(COMPTES, start=1):
        base.execute("INSERT INTO users VALUES (?,?,?,?,?)",
                     (i, pseudo, melo, melo, ""))
    base.commit()

    class _App(object):
        def route(self, *a, **k):
            return lambda f: f

    class _Req(object):
        def get_json(self, silent=False):
            return {"token": "t", "random": False}

    # Mesange : le troisieme compte, celui qui est ex aequo.
    portee = {
        "flask_app": _App(),
        "request": _Req(),
        "jsonify": lambda x: x,
        "get_db": lambda: base,
        "user_from_token": lambda t: {"id": 3},
    }
    with open(chemin, encoding="utf-8") as f:
        code = f.read()
    exec(compile(code, chemin, "exec"), portee)
    reponse = portee["classement"]()
    return reponse[0] if isinstance(reponse, tuple) else reponse


def main():
    dossier = tempfile.mkdtemp(prefix="classement-")
    poche = os.path.join(dossier, "server.py")
    with open(poche, "w", encoding="utf-8") as f:
        f.write(POCHE)

    for patch in ("patch_classement.py", "patch_classement_exaequo.py"):
        r = subprocess.run(
            [sys.executable, os.path.join(SERVEUR, patch), poche],
            capture_output=True, text=True)
        if r.returncode != 0 or "ECRIT." not in r.stdout:
            print("ECHEC : %s n'a pas pu s'appliquer" % patch)
            print(r.stdout, r.stderr)
            return 1

    reponse = _route(poche)
    rangs = [j["rang"] for j in reponse["joueurs"]]
    for j in reponse["joueurs"]:
        print("%2d  %-10s %d" % (j["rang"], j["pseudo"], j["melo"]))
    print("ma ligne : %d  %s  %d"
          % (reponse["moi"]["rang"], reponse["moi"]["pseudo"],
             reponse["moi"]["melo"]))

    if rangs != ATTENDU:
        print("ECHEC : rangs %s au lieu de %s" % (rangs, ATTENDU))
        return 1

    mienne = [j for j in reponse["joueurs"]
              if j["pseudo"] == reponse["moi"]["pseudo"]]
    if not mienne or mienne[0]["rang"] != reponse["moi"]["rang"]:
        print("ECHEC : ma ligne et la liste ne disent pas le meme rang")
        return 1

    # L'ORDRE D'AFFICHAGE NE BOUGE PAS : les ex aequo restent ranges par
    # pseudo croissant, comme avant.
    pseudos = [j["pseudo"] for j in reponse["joueurs"]]
    if pseudos != [p for p, _ in COMPTES]:
        print("ECHEC : l ordre d affichage a change : %s" % pseudos)
        return 1

    print("OK : ex aequo, ma ligne d accord, ordre inchange")
    return 0


if __name__ == "__main__":
    sys.exit(main())
