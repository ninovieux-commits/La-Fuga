# -*- coding: utf-8 -*-
"""Les parties de correspondance EN COURS d'un joueur, sur son profil.

Nino : « le "parties" vers le milieu affiche les parties par correspondance en
cours de la personne. Les plateaux d'apercus doivent faire la meme taille que
ceux du menu, et donner sur la partie de la personne en mode visiteur. »

`/corr_list` ne rend que les MIENNES : le serveur n'y lit que le jeton, il n'y
a aucun moyen de demander celles de quelqu'un d'autre. Le profil d'un tiers
affichait donc toujours « pas de partie en cours ».

CE QUI CHANGE
    - une route de plus : /corr_list_public {token, pseudo}

Elle est en LECTURE SEULE et ne montre que ce qu'on verrait en regardant la
personne jouer : la position, les deux noms, le score entre eux, a qui le
trait. Le dictionnaire est bati du point de vue du JOUEUR REGARDE — ses pieces
en bas, son adversaire en face — exactement comme son propre apercu.

CE QU'ELLE NE MONTRE PAS. `_corr_game_dict` porte aussi des choses qui ne
regardent que le joueur : ses pre-coups, ses messages non lus, les nulles en
attente. La route ne les retire pas une par une — elle ne recopie QUE les cles
d'une liste blanche. Une cle privee ajoutee plus tard au dictionnaire ne peut
donc pas fuir toute seule.

UN BLOCAGE FERME LA PORTE. Si l'un des deux a bloque l'autre, la liste revient
vide : on ne regarde pas jouer quelqu'un qui ne veut pas de nous, et
reciproquement. C'est la meme regle que pour les defis (`_is_blocked_pair`).

N'ENLEVE RIEN, NE TOUCHE A RIEN. `/corr_list` n'est pas modifiee, aucune table
n'est ecrite, aucune colonne ajoutee. Une application plus ancienne ne connait
pas la route et ne l'appelle jamais.

USAGE
    python3 patch_profil_parties.py /chemin/vers/server.py

Le script REFUSE d'ecrire si le motif n'est pas trouve exactement une fois, y
compris sur un fichier deja corrige. Une sauvegarde horodatee est posee a cote
avant toute ecriture.
"""
import datetime
import hashlib
import io
import os
import shutil
import sys


MOTIF = '''    cache = _corr_bulk(rows, me["id"])
    games = [_corr_game_dict(r, me["id"], cache) for r in rows]
    return jsonify({"ok": True, "games": games})


@flask_app.route("/corr_close", methods=["POST"])'''

REMPLACEMENT = '''    cache = _corr_bulk(rows, me["id"])
    games = [_corr_game_dict(r, me["id"], cache) for r in rows]
    return jsonify({"ok": True, "games": games})


# Ce qu'un VISITEUR voit d'une partie de correspondance : la position, les deux
# noms, le score entre eux, a qui le trait. C'est une liste BLANCHE, et non une
# liste de cles a retirer : `_corr_game_dict` porte aussi les pre-coups du
# joueur, ses messages non lus et les nulles en attente, et une cle privee
# ajoutee plus tard ne doit pas se retrouver dehors par oubli.
_CORR_PUBLIC_KEYS = (
    "id", "statut", "ma_couleur", "adversaire", "adversaire_melo",
    "mon_score", "score_adverse", "objectif", "turn", "moves_text",
    "my_turn", "resultat", "methode", "gagne", "random_code",
    "mode", "position", "couleur", "updated_at",
)


@flask_app.route("/corr_list_public", methods=["POST"])
def corr_list_public():
    """Parties de correspondance EN COURS d'un joueur, vues par un visiteur.

    Le profil d'un tiers les montre en apercu. On ne rend que les parties en
    cours : un defi pas encore accepte ne se montre pas (il n'est pas une
    partie), et une partie terminee appartient a l'historique."""
    data = request.get_json(silent=True) or {}
    me = user_from_token(data.get("token", ""))
    if not me:
        return jsonify({"ok": False, "error": "Token invalide"}), 401
    pseudo = (data.get("pseudo") or "").strip()
    if not pseudo:
        return jsonify({"ok": True, "games": []})
    row = get_db().execute(
        "SELECT * FROM users WHERE pseudo_lower = ?", (pseudo.lower(),)
    ).fetchone()
    if not row:
        return jsonify({"ok": False, "error": "Joueur introuvable"}), 404
    lui = dict(row)
    # Un blocage, d'un cote ou de l'autre, ferme la porte — comme pour un defi.
    if lui["id"] != me["id"] and _is_blocked_pair(me["id"], lui["id"]):
        return jsonify({"ok": True, "games": []})

    conn = get_db()
    try:
        rows = conn.execute(
            "SELECT * FROM corr_games WHERE statut = 'en_cours' "
            "AND (blanc_user_id=? OR noir_user_id=?) "
            "ORDER BY updated_at DESC",
            (lui["id"], lui["id"])).fetchall()
    finally:
        conn.close()

    # Du point de vue du joueur REGARDE : ses pieces en bas, son adversaire en
    # face. Le meme prechargement qu'ailleurs, donc trois requetes en tout.
    cache = _corr_bulk(rows, lui["id"])
    games = []
    for r in rows:
        complet = _corr_game_dict(r, lui["id"], cache)
        games.append({k: complet[k] for k in _CORR_PUBLIC_KEYS
                      if k in complet})
    return jsonify({"ok": True, "games": games})


@flask_app.route("/corr_close", methods=["POST"])'''


CORRECTIONS = [
    ("/corr_list_public : les parties en cours d'un autre joueur",
     MOTIF, REMPLACEMENT),
]


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    chemin = sys.argv[1]
    if not os.path.isfile(chemin):
        print("Fichier introuvable : %s" % chemin)
        return 1
    with io.open(chemin, encoding="utf-8") as f:
        source = f.read()

    for nom, motif, _ in CORRECTIONS:
        n = source.count(motif)
        if n != 1:
            print("REFUS : le motif « %s » apparait %d fois (attendu : 1)."
                  % (nom, n))
            print("Le fichier n'a PAS ete modifie.")
            print("Un fichier deja corrige donne 0 : il n'y a rien a refaire.")
            return 1

    corrige = source
    for _, motif, remplacement in CORRECTIONS:
        corrige = corrige.replace(motif, remplacement)

    horodatage = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    sauvegarde = "%s.avant-parties-%s" % (chemin, horodatage)
    shutil.copy2(chemin, sauvegarde)
    with io.open(chemin, "w", encoding="utf-8") as f:
        f.write(corrige)

    print("Sauvegarde : %s" % sauvegarde)
    print("%d correction appliquee." % len(CORRECTIONS))
    print("sha256 du fichier corrige : %s"
          % hashlib.sha256(corrige.encode("utf-8")).hexdigest())
    print("")
    print("Redemarrez le service :  sudo systemctl restart lafuga")
    return 0


if __name__ == "__main__":
    sys.exit(main())
