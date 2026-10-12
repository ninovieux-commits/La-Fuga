# -*- coding: utf-8 -*-
"""La notification de correspondance annonce LE COUP joué.

Avant : « Nino a joué, à vous de jouer ! »
Apres : « Nino a joué 3.Re2-Re3 »   (Blancs)
        « Nino a joué Do8-Do7 »     (Noirs)

Le .nmc groupe les coups par tour — « 3.Re2-Re3/Do8-Do7 ». On n'envoie que la
moitie qui vient d'etre jouee : ce qui PRECEDE la barre pour les Blancs, ce qui
la SUIT pour les Noirs. Le numero de tour fait partie de la premiere moitie,
comme dans le fichier.

Sans notation (cas qui ne devrait pas arriver), l'ancien texte est conserve :
mieux vaut une phrase complete qu'une phrase qui s'arrete.

USAGE
    python3 patch_notif_coup.py /chemin/vers/server.py

Le script REFUSE d'ecrire si un seul des motifs n'est pas trouve exactement
une fois, y compris sur un fichier deja corrige. Une sauvegarde horodatee est
posee a cote avant toute ecriture.
"""
import datetime
import hashlib
import io
import os
import shutil
import sys

CORRECTIONS = [
    (
        "la fonction qui met le coup au format du .nmc",
        '''@flask_app.route("/corr_jouer", methods=["POST"])''',
        '''def _coup_pour_notif(notation, my_color, nb_coups):
    """Le coup au format du .nmc, pour la notification de l'adversaire.

    Le fichier groupe les coups par tour : « 3.Re2-Re3/Do8-Do7 ». La
    notification n'annonce que la moitie qui vient d'etre jouee — ce qui
    precede la barre pour les Blancs (numero de tour compris), ce qui la suit
    pour les Noirs.

    [nb_coups] est le nombre total de demi-coups APRES celui-ci.
    """
    numero = (nb_coups + 1) // 2
    if my_color == "Blanc":
        return "%d.%s" % (numero, notation)
    return notation


@flask_app.route("/corr_jouer", methods=["POST"])''',
    ),
    (
        "le texte de la notification",
        '''        # Notification push à l'adversaire : c'est son tour.
        try:
            _notify_user(opp_uid, "turn", "La Fuga",
                         me["pseudo"] + " a joué, à vous de jouer !",
                         {"type": "corr_turn", "game_id": str(gid)})
        except Exception:
            pass''',
        '''        # Notification push à l'adversaire : QUEL coup vient d'etre joue.
        # « a joué, à vous de jouer » ne disait rien de la partie : il fallait
        # ouvrir l'application pour savoir ce qui s'etait passe.
        try:
            _nb = len([c for c in (new_moves or "").split("\\n") if c.strip()])
            _corps = (
                "%s a joué %s" % (me["pseudo"],
                                  _coup_pour_notif(notation, my_color, _nb))
                if notation else me["pseudo"] + " a joué, à vous de jouer !"
            )
            _notify_user(opp_uid, "turn", "La Fuga", _corps,
                         {"type": "corr_turn", "game_id": str(gid),
                          "coup": notation})
        except Exception:
            pass''',
    ),
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
        print("\nSi le fichier est DEJA corrige, c'est normal : rien a faire.")
        return 1

    resultat = source
    for _, motif, remplacement in CORRECTIONS:
        resultat = resultat.replace(motif, remplacement, 1)

    try:
        compile(resultat, chemin, "exec")
    except SyntaxError as e:
        print("Le resultat ne compile pas (%s). Rien n'a ete ecrit." % e)
        return 1

    horodatage = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    sauvegarde = "%s.avant-notif-%s" % (chemin, horodatage)
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
