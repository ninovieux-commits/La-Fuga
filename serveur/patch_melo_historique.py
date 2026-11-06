# -*- coding: utf-8 -*-
"""Les melos d'une partie, annonces aux DEUX joueurs et ranges dans l'historique.

Nino : « il faut que les melos gagnes et perdus durant une partie soient
specifies dans l'historique, a cote des noms des joueurs », puis « ajoute
aussi le melo des joueurs tel que : mesange 1500 -9 vs nino 1512 +9 ».

L'application sait deja afficher les quatre nombres. Il lui manque de quoi
les connaitre et de quoi les retrouver. Six corrections, et aucune ne touche
au calcul du melo lui-meme.

1. LA TABLE `games` GAGNE CINQ COLONNES : qui tenait les Blancs, les deux
   classements d'apres la partie, les deux variations. Migration douce, a la
   facon de celles de `corr_games` : un ALTER TABLE par colonne, dans un
   try/except, sans defaut pour les nombres — NULL veut dire « on ne sait
   pas », et zero est un vrai classement comme une vraie variation.

2. `save_game` RANGE CES CINQ COLONNES.

3. ET IL NE JETTE PLUS LE DOUBLON. C'est le point qu'on n'avait pas vu :
   l'application enregistre la partie DEUX FOIS — des la fin, pour ne pas la
   perdre si le serveur tarde, puis a nouveau quand le melo est annonce,
   puisqu'elle ne le connait pas avant. Le second envoi tombait sur la garde
   anti-doublon et repartait sans rien ecrire : le melo n'aurait jamais ete
   range. Il met desormais la ligne A JOUR, en gardant sa date de depot, et
   `COALESCE` protege ce qu'on sait deja d'un envoi qui en saurait moins.

4. `list_games` REND CES CINQ COLONNES.

5-6. `melo_maj` DIT AUSSI LE MELO DE L'ADVERSAIRE. Le serveur les calcule
   deja tous les deux — `melo_result` porte « Blanc » et « Noir » — et
   n'envoyait a chacun que le sien. Deux champs de plus, `son_melo` et
   `son_delta`, dans les trois annonces : les deux de la fin normale et
   celle de l'abandon par deconnexion.

CE QUI NE CHANGE PAS : le calcul du melo, les routes, les autres evenements,
et ce que les anciennes applications recoivent — elles liront les champs
qu'elles connaissent et ignoreront les nouveaux.

USAGE
    python3 patch_melo_historique.py /chemin/vers/server.py --essai
    python3 patch_melo_historique.py /chemin/vers/server.py

`--essai` ne fait que compter les six motifs et n'ecrit rien. Sans lui, le
script refuse d'ecrire si l'un d'eux n'est pas trouve exactement une fois, y
compris sur un fichier deja corrige, et pose une sauvegarde horodatee avant
toute ecriture.
"""
import datetime
import hashlib
import io
import os
import shutil
import sys

EDITS = []


def edit(nom, ancien, nouveau):
    EDITS.append((nom, ancien, nouveau))


# ───────────────────────────────────────────────────────────────────────────
# 1. Cinq colonnes pour la table des parties, et leur migration douce.
# ───────────────────────────────────────────────────────────────────────────
edit("colonnes de melo sur games",
     '''            objectif TEXT,
            played_at INTEGER NOT NULL,
            FOREIGN KEY (user_id) REFERENCES users(id)
        )
    """)
    c.execute("CREATE INDEX IF NOT EXISTS idx_games_user ON games(user_id)")
    c.execute("CREATE INDEX IF NOT EXISTS idx_games_uid ON games(game_uid)")''',
     '''            objectif TEXT,
            played_at INTEGER NOT NULL,
            blanc TEXT DEFAULT '',
            melo1 INTEGER,
            melo2 INTEGER,
            variation1 INTEGER,
            variation2 INTEGER,
            FOREIGN KEY (user_id) REFERENCES users(id)
        )
    """)
    c.execute("CREATE INDEX IF NOT EXISTS idx_games_user ON games(user_id)")
    c.execute("CREATE INDEX IF NOT EXISTS idx_games_uid ON games(game_uid)")
    # Migration douce : qui tenait les Blancs. L'historique s'en sert pour
    # poser un rond noir ou blanc devant chaque nom.
    try:
        c.execute("ALTER TABLE games ADD COLUMN blanc TEXT DEFAULT ''")
    except Exception:
        pass  # colonne deja presente
    # Migration douce : le melo de chaque joueur APRES la partie, et ce qu'il
    # y a gagne ou perdu. SANS DEFAUT, donc NULL : zero est un vrai classement
    # et une vraie variation, « on ne sait pas » n'en est pas une — et les
    # parties d'avant ce patch ne le savent pas.
    for _col in ("melo1", "melo2", "variation1", "variation2"):
        try:
            c.execute("ALTER TABLE games ADD COLUMN %s INTEGER" % _col)
        except Exception:
            pass''')


# ───────────────────────────────────────────────────────────────────────────
# 2 et 3. `save_game` range les cinq colonnes, et le doublon met a jour.
# ───────────────────────────────────────────────────────────────────────────
edit("save_game : melo range, doublon mis a jour",
     '''    conn = get_db()
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
    return jsonify({"ok": True})''',
     '''    conn = get_db()

    # Les quatre nombres du melo, quand l'application les connait. Absents,
    # ils valent None et non zero : zero est un vrai classement comme une
    # vraie variation.
    def _nombre(cle):
        v = data.get(cle)
        if v is None or v == "":
            return None
        try:
            return int(v)
        except Exception:
            return None

    melos = (_nombre("melo1"), _nombre("melo2"),
             _nombre("variation1"), _nombre("variation2"))
    blanc = str(data.get("blanc", "") or "")

    # LA MEME PARTIE REVIENT, ET C'EST VOULU. L'application l'enregistre des
    # la fin — pour ne pas la perdre si le serveur tarde — puis une seconde
    # fois quand le melo est annonce, qu'elle ne connait pas avant. Le
    # doublon ne repart donc plus les mains vides : il MET A JOUR la ligne,
    # en lui gardant sa date de depot. `COALESCE` protege au passage ce qu'on
    # sait deja d'un envoi qui en saurait moins.
    existing = conn.execute(
        "SELECT id FROM games WHERE user_id = ? AND game_uid = ?",
        (user["id"], game_uid)
    ).fetchone()
    if existing:
        conn.execute(
            "UPDATE games SET nmc_text = ?, resultat = ?, methode = ?, "
            "blanc = COALESCE(NULLIF(?, ''), blanc), "
            "melo1 = COALESCE(?, melo1), melo2 = COALESCE(?, melo2), "
            "variation1 = COALESCE(?, variation1), "
            "variation2 = COALESCE(?, variation2) WHERE id = ?",
            (nmc_text, data.get("resultat", ""), data.get("methode", ""),
             blanc) + melos + (existing["id"],)
        )
        conn.commit()
        conn.close()
        return jsonify({"ok": True, "duplicate": True})

    conn.execute(
        "INSERT INTO games (user_id, game_uid, nmc_text, joueur1, joueur2, "
        "resultat, methode, cadence, objectif, played_at, blanc, "
        "melo1, melo2, variation1, variation2) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (user["id"], game_uid, nmc_text,
         data.get("joueur1", ""), data.get("joueur2", ""),
         data.get("resultat", ""), data.get("methode", ""),
         str(data.get("cadence", "")), str(data.get("objectif", "")),
         int(time.time()), blanc) + melos
    )
    conn.commit()
    conn.close()
    return jsonify({"ok": True})''')


# ───────────────────────────────────────────────────────────────────────────
# 4. `list_games` rend les cinq colonnes.
# ───────────────────────────────────────────────────────────────────────────
edit("list_games : rendre le melo",
     '''    rows = get_db().execute(
        "SELECT game_uid, joueur1, joueur2, resultat, methode, cadence, "
        "objectif, played_at FROM games WHERE user_id = ? "
        "ORDER BY played_at DESC, id DESC",
        (target_id,)
    ).fetchall()''',
     '''    rows = get_db().execute(
        "SELECT game_uid, joueur1, joueur2, resultat, methode, cadence, "
        "objectif, played_at, blanc, melo1, melo2, variation1, variation2 "
        "FROM games WHERE user_id = ? "
        "ORDER BY played_at DESC, id DESC",
        (target_id,)
    ).fetchall()''')


# ───────────────────────────────────────────────────────────────────────────
# 5. L'abandon par deconnexion : le gagnant apprend aussi ce que l'autre perd.
# ───────────────────────────────────────────────────────────────────────────
edit("melo_maj : abandon, les deux melos",
     '''            sio.emit("melo_maj", {
                "game_id": game_id,
                "mon_melo": melo_result[winner_color]["apres"],
                "delta": melo_result[winner_color]["delta"],
            }, to=winner_sid)''',
     '''            sio.emit("melo_maj", {
                "game_id": game_id,
                "mon_melo": melo_result[winner_color]["apres"],
                "delta": melo_result[winner_color]["delta"],
                # Celui de l'autre : l'historique ecrit les deux cotes.
                "son_melo": melo_result[color_dc]["apres"],
                "son_delta": melo_result[color_dc]["delta"],
            }, to=winner_sid)''')


# ───────────────────────────────────────────────────────────────────────────
# 6. La fin normale : chacun apprend les deux melos.
# ───────────────────────────────────────────────────────────────────────────
edit("melo_maj : Blanc apprend celui du Noir",
     '''            sio.emit("melo_maj", {
                "game_id": game_id,
                "mon_melo": melo_result["Blanc"]["apres"],
                "delta": melo_result["Blanc"]["delta"],
            }, to=blanc_sid)''',
     '''            sio.emit("melo_maj", {
                "game_id": game_id,
                "mon_melo": melo_result["Blanc"]["apres"],
                "delta": melo_result["Blanc"]["delta"],
                "son_melo": melo_result["Noir"]["apres"],
                "son_delta": melo_result["Noir"]["delta"],
            }, to=blanc_sid)''')

edit("melo_maj : Noir apprend celui du Blanc",
     '''            sio.emit("melo_maj", {
                "game_id": game_id,
                "mon_melo": melo_result["Noir"]["apres"],
                "delta": melo_result["Noir"]["delta"],
            }, to=noir_sid)''',
     '''            sio.emit("melo_maj", {
                "game_id": game_id,
                "mon_melo": melo_result["Noir"]["apres"],
                "delta": melo_result["Noir"]["delta"],
                "son_melo": melo_result["Blanc"]["apres"],
                "son_delta": melo_result["Blanc"]["delta"],
            }, to=noir_sid)''')


# ───────────────────────────────────────────────────────────────────────────
def main():
    if len(sys.argv) < 2:
        print("usage: python3 patch_melo_historique.py /chemin/server.py"
              " [--essai]")
        return 2
    chemin = sys.argv[1]
    essai = "--essai" in sys.argv
    if not os.path.isfile(chemin):
        print("introuvable : %s" % chemin)
        return 2

    source = io.open(chemin, encoding="utf-8").read()
    print("avant : %d lignes, sha256 %s"
          % (source.count("\n") + 1,
             hashlib.sha256(source.encode("utf-8")).hexdigest()))

    # D'abord on COMPTE tout, puis on decide : jamais de correction a moitie.
    manques = 0
    for nom, ancien, _ in EDITS:
        n = source.count(ancien)
        print("  %-42s %d" % (nom, n))
        if n != 1:
            manques += 1
    if manques:
        print("REFUS : %d motif(s) introuvable(s) ou en double." % manques)
        print("        Le fichier n'est pas celui attendu, ou il est deja")
        print("        corrige. Rien n'a ete ecrit.")
        return 1
    if essai:
        print("ESSAI : les six motifs sont la. Rien n'a ete ecrit.")
        return 0

    sortie = source
    for _, ancien, nouveau in EDITS:
        sortie = sortie.replace(ancien, nouveau, 1)

    try:
        compile(sortie, chemin, "exec")
    except SyntaxError as e:
        print("REFUS : le resultat ne compile pas (%s). Rien n'a ete ecrit." % e)
        return 1

    horodatage = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    sauvegarde = "%s.avant-melohisto-%s" % (chemin, horodatage)
    shutil.copy2(chemin, sauvegarde)
    print("sauvegarde : %s" % sauvegarde)

    io.open(chemin, "w", encoding="utf-8").write(sortie)
    print("apres : %d lignes, sha256 %s"
          % (sortie.count("\n") + 1,
             hashlib.sha256(sortie.encode("utf-8")).hexdigest()))
    print("ECRIT.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
