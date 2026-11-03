# -*- coding: utf-8 -*-
"""« On ne se defie pas soi-meme » se verifie par COMPTE, pas par socket.

La garde comparait deux identifiants de socket :

    if cible_sid == sid:
        sio.emit("defi_echec", {"raison": "soi_meme"}, to=sid)

Deux appareils ouverts sur le meme compte ont deux sockets differentes : la
comparaison etait donc fausse, et l'on pouvait se defier soi-meme d'un
appareil a l'autre. La partie qui en naissait aurait eu le meme joueur des
deux cotes — meme melo, meme historique, deux fois.

L'application ne le propose pas : on ne se trouve pas dans sa propre
recherche. Mais une garde qui ne garde rien vaut mieux reecrite que laissee
en place, et celle-ci se repare d'une ligne.

On en profite pour remonter `cible_info` AVANT la garde : c'est lui qui porte
le compte, et il etait lu juste apres.

USAGE
    python3 patch_defi_soi_meme.py /chemin/vers/server.py

Le script REFUSE d'ecrire si le motif n'est pas trouve exactement une fois, y
compris sur un fichier deja corrige. Une sauvegarde horodatee est posee a
cote avant toute ecriture, et le resultat est compile avant d'etre ecrit.
"""
import datetime
import hashlib
import io
import os
import shutil
import sys


MOTIF = '''        if cible_sid == sid:
            sio.emit("defi_echec", {"raison": "soi_meme"}, to=sid)
            return
        cible_info = CONNECTED.get(cible_sid)'''

AJOUT = '''        cible_info = CONNECTED.get(cible_sid)
        # SOI-MEME SE COMPTE PAR COMPTE, ET NON PAR SOCKET. Deux appareils
        # ouverts sur le meme compte ont deux sockets differentes : la garde
        # d'avant les laissait se defier l'un l'autre, et la partie qui en
        # serait nee aurait eu le meme joueur des deux cotes.
        if not cible_info or cible_info["user_id"] == info["user_id"]:
            sio.emit("defi_echec", {"raison": "soi_meme"}, to=sid)
            return'''


CORRECTIONS = [("la garde du defi de soi-meme", MOTIF, AJOUT)]


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

    try:
        compile(corrige, chemin, "exec")
    except SyntaxError as e:
        print("REFUS : le resultat ne compile pas (%s)." % e)
        print("Le fichier n'a PAS ete modifie.")
        return 1

    horodatage = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    sauvegarde = "%s.avant-defi-soi-%s" % (chemin, horodatage)
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
