# -*- coding: utf-8 -*-
"""Le profil d'un joueur dit s'il est dans MES favoris, et si je l'ai bloque.

L'application posait deja la question : elle lit `is_favorite` et `is_blocked`
dans la reponse de `/get_profile`. Le serveur ne les a JAMAIS renvoyees. La
touche « Favori » ne devenait donc jamais « Retirer », et « Bloquer » jamais
« Debloquer » : les deux lisaient une cle absente, c'est-a-dire toujours faux.

Nino : « le bouton favori doit devenir retirer quand le joueur est favori […]
il doit y avoir une etoile dans les infos de joueur s'il est favori ».

CE QUI CHANGE
    - /get_profile rend `is_favorite` et `is_blocked` quand ce n'est pas moi

`is_favorite` : je l'ai mis dans MES favoris. La relation n'est pas
reciproque — qu'il m'ait ou non dans les siens ne me regarde pas.

`is_blocked` : c'est MOI qui l'ai bloque. Un blocage est bilateral dans ses
EFFETS (voir `_is_blocked_pair`), mais seul celui que j'ai pose se debloque
depuis mon ecran ; afficher « Debloquer » pour un blocage que l'autre a pose
promettrait une action impossible.

Sur MON propre profil, les deux cles sont absentes : se mettre en favori ou se
bloquer soi-meme n'a pas de sens, et l'ecran ne propose deja pas ces touches.

N'ENLEVE RIEN. Une application plus ancienne ignore les deux cles.

USAGE
    python3 patch_profil_favori.py /chemin/vers/server.py

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


MOTIF = '''    if not is_self:
        # Scores head-to-head entre moi et lui (direct + correspondance).
        _d = _get_direct_score(me["id"], u["id"])
        _c = _get_corr_score(me["id"], u["id"])
        out["h2h_direct_moi"] = _d[me["id"]]
        out["h2h_direct_lui"] = _d[u["id"]]
        out["h2h_corr_moi"] = _c[me["id"]]
        out["h2h_corr_lui"] = _c[u["id"]]'''

REMPLACEMENT = '''    if not is_self:
        # Scores head-to-head entre moi et lui (direct + correspondance).
        _d = _get_direct_score(me["id"], u["id"])
        _c = _get_corr_score(me["id"], u["id"])
        out["h2h_direct_moi"] = _d[me["id"]]
        out["h2h_direct_lui"] = _d[u["id"]]
        out["h2h_corr_moi"] = _c[me["id"]]
        out["h2h_corr_lui"] = _c[u["id"]]
        # Est-il dans MES favoris, l'ai-je bloque ? L'application lisait deja
        # ces deux cles ; elles n'avaient jamais ete envoyees, donc « Favori »
        # ne devenait jamais « Retirer » et « Bloquer » jamais « Debloquer ».
        #
        # Les deux relations sont a SENS UNIQUE, du point de vue de celui qui
        # regarde : ses favoris a lui ne me regardent pas, et seul le blocage
        # que j'ai pose se defait depuis mon ecran.
        _db = get_db()
        out["is_favorite"] = _db.execute(
            "SELECT 1 FROM favorites WHERE user_id=? AND fav_user_id=? LIMIT 1",
            (me["id"], u["id"])).fetchone() is not None
        out["is_blocked"] = _db.execute(
            "SELECT 1 FROM blocked WHERE user_id=? AND blocked_user_id=? "
            "LIMIT 1", (me["id"], u["id"])).fetchone() is not None'''


CORRECTIONS = [
    ("/get_profile rend is_favorite et is_blocked", MOTIF, REMPLACEMENT),
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
    sauvegarde = "%s.avant-favori-%s" % (chemin, horodatage)
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
