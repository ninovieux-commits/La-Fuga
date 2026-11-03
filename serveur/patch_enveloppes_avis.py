# -*- coding: utf-8 -*-
"""« a envoye une enveloppe » : la trace dans le fil de la conversation.

Nino : « quand quelqu'un envoie une enveloppe, il doit y avoir ecrit "a
envoye une enveloppe" en dessous de la derniere bulle (suivant le fil de la
discussion). Ce ne doit pas etre dans une bulle. »

L'application sait deja le dessiner : elle lit le jeton « [enveloppe] » dans
la conversation et le remplace par un petit cadre, hors bulle, a la couleur 2
de celui qui envoie. Il manquait que le serveur le DEPOSE.

Il est pose comme un message ordinaire — meme table, meme horodatage, meme
plafond, par les memes deux lignes que /send_message. Trois raisons :

    - il se range tout seul a sa place dans le fil, entre les deux bulles
      qui l'encadrent, sans qu'on ait a trier quoi que ce soit ;
    - il SURVIT a l'enveloppe : celle-ci s'efface a l'ouverture, la trace de
      l'envoi demeure, comme demeure un message ;
    - il part avec la conversation quand le plafond chasse les anciens.

Aucune notification de plus : la push de l'envoi existe deja, et ces deux
lignes n'en declenchent aucune.

USAGE
    python3 patch_enveloppes_avis.py /chemin/vers/server.py

A passer APRES patch_enveloppes.py. Le script REFUSE d'ecrire si un motif
n'est pas trouve exactement une fois, y compris sur un fichier deja corrige.
Une sauvegarde horodatee est posee a cote avant toute ecriture, et le
resultat est compile avant d'etre ecrit.
"""
import datetime
import hashlib
import io
import os
import shutil
import sys


# ── 1. LE JETON, nomme une fois ─────────────────────────────────────────────
MOTIF_JETON = '''# Periode du menage des enveloppes expirees.'''

AJOUT_JETON = '''# LE JETON DE LA TRACE, celui que l'application reconnait pour ecrire « a
# envoye une enveloppe » hors d'une bulle. Entre crochets comme les jetons
# d'images : une version qui ne le connait pas affiche le mot, pas une bulle
# vide.
ENV_JETON = "[enveloppe]"

# Periode du menage des enveloppes expirees.'''


# ── 2. LA TRACE, posee a l'envoi ────────────────────────────────────────────
#
# L'ancre PORTE LA LIGNE DE L'INSERT au-dessus, et ce n'est pas du zele :
# « gid = cur.lastrowid » suivi d'un commit et d'un close se trouve deux fois
# dans le serveur. Le script a refuse d'ecrire, comme il doit.
MOTIF_TRACE = '''        (me["id"], autre["id"], nom, len(octets), maintenant, expire))
    gid = cur.lastrowid
    conn.commit()
    conn.close()'''

AJOUT_TRACE = '''        (me["id"], autre["id"], nom, len(octets), maintenant, expire))
    gid = cur.lastrowid
    # LA TRACE DANS LE FIL, comme un message ordinaire : memes colonnes, meme
    # horodatage, meme plafond que /send_message. Dans la meme transaction que
    # l'enveloppe — l'une sans l'autre n'aurait pas de sens.
    conn.execute("INSERT INTO messages (from_user_id, to_user_id, text, "
                 "created_at) VALUES (?, ?, ?, ?)",
                 (me["id"], autre["id"], ENV_JETON, maintenant))
    _plafonner_boite(conn, me["id"], autre["id"])
    conn.commit()
    conn.close()'''


CORRECTIONS = [
    ("le jeton", MOTIF_JETON, AJOUT_JETON),
    ("la trace", MOTIF_TRACE, AJOUT_TRACE),
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

    try:
        compile(corrige, chemin, "exec")
    except SyntaxError as e:
        print("REFUS : le resultat ne compile pas (%s)." % e)
        print("Le fichier n'a PAS ete modifie.")
        return 1

    horodatage = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    sauvegarde = "%s.avant-env-avis-%s" % (chemin, horodatage)
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
