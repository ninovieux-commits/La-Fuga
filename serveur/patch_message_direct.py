# -*- coding: utf-8 -*-
"""Un message part vers TOUTES les sockets du destinataire, pas une seule.

Nino : « les messages non plus n'apparaissent pas en temps reel quand on est
deja sur la boite ? »

/send_message emet bien « message_recu », mais a UNE socket :

    sid = _find_sid_by_pseudo(row["pseudo"])
    if sid:
        sio.emit("message_recu", ..., to=sid)

`_find_sid_by_pseudo` rend la premiere socket trouvee sous ce pseudo. Un
joueur qui s'est reconnecte — Wi-Fi vers 4G, ecran eteint puis rallume, serveur
redemarre — en a parfois une autre, et l'ancienne reste dans la table : le
message part alors dans le vide. L'application ne le voit plus qu'a sa
relecture de securite, trente secondes plus tard, puisqu'elle espace ses
relectures tant que la socket repond.

On fait donc ici ce que _emit_direct fait deja pour la correspondance : on
prend TOUTES les sockets du destinataire, par son identifiant, et on les sert
toutes. Un telephone et une tablette ouverts recoivent les deux ; une socket
morte ne coute qu'un emit perdu.

RIEN D'AUTRE NE CHANGE : meme evenement, meme contenu, meme push derriere.
L'application n'a rien a apprendre, elle ecoute deja « message_recu ».

USAGE
    python3 patch_message_direct.py /chemin/vers/server.py

Le script REFUSE d'ecrire si le motif n'est pas trouve exactement une fois, y
compris sur un fichier deja corrige. Une sauvegarde horodatee est posee a cote
avant toute ecriture, et le resultat est compile avant d'etre ecrit.
"""
import datetime
import hashlib
import io
import os
import shutil
import sys


MOTIF = '''    sid = _find_sid_by_pseudo(row["pseudo"])
    if sid:
        sio.emit("message_recu", {"de": me["pseudo"], "texte": text,
                                  "created_at": now}, to=sid)'''

AJOUT = '''    # TOUTES SES SOCKETS, ET NON LA PREMIERE TROUVEE.
    #
    # `_find_sid_by_pseudo` n'en rend qu'une. Un joueur reconnecte en a
    # parfois une autre, l'ancienne restant dans la table : le message partait
    # dans le vide, et la boite ouverte ne le voyait qu'a sa relecture de
    # securite — trente secondes. C'est ce que fait deja _emit_direct pour la
    # correspondance, et c'est pour cela que les enveloppes, elles,
    # arrivaient bien.
    _message = {"de": me["pseudo"], "texte": text, "created_at": now}
    try:
        for _s, _info in list(CONNECTED.items()):
            if _info.get("user_id") == row["id"]:
                sio.emit("message_recu", _message, to=_s)
    except Exception as e:
        print("[message] direct :", e)'''


CORRECTIONS = [("le direct des messages", MOTIF, AJOUT)]


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
    sauvegarde = "%s.avant-msg-direct-%s" % (chemin, horodatage)
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
