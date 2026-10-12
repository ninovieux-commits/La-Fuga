# -*- coding: utf-8 -*-
"""Les notifications disent QUI en titre, et le reste en corps.

AVANT                               APRES
  La Fuga                             mesange
  mesange a joue 6.Sol1-Sol2>Fa3      a joue 6.Sol1-Sol2>Fa3

Android ecrit deja « La Fuga » au-dessus du groupe, avec l'icone : le
repeter en titre volait la seule ligne qui pouvait dire QUI, et le pseudo se
retrouvait noye au debut du corps. Les notifications de message faisaient
DEJA comme ca (titre = pseudo) ; les quatre autres ne suivaient pas.

Quatre corrections :

  1. defi de correspondance   « X vous defie... »  -> titre X, corps « vous defie... »
  2. defi accepte             « X a accepte... »   -> titre X, corps « a accepte... »
  3. coup joue                « X a joue Y »       -> titre X, corps « a joue Y »
  4. coup FINAL               rien du tout         -> titre X, corps « a joue Y — partie terminee »

Le 4 est nouveau : la branche qui clot la partie ne notifiait personne. Quand
l'adversaire jouait le coup final, on ne recevait rien, et la partie se
terminait sans qu'on le sache. Le destinataire est l'ADVERSAIRE de celui qui
vient de jouer, pas le perdant : un coup peut faire gagner l'autre camp.

Le format du coup reste celui du .nmc : ce qui precede la barre pour les
Blancs (numero de tour compris), ce qui la suit pour les Noirs.

NE COUVRE PAS l'abandon ni la nulle acceptee, qui passent par d'autres routes
et ne notifient rien non plus.

USAGE
    python3 patch_notifs.py /chemin/vers/server.py

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
        "1. defi de correspondance : titre = pseudo",
        '''    # Notification push à la personne défiée.
    try:
        _notify_user(cible["id"], "defi_corr", "La Fuga",
                     me["pseudo"] + " vous défie en correspondance !",
                     {"type": "defi_corr", "game_id": str(gid)})''',
        '''    # Notification push à la personne défiée. Le titre est le pseudo de
    # l'expediteur : Android ecrit deja « La Fuga » au-dessus, le repeter en
    # titre volait la seule ligne qui pouvait dire QUI.
    try:
        _notify_user(cible["id"], "defi_corr", me["pseudo"],
                     "vous défie en correspondance !",
                     {"type": "defi_corr", "game_id": str(gid)})''',
    ),
    (
        "2. defi accepte : titre = pseudo",
        '''                _notify_user(blanc_uid, "turn", "La Fuga",
                             me["pseudo"] + " a accepté votre défi, à vous de jouer !",
                             {"type": "corr_turn", "game_id": str(gid)})''',
        '''                _notify_user(blanc_uid, "turn", me["pseudo"],
                             "a accepté votre défi, à vous de jouer !",
                             {"type": "corr_turn", "game_id": str(gid)})''',
    ),
    (
        "3. coup joue : titre = pseudo",
        '''            _nb = len([c for c in (new_moves or "").split("\\n") if c.strip()])
            _corps = (
                "%s a joué %s" % (me["pseudo"],
                                  _coup_pour_notif(notation, my_color, _nb))
                if notation else me["pseudo"] + " a joué, à vous de jouer !"
            )
            _notify_user(opp_uid, "turn", "La Fuga", _corps,
                         {"type": "corr_turn", "game_id": str(gid),
                          "coup": notation})''',
        '''            _nb = len([c for c in (new_moves or "").split("\\n") if c.strip()])
            _corps = (
                "a joué %s" % _coup_pour_notif(notation, my_color, _nb)
                if notation else "a joué, à vous de jouer !"
            )
            _notify_user(opp_uid, "turn", me["pseudo"], _corps,
                         {"type": "corr_turn", "game_id": str(gid),
                          "coup": notation})''',
    ),
    (
        "4. coup final : notifier l'adversaire (nouveau)",
        '''        try:
            if final_row:
                _archive_corr_game(final_row, resultat, methode)
        except Exception as e:
            print("[corr archive] erreur :", e)
        return jsonify({"ok": True})''',
        '''        try:
            if final_row:
                _archive_corr_game(final_row, resultat, methode)
        except Exception as e:
            print("[corr archive] erreur :", e)
        # Notification push : la partie vient de se terminer sur ce coup, et
        # personne n'en prevenait l'adversaire. Le destinataire est celui qui
        # n'a PAS joue — pas le perdant : un coup peut faire gagner l'autre.
        try:
            _autre = (row["noir_user_id"] if my_color == "Blanc"
                      else row["blanc_user_id"])
            _nb = len([c for c in (new_moves or "").split("\\n") if c.strip()])
            _coup = (_coup_pour_notif(notation, my_color, _nb)
                     if notation else "")
            _corps = ("a joué %s — partie terminée" % _coup
                      if _coup else "partie terminée")
            _notify_user(_autre, "turn", me["pseudo"], _corps,
                         {"type": "corr_fin", "game_id": str(gid),
                          "coup": notation, "resultat": resultat})
        except Exception:
            pass
        return jsonify({"ok": True})''',
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
        print("Sinon, appliquez d'abord patch_notif_coup.py, dont celui-ci "
              "reprend la mise en forme du coup.")
        return 1

    resultat = source
    for _, motif, remplacement in CORRECTIONS:
        resultat = resultat.replace(motif, remplacement, 1)

    if "_coup_pour_notif" not in resultat:
        print("patch_notif_coup.py n'a pas ete applique : rien n'a ete ecrit.")
        return 1

    # Garde-fou : plus une seule notification ne doit avoir « La Fuga » en
    # titre. S'il en reste une, c'est un site oublie.
    # NB : soustraire 'def _notify_user(' et NON 'def _notify_user', qui
    # attraperait aussi 'def _notify_user_sync('.
    reste = (resultat.count('_notify_user(')
             - resultat.count('def _notify_user('))
    if '"La Fuga"' in resultat:
        print("Il reste un titre « La Fuga » : rien n'a ete ecrit.")
        return 1
    if reste != 6:
        print("Attendu 6 appels a _notify_user, trouve %d : rien n'a ete "
              "ecrit." % reste)
        return 1

    try:
        compile(resultat, chemin, "exec")
    except SyntaxError as e:
        print("Le resultat ne compile pas (%s). Rien n'a ete ecrit." % e)
        return 1

    horodatage = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    sauvegarde = "%s.avant-notifs-%s" % (chemin, horodatage)
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
