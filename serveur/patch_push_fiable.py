# -*- coding: utf-8 -*-
"""Une notification perdue est reessayee, et un echec se dit.

LE DEFAUT. `_send_push` se terminait ainsi :

    messaging.send(message)
    except Exception as e:
        print("[FCM] envoi echoue :", e)

Un seul essai. La moindre secousse entre le serveur et Google — un paquet
perdu, un 503, une seconde d'indisponibilite — et la notification n'existait
plus. Rien ne la reprenait, et la seule trace etait une ligne de journal que
personne ne lisait. Nino : « des fois je les recois et une fois de temps en
temps, non ». Ni un type de notification, ni une heure : du hasard, et c'est
la signature d'un envoi qu'on abandonne.

LA CORRECTION. Trois essais, une demi-seconde puis deux secondes d'attente —
le total reste sous les trois secondes, donc loin du delai que l'appelant
accorde, et la place tenue dans la reserve d'envoi ne change pas d'ordre de
grandeur.

Et on distingue deux echecs : celui qui peut passer tout seul (reseau,
indisponibilite) et celui qu'aucune insistance ne changera (jeton mort, jeton
d'une autre application, message mal forme). Le second s'arrete au premier
essai et s'ecrit « jeton mort » : c'est l'autre cause possible d'une
notification qui n'arrive jamais, et on la verra desormais dans le journal.

LE RESTE NE BOUGE PAS. La notification part deja en priorite haute, avec une
charge qu'Android affiche lui-meme application fermee : il n'y avait rien a
corriger de ce cote.

USAGE
    python3 patch_push_fiable.py /chemin/vers/server.py

Le script REFUSE d'ecrire si un motif n'est pas trouve exactement une fois, y
compris sur un fichier deja corrige. Une sauvegarde horodatee est posee a cote
avant toute ecriture, et le resultat est compile avant d'etre ecrit.
"""
import datetime
import hashlib
import io
import os
import shutil
import sys


# ── 1. Les reglages et les deux aides, juste avant la reserve d'envoi ───────
#
# Le motif tient en une ligne sans accent : c'est ce qui se recopie le plus
# surement d'un terminal a l'autre.
MOTIF_POOL = '''_FCM_POOL = gevent.pool.Pool(int(os.environ.get("LAFUGA_FCM_POOL", "20")))'''

AJOUT_POOL = '''# Combien de fois une notification est representee a Firebase, et l'attente
# entre deux essais. Le total reste sous les trois secondes.
_FCM_ESSAIS = 3
_FCM_ATTENTES = (0.5, 2.0, 0)

# Les erreurs qu'un second essai ne changerait pas : le jeton n'existe plus
# (l'application a ete desinstallee ou ses donnees effacees), il appartient a
# une autre application, ou le message est mal forme.
#
# ON COMPARE LE NOM DE LA CLASSE, et non la classe elle-meme : ces exceptions
# ont change de place entre les versions de `firebase-admin`, et un import
# qui echoue dans la gestion d'erreur transformerait une notification perdue
# en trace illisible.
_FCM_DEFINITIF = ("UnregisteredError", "SenderIdMismatchError",
                  "InvalidArgumentError", "ThirdPartyAuthError")
_FCM_JETON_MORT = ("UnregisteredError", "SenderIdMismatchError")


def _fcm_reessayable(e):
    """Vrai si l'erreur peut disparaitre d'elle-meme."""
    return type(e).__name__ not in _FCM_DEFINITIF


def _fcm_trace(fcm_token):
    """De quoi reconnaitre un appareil dans le journal, sans ecrire son jeton."""
    return "...%s" % (fcm_token or "")[-8:]


_FCM_POOL = gevent.pool.Pool(int(os.environ.get("LAFUGA_FCM_POOL", "20")))'''


# ── 2. L'envoi lui-meme ────────────────────────────────────────────────────
MOTIF_ENVOI = '''        messaging.send(message)
    except Exception as e:
        print("[FCM] envoi echoue :", e)'''

AJOUT_ENVOI = '''        # ON REESSAIE. Un envoi perdu l'etait pour toujours.
        derniere = None
        essai = 0
        for essai in range(_FCM_ESSAIS):
            try:
                messaging.send(message)
                if essai:
                    print("[FCM] envoi reussi au %d e essai (jeton %s)"
                          % (essai + 1, _fcm_trace(fcm_token)))
                return
            except Exception as e:
                derniere = e
                if not _fcm_reessayable(e):
                    break
                gevent.sleep(_FCM_ATTENTES[essai])
        # UN ECHEC SE DIT, ET AVEC DE QUOI LE RETROUVER : le type de l'erreur,
        # la fin du jeton, le titre. Sans cela, « des fois ca ne marche pas »
        # ne se verifie dans aucun journal.
        print("[FCM] ECHEC apres %d essai(s) : %s : %s (jeton %s, titre %r)"
              % (essai + 1, type(derniere).__name__, derniere,
                 _fcm_trace(fcm_token), title))
        if type(derniere).__name__ in _FCM_JETON_MORT:
            print("[FCM] jeton mort, cet appareil ne recevra plus rien "
                  "jusqu'a sa prochaine connexion : %s" % _fcm_trace(fcm_token))
    except Exception as e:
        print("[FCM] envoi echoue :", e)'''


CORRECTIONS = [
    ("les reglages et les deux aides", MOTIF_POOL, AJOUT_POOL),
    ("l'envoi reessaye", MOTIF_ENVOI, AJOUT_ENVOI),
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
    sauvegarde = "%s.avant-push-%s" % (chemin, horodatage)
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
