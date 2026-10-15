# -*- coding: utf-8 -*-
"""Le melo du MODE joue, partout ou le serveur en nomme un.

Nino : « il faudrait que le melo indique durant une partie soit le melo du
mode correspondant (soit standard soit random) ».

La base tient deux colonnes depuis longtemps — `melo` et `melo_random` — et
`_apply_melo` ECRIT deja dans la bonne : `_col = "melo_random" if
game.get("random")`. Ce sont les LECTURES qui ne regardent pas le mode. La
file d'attente, elle, fait deja le bon choix (`melo_random if rnd`), ce qui
explique que la premiere partie d'un match Random soit juste.

TROIS LECTURES A CORRIGER, et la troisieme n'est pas un probleme d'affichage.

1. `defi_recu` — le popup « X vous defie » montre le melo standard, meme sur
   un defi Random. Pur affichage : une partie nee d'un defi est
   `is_ranked: False`, aucun melo n'y est calcule.

2. `_corr_bulk` / `_corr_game_dict` — chaque partie de correspondance porte le
   melo standard de l'adversaire, meme sur une Random Fuga. Affichage aussi :
   la correspondance n'est pas classee.

3. `_get_user_melo` — et celle-ci COMPTE. Entre deux parties d'un meme match,
   le serveur relit les melos en base pour la partie suivante... toujours dans
   la colonne standard. Sur un match Random, des la DEUXIEME partie, l'Elo est
   donc calcule a partir du melo standard des deux joueurs, puis ecrit dans
   `melo_random`. Un joueur a 1800 standard et 1500 random voit son melo
   random sauter a son niveau standard des qu'il gagne la deuxieme partie d'un
   match Random. La premiere partie, elle, est juste.

CE QUI NE CHANGE PAS. Aucune colonne ajoutee, aucune donnee ecrite par ce
patch, aucune route nouvelle. `_apply_melo` n'est pas touche : il ecrivait
deja au bon endroit. Les parties standard lisent exactement ce qu'elles
lisaient.

USAGE
    python3 patch_melo_mode.py /chemin/vers/server.py

Le script REFUSE d'ecrire si l'un des motifs n'est pas trouve exactement une
fois, y compris sur un fichier deja corrige. Une sauvegarde horodatee est
posee a cote avant toute ecriture.
"""
import datetime
import hashlib
import io
import os
import shutil
import sys


# ---------------------------------------------------------------- 1. le defi
#
# `info` et `cible_info` sortent de CONNECTED, qui porte les deux melos
# (`auth` les y met tous les deux). `rnd` est deja calcule juste au-dessus.
DEFI_MOTIF = '''        defi_id = secrets.token_hex(6)
        DEFIS[defi_id] = {
            "defieur_sid": sid, "defieur_pseudo": info["pseudo"],
            "defieur_user_id": info["user_id"], "defieur_melo": info["melo"],
            "cible_sid": cible_sid, "cible_pseudo": cible_info["pseudo"],
            "cible_user_id": cible_info["user_id"], "cible_melo": cible_info["melo"],
            "objectif": objectif, "cadence": cadence, "random": rnd,
        }'''

DEFI_REMPLACEMENT = '''        defi_id = secrets.token_hex(6)
        # Melo du MODE defie : une Random Fuga se joue au classement Random.
        _dm = info.get("melo_random", 1500) if rnd else info["melo"]
        _cm = cible_info.get("melo_random", 1500) if rnd else cible_info["melo"]
        DEFIS[defi_id] = {
            "defieur_sid": sid, "defieur_pseudo": info["pseudo"],
            "defieur_user_id": info["user_id"], "defieur_melo": _dm,
            "cible_sid": cible_sid, "cible_pseudo": cible_info["pseudo"],
            "cible_user_id": cible_info["user_id"], "cible_melo": _cm,
            "objectif": objectif, "cadence": cadence, "random": rnd,
        }'''

EMIT_MOTIF = '''    sio.emit("defi_recu", {
        "defi_id": defi_id, "defieur": info["pseudo"],
        "defieur_melo": info["melo"], "objectif": objectif, "cadence": cadence,
        "random": rnd,
    }, to=cible_sid)'''

EMIT_REMPLACEMENT = '''    sio.emit("defi_recu", {
        "defi_id": defi_id, "defieur": info["pseudo"],
        "defieur_melo": _dm, "objectif": objectif, "cadence": cadence,
        "random": rnd,
    }, to=cible_sid)'''


# ------------------------------------------------- 2. la correspondance
#
# Le cache retient desormais les DEUX melos, et `_corr_game_dict` choisit
# selon le `random_code` de la partie. Sans cache, meme regle.
BULK_MOTIF = '''        for r in conn.execute(
                "SELECT id, melo FROM users WHERE id IN (%s)" % ph, ids):
            cache["melos"][r["id"]] = r["melo"]'''

BULK_REMPLACEMENT = '''        for r in conn.execute(
                "SELECT id, melo, melo_random FROM users WHERE id IN (%s)" % ph,
                ids):
            # Les DEUX : c'est la partie, plus bas, qui dira lequel montrer.
            _mr = r["melo_random"] if r["melo_random"] is not None else 1500
            cache["melos"][r["id"]] = (r["melo"], _mr)'''

CORR_MOTIF = '''    # Mélo (global) de l'adversaire — pour l'afficher sur le slot de défi.
    opp_melo = 1500
    if cache is not None:
        opp_melo = cache["melos"].get(opp_uid, 1500)
    else:
        try:
            r = get_db().execute("SELECT melo FROM users WHERE id=?",
                                 (opp_uid,)).fetchone()
            if r:
                opp_melo = r["melo"]
        except Exception:
            pass'''

CORR_REMPLACEMENT = '''    # Mélo de l'adversaire DANS LE MODE DE CETTE PARTIE — une Random Fuga se
    # joue au classement Random, et c'est lui qu'il faut montrer.
    _rnd = bool((row["random_code"] if "random_code" in row.keys() else "") or "")
    opp_melo = 1500
    if cache is not None:
        _paire = cache["melos"].get(opp_uid)
        if _paire is not None:
            opp_melo = _paire[1] if _rnd else _paire[0]
    else:
        try:
            r = get_db().execute(
                "SELECT melo, melo_random FROM users WHERE id=?",
                (opp_uid,)).fetchone()
            if r:
                if _rnd:
                    opp_melo = (r["melo_random"]
                                if r["melo_random"] is not None else 1500)
                else:
                    opp_melo = r["melo"]
        except Exception:
            pass'''


# ------------------------------------------- 3. la partie suivante d'un match
#
# C'est la seule des trois qui touche un CALCUL : ce melo sert de base a l'Elo
# de la partie suivante, et le resultat est ecrit dans `melo_random`.
GETTER_MOTIF = '''def _get_user_melo(uid):
    """Lit le mélo courant d'un utilisateur en base."""
    try:
        row = get_db().execute("SELECT melo FROM users WHERE id=?", (uid,)).fetchone()
        return row["melo"] if row else 1500
    except Exception:
        return 1500'''

GETTER_REMPLACEMENT = '''def _get_user_melo(uid, random=False):
    """Lit le mélo courant d'un utilisateur en base, DANS LE MODE demandé.

    Sans le mode, la partie suivante d'un match Random repartait du mélo
    standard des deux joueurs — et `_apply_melo` écrivait le résultat dans
    `melo_random`. Le classement Random d'un joueur sautait donc à son niveau
    standard dès la deuxième partie d'un match."""
    _col = "melo_random" if random else "melo"
    try:
        row = get_db().execute(
            "SELECT %s AS m FROM users WHERE id=?" % _col, (uid,)).fetchone()
        if not row or row["m"] is None:
            return 1500
        return row["m"]
    except Exception:
        return 1500'''

APPEL_MOTIF = '''            # Mélos à jour (lus en base pour refléter l'évolution)
            nb_melo = _get_user_melo(new_blanc_uid)
            nn_melo = _get_user_melo(new_noir_uid)'''

APPEL_REMPLACEMENT = '''            # Mélos à jour (lus en base pour refléter l'évolution), dans le
            # mode du match : une Random Fuga continue au classement Random.
            _rnd = bool(game.get("random", False))
            nb_melo = _get_user_melo(new_blanc_uid, _rnd)
            nn_melo = _get_user_melo(new_noir_uid, _rnd)'''


CHANGEMENTS = [
    ("le defi : les deux melos du mode", DEFI_MOTIF, DEFI_REMPLACEMENT),
    ("le defi : ce qu'on envoie a la cible", EMIT_MOTIF, EMIT_REMPLACEMENT),
    ("la correspondance : le cache retient les deux", BULK_MOTIF,
     BULK_REMPLACEMENT),
    ("la correspondance : le mode decide", CORR_MOTIF, CORR_REMPLACEMENT),
    ("la partie suivante : lecture par mode", GETTER_MOTIF,
     GETTER_REMPLACEMENT),
    ("la partie suivante : on passe le mode", APPEL_MOTIF, APPEL_REMPLACEMENT),
]


def main():
    if len(sys.argv) < 2:
        print("usage: python3 patch_melo_mode.py /chemin/vers/server.py")
        return 2
    chemin = sys.argv[1]
    if not os.path.isfile(chemin):
        print("introuvable : %s" % chemin)
        return 2

    source = io.open(chemin, encoding="utf-8").read()
    print("avant : %d lignes, sha256 %s"
          % (source.count("\n") + 1,
             hashlib.sha256(source.encode("utf-8")).hexdigest()))

    # TOUT verifier avant d'ecrire quoi que ce soit.
    for nom, motif, _ in CHANGEMENTS:
        n = source.count(motif)
        if n != 1:
            print("REFUS : « %s » trouve %d fois au lieu d'une." % (nom, n))
            print("        Le fichier n'est pas celui attendu, ou il est deja")
            print("        corrige. Rien n'a ete ecrit.")
            return 1

    sortie = source
    for nom, motif, remplacement in CHANGEMENTS:
        sortie = sortie.replace(motif, remplacement)
        print("  ok  %s" % nom)

    horodatage = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    sauvegarde = "%s.avant-melo-mode-%s" % (chemin, horodatage)
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
