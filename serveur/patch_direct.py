# -*- coding: utf-8 -*-
"""La correspondance previent EN DIRECT, au lieu de se faire redemander.

Jusqu'ici, aucune route de correspondance n'emettait le moindre evenement
Socket.IO. Jouer un coup, proposer une nulle, abandonner, accepter un defi,
ecrire dans le chat d'une partie : tout cela envoyait une notification push,
et RIEN a l'application ouverte. Celle-ci ne pouvait donc qu'une chose,
redemander la liste des parties toutes les quatre secondes.

Un seul point d'insertion suffit. Chaque mutation appelle deja _notify_user
avec un dictionnaire qui porte son type et son game_id — exactement ce qu'il
faut au client :

    corr_turn | corr_fin | corr_nulle | corr_chat | defi_corr | message

On previent donc en direct au MEME endroit, sous l'evenement « maj_directe »,
avec la meme charge utile. Les deux chemins disent desormais la meme chose, et
toute notification ajoutee plus tard sera temps reel sans y penser.

L'emission est placee AVANT le filtre des preferences, et c'est voulu : les
preferences disent ce qu'on veut recevoir sur son telephone quand
l'application est fermee. Ici elle est ouverte et affiche la partie — elle
doit se mettre a jour meme si les push sont coupees.

N'enleve rien : les notifications push partent comme avant, et les clients qui
ignorent « maj_directe » ne voient aucune difference.

USAGE
    python3 patch_direct.py /chemin/vers/server.py

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

MOTIF_NOTIFY = '''def _notify_user(user_id, kind, title, body, data=None):
    """Envoie une push à un utilisateur SELON SES PRÉFÉRENCES, EN TÂCHE DE FOND.
    kind = 'turn' | 'msg' | 'defi_corr' | 'defi_direct'.

    L'appel revient immédiatement : le joueur qui joue un coup n'attend plus
    l'aller-retour HTTPS vers Firebase. Comportement fonctionnel identique, la
    notification part juste sans faire patienter la requête."""
    try:'''

REMPLACEMENT_NOTIFY = '''def _emit_direct(user_id, data):
    """Previent EN DIRECT les sockets ouvertes d'un joueur.

    La correspondance n'avait aucun evenement temps reel : seules des
    notifications push sortaient du serveur, et l'application ouverte ne
    pouvait que redemander la liste toutes les quatre secondes. Elle est
    maintenant prevenue a l'instant ou quelque chose bouge.

    Rien a voir avec les preferences de notification, et c'est pour cela que
    l'emission n'est pas dans _notify_user_sync, qui les filtre : ces
    preferences disent ce qu'on veut recevoir SUR SON TELEPHONE quand
    l'application est fermee. Ici elle est ouverte et affiche la partie — elle
    doit se mettre a jour meme si les push sont coupees.

    Un meme joueur peut avoir plusieurs sockets, telephone et tablette : on
    les previent toutes.
    """
    if not data:
        return
    try:
        for _s, _info in list(CONNECTED.items()):
            if _info.get("user_id") == user_id:
                sio.emit("maj_directe", data, to=_s)
    except Exception as e:
        print("[direct] erreur :", e)


def _notify_user(user_id, kind, title, body, data=None):
    """Envoie une push à un utilisateur SELON SES PRÉFÉRENCES, EN TÂCHE DE FOND,
    et le previent EN DIRECT si son application est ouverte.
    kind = 'turn' | 'msg' | 'defi_corr' | 'defi_direct'.

    L'appel revient immédiatement : le joueur qui joue un coup n'attend plus
    l'aller-retour HTTPS vers Firebase. Comportement fonctionnel identique, la
    notification part juste sans faire patienter la requête."""
    # Le direct d'abord, et sans condition : il ne coute qu'un emit sur une
    # socket deja ouverte, la ou la push part dans un greenlet et un
    # aller-retour vers Firebase.
    _emit_direct(user_id, data)
    try:'''


# 2. L'acceptation d'un defi ne prevenait QUE le joueur des Blancs, et
#    seulement si ce n'etait pas celui qui venait d'accepter. Le defieur
#    n'apprenait donc jamais que sa partie avait demarre : pour la push c'est
#    voulu — « a vous de jouer » serait faux s'il a les Noirs — mais son ecran
#    doit quand meme se mettre a jour. On le previent en direct, sans push.
MOTIF_DEFI = '''    if accepte:
        try:
            blanc_uid = row["blanc_user_id"]
            if blanc_uid and blanc_uid != me["id"]:
                _notify_user(blanc_uid, "turn", me["pseudo"],
                             "a accepté votre défi, à vous de jouer !",
                             {"type": "corr_turn", "game_id": str(gid)})
        except Exception:
            pass
    return jsonify({"ok": True})'''

REMPLACEMENT_DEFI = '''    if accepte:
        try:
            blanc_uid = row["blanc_user_id"]
            if blanc_uid and blanc_uid != me["id"]:
                _notify_user(blanc_uid, "turn", me["pseudo"],
                             "a accepté votre défi, à vous de jouer !",
                             {"type": "corr_turn", "game_id": str(gid)})
            # Et le defieur, en direct seulement : sa liste doit montrer la
            # partie commencee, meme quand il a les Noirs et n'a donc aucune
            # notification a recevoir.
            _emit_direct(row["defieur_user_id"],
                         {"type": "corr_maj", "game_id": str(gid)})
        except Exception:
            pass
    return jsonify({"ok": True})'''

CORRECTIONS = [
    ("le direct au meme endroit que la push", MOTIF_NOTIFY, REMPLACEMENT_NOTIFY),
    ("le defieur apprend que son defi est accepte", MOTIF_DEFI,
     REMPLACEMENT_DEFI),
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

    problemes = []
    for titre, motif, _ in CORRECTIONS:
        n = source.count(motif)
        if n != 1:
            problemes.append("  - %s : motif trouve %d fois (attendu 1)"
                             % (titre, n))
    if problemes:
        print("Rien n'a ete modifie. Motifs non conformes :")
        print("\n".join(problemes))
        if "_emit_direct" in source:
            print("\nLe fichier est DEJA corrige : rien a faire.")
        else:
            print("\nAppliquez d'abord patch_notifs.py et patch_nulle.py.")
        return 1

    resultat = source
    for _, motif, remplacement in CORRECTIONS:
        resultat = resultat.replace(motif, remplacement, 1)

    # Garde-fous.
    # 1. La definition, et DEUX appels : celui de _notify_user, et celui de
    #    l'acceptation d'un defi. Un de plus voudrait dire qu'un emit traine
    #    ailleurs et que ce fichier n'est pas celui qu'on croit.
    appels = resultat.count("_emit_direct(") - resultat.count("def _emit_direct(")
    if appels != 2:
        print("Attendu 2 appels a _emit_direct, trouve %d : rien n'a ete "
              "ecrit." % appels)
        return 1
    # 2. L'emission doit etre AVANT le filtre des preferences, sinon couper
    #    ses notifications couperait aussi le direct.
    if resultat.index("_emit_direct(user_id, data)") > resultat.index(
            "def _notify_user_sync("):
        print("L'emission tombe apres le filtre des preferences : rien n'a "
              "ete ecrit.")
        return 1
    # 3. Les notifications d'avant sont toutes encore la.
    notifs = (resultat.count("_notify_user(")
              - resultat.count("def _notify_user("))
    if notifs != 9:
        print("Attendu 9 appels a _notify_user, trouve %d : rien n'a ete "
              "ecrit." % notifs)
        return 1

    try:
        compile(resultat, chemin, "exec")
    except SyntaxError as e:
        print("Le resultat ne compile pas (%s). Rien n'a ete ecrit." % e)
        return 1

    horodatage = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    sauvegarde = "%s.avant-direct-%s" % (chemin, horodatage)
    shutil.copy2(chemin, sauvegarde)
    with io.open(chemin, "w", encoding="utf-8") as f:
        f.write(resultat)

    empreinte = hashlib.sha256(resultat.encode("utf-8")).hexdigest()
    print("Sauvegarde : %s" % sauvegarde)
    print("%d corrections appliquees." % len(CORRECTIONS))
    print("sha256 du fichier corrige : %s" % empreinte)
    print("\nRedemarrez le service :  sudo systemctl restart lafuga")
    return 0


if __name__ == "__main__":
    sys.exit(main())
