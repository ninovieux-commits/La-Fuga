# -*- coding: utf-8 -*-
"""Une boite de discussion garde ses 200 derniers messages.

Nino : « une fois qu'une boite contient 200 messages, les plus anciens doivent
etre effaces ».

C'est une suppression, pas un affichage : elle se fait donc ici, la ou les
messages vivent. Les effacer cote application ne ferait que les cacher — ils
reviendraient a la lecture suivante — et la base continuerait de grossir sans
fin.

CE QUI CHANGE
    - une constante PLAFOND_MESSAGES = 200
    - `_plafonner_boite(conn, a, b)` : efface les plus anciens au-dela
    - /send_message l'appelle juste apres avoir inscrit le message

LA BOITE, C'EST LA PAIRE. Les deux sens comptent : une boite contient ce que
chacun a ecrit. Le plafond ne s'applique donc pas « par expediteur » mais a la
conversation entiere, comme on la lit a l'ecran.

LE COMPTE DES NON-LUS SUIT. Un message efface n'est plus a lire : la pastille
retombe d'autant, ce qui est juste — on ne peut pas reclamer la lecture d'un
message qui n'existe plus.

RIEN A CHANGER DANS L'APPLICATION. Elle demande la conversation entiere et
recoit au plus 200 messages.

USAGE
    python3 patch_plafond_messages.py /chemin/vers/server.py

Le script REFUSE d'ecrire si un motif n'est pas trouve exactement une fois, y
compris sur un fichier deja corrige. Une sauvegarde horodatee est posee a cote
avant toute ecriture.
"""
import datetime
import hashlib
import io
import os
import shutil
import sys


MOTIF_HELPER = '''@flask_app.route("/send_message", methods=["POST"])'''

REMPLACEMENT_HELPER = '''# Combien de messages une boite de discussion garde au plus.
#
# Nino : « une fois qu'une boite contient 200 messages, les plus anciens
# doivent etre effaces ». Deux cents, c'est assez pour retrouver une
# conversation de la veille et assez peu pour qu'une boite ne pese jamais
# lourd : a mille caracteres par message, 200 Ko dans le pire des cas.
PLAFOND_MESSAGES = 200


def _plafonner_boite(conn, a, b):
    """Efface les plus anciens messages echanges entre `a` et `b`.

    La boite, c'est la PAIRE : les deux sens comptent, comme a l'ecran. On
    garde les PLAFOND_MESSAGES plus recents et on efface le reste.

    `LIMIT -1 OFFSET n` est la facon SQLite de dire « tout sauf les n
    premiers » : la sous-requete rend donc exactement les messages de trop,
    du plus recent au plus ancien.
    """
    conn.execute(
        "DELETE FROM messages WHERE id IN ("
        "  SELECT id FROM messages"
        "   WHERE (from_user_id = ? AND to_user_id = ?)"
        "      OR (from_user_id = ? AND to_user_id = ?)"
        "   ORDER BY created_at DESC, id DESC"
        "   LIMIT -1 OFFSET ?)",
        (a, b, b, a, PLAFOND_MESSAGES))


@flask_app.route("/send_message", methods=["POST"])'''


MOTIF_APPEL = '''    conn.execute("INSERT INTO messages (from_user_id, to_user_id, text, created_at) "
                 "VALUES (?, ?, ?, ?)", (me["id"], row["id"], text, now))
    conn.commit()
    conn.close()'''

REMPLACEMENT_APPEL = '''    conn.execute("INSERT INTO messages (from_user_id, to_user_id, text, created_at) "
                 "VALUES (?, ?, ?, ?)", (me["id"], row["id"], text, now))
    # La boite ne depasse jamais son plafond : le message de trop en chasse un
    # ancien, dans la meme transaction que l'ecriture.
    _plafonner_boite(conn, me["id"], row["id"])
    conn.commit()
    conn.close()'''


CORRECTIONS = [
    ("le plafond et son aide", MOTIF_HELPER, REMPLACEMENT_HELPER),
    ("/send_message plafonne la boite", MOTIF_APPEL, REMPLACEMENT_APPEL),
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
    sauvegarde = "%s.avant-plafond-%s" % (chemin, horodatage)
    shutil.copy2(chemin, sauvegarde)
    with io.open(chemin, "w", encoding="utf-8") as f:
        f.write(corrige)

    print("Sauvegarde : %s" % sauvegarde)
    print("%d corrections appliquees." % len(CORRECTIONS))
    print("sha256 du fichier corrige : %s"
          % hashlib.sha256(corrige.encode("utf-8")).hexdigest())
    print("")
    print("Redemarrez le service :  sudo systemctl restart lafuga")
    return 0


if __name__ == "__main__":
    sys.exit(main())
