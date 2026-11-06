# -*- coding: utf-8 -*-
"""Le melo d'une partie : range, mis a jour, rendu, et annonce aux deux.

CE TEST NE TOUCHE RIEN. Il n'a besoin ni du serveur de production ni meme
d'un `server.py` : il fabrique un serveur de poche qui porte exactement les
six motifs du patch, lui applique `patch_melo_historique.py`, puis execute
le resultat sur une base SQLite a lui. C'est donc le VRAI code livre qui est
mesure, et non une copie de sa logique.

    python3 tests/test_melo_historique.py
"""
import os
import sqlite3
import subprocess
import sys
import tempfile

ICI = os.path.dirname(os.path.abspath(__file__))
SERVEUR = os.path.dirname(ICI)

# Le serveur de poche : les six motifs, et juste de quoi les executer.
POCHE = '''
def init_db(c):
    c.execute("""
        CREATE TABLE IF NOT EXISTS games (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            game_uid TEXT NOT NULL,
            nmc_text TEXT NOT NULL,
            joueur1 TEXT,
            joueur2 TEXT,
            resultat TEXT,
            methode TEXT,
            cadence TEXT,
            objectif TEXT,
            played_at INTEGER NOT NULL,
            FOREIGN KEY (user_id) REFERENCES users(id)
        )
    """)
    c.execute("CREATE INDEX IF NOT EXISTS idx_games_user ON games(user_id)")
    c.execute("CREATE INDEX IF NOT EXISTS idx_games_uid ON games(game_uid)")


def save_game():
    data = request.get_json(silent=True) or {}
    user = user_from_token(data.get("token", ""))
    if not user:
        return jsonify({"ok": False, "error": "Token invalide"}), 401

    game_uid = (data.get("game_uid") or "").strip()
    nmc_text = data.get("nmc_text") or ""
    if not game_uid or not nmc_text:
        return jsonify({"ok": False, "error": "Donnees manquantes"}), 400

    conn = get_db()
    # Eviter le doublon pour ce joueur
    existing = conn.execute(
        "SELECT id FROM games WHERE user_id = ? AND game_uid = ?",
        (user["id"], game_uid)
    ).fetchone()
    if existing:
        conn.close()
        return jsonify({"ok": True, "duplicate": True})

    conn.execute(
        "INSERT INTO games (user_id, game_uid, nmc_text, joueur1, joueur2, "
        "resultat, methode, cadence, objectif, played_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (user["id"], game_uid, nmc_text,
         data.get("joueur1", ""), data.get("joueur2", ""),
         data.get("resultat", ""), data.get("methode", ""),
         str(data.get("cadence", "")), str(data.get("objectif", "")),
         int(time.time()))
    )
    conn.commit()
    conn.close()
    return jsonify({"ok": True})


def list_games():
    target_id = 1
    rows = get_db().execute(
        "SELECT game_uid, joueur1, joueur2, resultat, methode, cadence, "
        "objectif, played_at FROM games WHERE user_id = ? "
        "ORDER BY played_at DESC, id DESC",
        (target_id,)
    ).fetchall()
    return jsonify({"ok": True, "games": [dict(r) for r in rows]})


def fin_par_abandon(game_id, melo_result, winner_color, color_dc, winner_sid):
    if melo_result and winner_color:
        if True:
            sio.emit("melo_maj", {
                "game_id": game_id,
                "mon_melo": melo_result[winner_color]["apres"],
                "delta": melo_result[winner_color]["delta"],
            }, to=winner_sid)


def fin_normale(game_id, melo_result, blanc_sid, noir_sid):
    if melo_result:
        if blanc_sid:
            sio.emit("melo_maj", {
                "game_id": game_id,
                "mon_melo": melo_result["Blanc"]["apres"],
                "delta": melo_result["Blanc"]["delta"],
            }, to=blanc_sid)
        if noir_sid:
            sio.emit("melo_maj", {
                "game_id": game_id,
                "mon_melo": melo_result["Noir"]["apres"],
                "delta": melo_result["Noir"]["delta"],
            }, to=noir_sid)
'''

MELO = {
    "Blanc": {"apres": 1512, "delta": 12},
    "Noir": {"apres": 1488, "delta": -12},
}


def _portee(chemin_base):
    """Les quelques noms que le serveur de poche attend du dehors."""
    envois = []

    class _Sio(object):
        def emit(self, nom, data, to=None):
            envois.append((nom, data, to))

    def get_db():
        conn = sqlite3.connect(chemin_base)
        conn.row_factory = sqlite3.Row
        return conn

    class _Req(object):
        corps = {}

        def get_json(self, silent=False):
            return self.corps

    import time as _time
    requete = _Req()
    return {
        "sio": _Sio(),
        "get_db": get_db,
        "request": requete,
        "jsonify": lambda x: x,
        "user_from_token": lambda t: {"id": 1} if t else None,
        "time": _time,
    }, envois, requete


def main():
    dossier = tempfile.mkdtemp(prefix="melohisto-")
    poche = os.path.join(dossier, "server.py")
    with open(poche, "w", encoding="utf-8") as f:
        f.write(POCHE)

    # L'essai d'abord : il doit trouver les six motifs sans rien ecrire.
    r = subprocess.run(
        [sys.executable, os.path.join(SERVEUR, "patch_melo_historique.py"),
         poche, "--essai"], capture_output=True, text=True)
    if "ESSAI" not in r.stdout:
        print("ECHEC : l'essai n'a pas trouve les six motifs")
        print(r.stdout, r.stderr)
        return 1

    r = subprocess.run(
        [sys.executable, os.path.join(SERVEUR, "patch_melo_historique.py"),
         poche], capture_output=True, text=True)
    if r.returncode != 0 or "ECRIT." not in r.stdout:
        print("ECHEC : le patch ne s'est pas applique")
        print(r.stdout, r.stderr)
        return 1

    base = os.path.join(dossier, "lafuga.db")
    portee, envois, requete = _portee(base)
    with open(poche, encoding="utf-8") as f:
        exec(compile(f.read(), poche, "exec"), portee)

    # La table, puis la migration : on la cree D'ABORD sans les colonnes,
    # comme la base de production, pour que l'ALTER TABLE ait du travail.
    brute = sqlite3.connect(base)
    brute.execute("CREATE TABLE games (id INTEGER PRIMARY KEY AUTOINCREMENT,"
                  " user_id INTEGER NOT NULL, game_uid TEXT NOT NULL,"
                  " nmc_text TEXT NOT NULL, joueur1 TEXT, joueur2 TEXT,"
                  " resultat TEXT, methode TEXT, cadence TEXT,"
                  " objectif TEXT, played_at INTEGER NOT NULL)")
    brute.commit()
    brute.close()

    conn = portee["get_db"]()
    portee["init_db"](conn)
    conn.commit()
    colonnes = [r[1] for r in conn.execute("PRAGMA table_info(games)")]
    conn.close()
    for attendu in ("blanc", "melo1", "melo2", "variation1", "variation2"):
        if attendu not in colonnes:
            print("ECHEC : la colonne %s manque apres la migration" % attendu)
            return 1
    print("migration : %s" % ", ".join(colonnes[-5:]))

    # Premier enregistrement : la partie, SANS le melo — il n'est pas encore
    # annonce.
    requete.corps = {
        "token": "t", "game_uid": "online_g1", "nmc_text": '[Date "x"]',
        "joueur1": "nino", "joueur2": "celia", "resultat": "1-0",
        "methode": "fugue", "cadence": "5", "objectif": "partie",
        "blanc": "nino",
    }
    portee["save_game"]()

    # Second : le melo est arrive. La ligne doit etre MISE A JOUR.
    requete.corps = dict(requete.corps)
    requete.corps.update({
        "nmc_text": '[Date "x"]\n[Melo1 "1512"]',
        "melo1": 1512, "melo2": 1488, "variation1": 12, "variation2": -12,
    })
    portee["save_game"]()

    reponse = portee["list_games"]()
    jeux = reponse["games"]
    if len(jeux) != 1:
        print("ECHEC : %d parties au lieu d'une (doublon mal gere)" % len(jeux))
        return 1
    g = jeux[0]
    attendu = {"blanc": "nino", "melo1": 1512, "melo2": 1488,
               "variation1": 12, "variation2": -12}
    for cle, valeur in attendu.items():
        if g.get(cle) != valeur:
            print("ECHEC : %s vaut %r au lieu de %r" % (cle, g.get(cle), valeur))
            return 1
    # `list_games` ne rend pas le `.nmc` — c'est voulu, il est gros — alors
    # on le lit en base.
    conn = portee["get_db"]()
    texte = conn.execute("SELECT nmc_text FROM games").fetchone()["nmc_text"]
    conn.close()
    if "[Melo1" not in texte:
        print("ECHEC : le .nmc n'a pas ete rafraichi : %r" % texte)
        return 1
    print("save_game : %s" % {k: g[k] for k in attendu})

    # Un troisieme envoi QUI EN SAIT MOINS ne doit rien effacer.
    requete.corps = {
        "token": "t", "game_uid": "online_g1", "nmc_text": '[Date "x"]',
        "joueur1": "nino", "joueur2": "celia", "resultat": "1-0",
        "methode": "fugue",
    }
    portee["save_game"]()
    g = portee["list_games"]()["games"][0]
    if g["melo1"] != 1512 or g["blanc"] != "nino":
        print("ECHEC : un envoi sans melo a efface ce qu'on savait : %r" % g)
        return 1
    print("coalesce : ce qu'on savait est garde")

    # Les annonces : chacun doit apprendre les DEUX melos.
    del envois[:]
    portee["fin_normale"]("g1", MELO, "sid-blanc", "sid-noir")
    portee["fin_par_abandon"]("g1", MELO, "Blanc", "Noir", "sid-blanc")
    if len(envois) != 3:
        print("ECHEC : %d annonces au lieu de trois" % len(envois))
        return 1
    blanc = envois[0][1]
    noir = envois[1][1]
    abandon = envois[2][1]
    if (blanc["mon_melo"], blanc["delta"]) != (1512, 12) or \
       (blanc["son_melo"], blanc["son_delta"]) != (1488, -12):
        print("ECHEC : l'annonce du Blanc : %r" % blanc)
        return 1
    if (noir["mon_melo"], noir["delta"]) != (1488, -12) or \
       (noir["son_melo"], noir["son_delta"]) != (1512, 12):
        print("ECHEC : l'annonce du Noir : %r" % noir)
        return 1
    if (abandon["son_melo"], abandon["son_delta"]) != (1488, -12):
        print("ECHEC : l'annonce d'abandon : %r" % abandon)
        return 1
    print("melo_maj : Blanc %+d/%+d, Noir %+d/%+d, abandon %+d/%+d"
          % (blanc["delta"], blanc["son_delta"],
             noir["delta"], noir["son_delta"],
             abandon["delta"], abandon["son_delta"]))

    print("OK : colonnes, mise a jour, coalesce, liste et annonces")
    return 0


if __name__ == "__main__":
    sys.exit(main())
