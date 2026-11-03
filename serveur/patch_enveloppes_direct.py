# -*- coding: utf-8 -*-
"""Les enveloppes qui PARTENT se voient en direct, elles aussi.

Nino : « quand mon interlocuteur supprime ou envoie une enveloppe, ca doit
changer de mon cote en temps reel si je suis deja sur la boite. »

L'ENVOI etait deja annonce : _notify_user pose la push ET emet le meme
contenu sur les sockets ouvertes (maj_directe). Il manquait les deux autres
mouvements :

    - le destinataire OUVRE : l'enveloppe disparait, et son expediteur doit
      voir son jeton quitter la boite a l'instant, pas a la minute suivante ;
    - l'un des deux SUPPRIME : l'autre doit le voir de meme.

Ni l'un ni l'autre ne merite de faire sonner un telephone : on emet donc en
direct, sans push — _emit_direct seul, jamais _notify_user.

USAGE
    python3 patch_enveloppes_direct.py /chemin/vers/server.py

A passer APRES patch_enveloppes.py : les trois motifs sont dans le bloc que
celui-la pose. Le script REFUSE d'ecrire si un motif n'est pas trouve
exactement une fois, y compris sur un fichier deja corrige. Une sauvegarde
horodatee est posee a cote avant toute ecriture, et le resultat est compile
avant d'etre ecrit.
"""
import datetime
import hashlib
import io
import os
import shutil
import sys


# ── 1. LE MESSAGER ──────────────────────────────────────────────────────────
MOTIF_HELPER = '''@flask_app.route("/env_envoyer", methods=["POST"])'''

AJOUT_HELPER = '''def _env_previens(user_id, de_pseudo):
    """Previent EN DIRECT, sans push : une enveloppe a bouge chez l'autre.

    L'envoi, lui, passe par _notify_user : une enveloppe qui arrive merite
    qu'on en soit averti meme telephone range. Une ouverture ou une
    suppression, non — elles ne font que mettre la boite a jour chez qui la
    regarde. D'ou _emit_direct seul.
    """
    try:
        _emit_direct(user_id, {"type": "enveloppe", "de": de_pseudo})
    except Exception as e:
        print("[enveloppes] direct :", e)


@flask_app.route("/env_envoyer", methods=["POST"])'''


# ── 2. L'OUVERTURE PAR LE DESTINATAIRE ──────────────────────────────────────
MOTIF_OUVRIR = '''    pour_moi = bool(ligne["destinataire_id"] == me["id"])
    if pour_moi:
        _env_efface(ligne)'''

AJOUT_OUVRIR = '''    pour_moi = bool(ligne["destinataire_id"] == me["id"])
    if pour_moi:
        _env_efface(ligne)
        # L'EXPEDITEUR LA VOIT PARTIR. Son jeton quitte sa boite a l'instant
        # ou on l'ouvre : c'est le seul moyen qu'il sache qu'elle est lue.
        _env_previens(ligne["expediteur_id"], me["pseudo"])'''


# ── 3. LA SUPPRESSION, DES DEUX COTES ───────────────────────────────────────
MOTIF_SUPPRIMER = '''    _env_efface(ligne)
    return jsonify({"ok": True})'''

AJOUT_SUPPRIMER = '''    _env_efface(ligne)
    # L'AUTRE LE VOIT AUSSI, quel que soit celui des deux qui a jete.
    autre_id = (ligne["destinataire_id"]
                if me["id"] == ligne["expediteur_id"]
                else ligne["expediteur_id"])
    _env_previens(autre_id, me["pseudo"])
    return jsonify({"ok": True})'''


CORRECTIONS = [
    ("le messager", MOTIF_HELPER, AJOUT_HELPER),
    ("l'ouverture", MOTIF_OUVRIR, AJOUT_OUVRIR),
    ("la suppression", MOTIF_SUPPRIMER, AJOUT_SUPPRIMER),
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
    sauvegarde = "%s.avant-env-direct-%s" % (chemin, horodatage)
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
