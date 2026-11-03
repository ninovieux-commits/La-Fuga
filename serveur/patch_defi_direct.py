# -*- coding: utf-8 -*-
"""Un defi en direct atteint TOUTES les sockets de la cible.

Nino : « corrige aussi le defi en direct. »

`on_defier` cherche la cible avec `_find_sid_by_pseudo`, qui rend LA PREMIERE
socket trouvee sous ce pseudo. Un joueur peut en avoir plusieurs : deux
appareils ouverts, ou un fantome laisse par une coupure que le serveur n'a pas
encore vue. Choisir la premiere, c'est parfois choisir la morte — et alors :

    - le defieur recoit « defi_envoye » et attend une reponse ;
    - la cible, elle, ne voit rien du tout ;
    - ou bien, si aucune socket n'est trouvee alors que la personne est en
      ligne sur une autre, le defieur lit « hors ligne » a tort.

Quatre changements, et rien d'autre :

    1. un `_find_sids_by_pseudo` qui les rend TOUTES ;
    2. `on_defier` s'en sert ; `cible_sid` reste la premiere, pour tout ce qui
       suit (le controle de blocage, le melo, la partie qui demarre) ;
    3. le defi est annonce a toutes les sockets de la cible ;
    4. l'annulation aussi — sans quoi un defi annule resterait affiche sur le
       second appareil.

Le defi lui-meme, son enregistrement et sa reponse ne changent pas : la cle
`cible_sid` reste dans DEFIS, a cote de la nouvelle liste.

USAGE
    python3 patch_defi_direct.py /chemin/vers/server.py

Le script REFUSE d'ecrire si l'un des motifs n'est pas trouve exactement une
fois, y compris sur un fichier deja corrige. Une sauvegarde horodatee est
posee a cote avant toute ecriture, et le resultat est compile avant d'etre
ecrit.
"""
import datetime
import hashlib
import io
import os
import shutil
import sys


# ── 1. Toutes les sockets d'un pseudo ───────────────────────────────────────
MOTIF_HELPER = '''def _find_sid_by_pseudo(pseudo):'''

AJOUT_HELPER = '''def _find_sids_by_pseudo(pseudo):
    """TOUTES les sockets connectees sous ce pseudo, de la plus ancienne a la
    plus recente.

    Un joueur peut en avoir plusieurs : deux appareils, ou un fantome laisse
    par une coupure que le serveur n'a pas encore vue. Ne regarder que la
    premiere, c'est parfois ne regarder que la morte.
    """
    pl = pseudo.lower()
    return [s for s, info in CONNECTED.items()
            if info["pseudo"].lower() == pl]


def _find_sid_by_pseudo(pseudo):'''


# ── 2. Le defi les cherche toutes ───────────────────────────────────────────
MOTIF_CIBLES = '''        cible_sid = _find_sid_by_pseudo(pseudo_cible)
        if not cible_sid:'''

AJOUT_CIBLES = '''        cibles = _find_sids_by_pseudo(pseudo_cible)
        # La premiere sert de reference pour tout ce qui suit — le controle
        # de blocage, le melo, la partie qui demarre — mais l'annonce, elle,
        # ira a toutes.
        cible_sid = cibles[0] if cibles else None
        if not cible_sid:'''


# ── 3. On retient la liste a cote de la premiere ───────────────────────────
MOTIF_DEFIS = '''            "cible_sid": cible_sid, "cible_pseudo": cible_info["pseudo"],'''

AJOUT_DEFIS = '''            "cible_sid": cible_sid, "cible_sids": list(cibles),
            "cible_pseudo": cible_info["pseudo"],'''


# ── 4. L'annonce part vers toutes ──────────────────────────────────────────
#
# Le motif prend l'emission ENTIERE, et le remplacement en fait une boucle.
# Un `to=None` aurait ete plus court a ecrire — et c'est precisement le piege :
# en python-socketio, emettre sans destinataire, c'est emettre A TOUT LE
# MONDE. Le defi serait parti chez tous les joueurs connectes.
MOTIF_EMIT = '''    sio.emit("defi_recu", {
        "defi_id": defi_id, "defieur": info["pseudo"],
        "defieur_melo": _dm, "objectif": objectif, "cadence": cadence,
        "random": rnd,
    }, to=cible_sid)'''

AJOUT_EMIT = '''    for _cible in cibles:
        sio.emit("defi_recu", {
            "defi_id": defi_id, "defieur": info["pseudo"],
            "defieur_melo": _dm, "objectif": objectif, "cadence": cadence,
            "random": rnd,
        }, to=_cible)'''


# ── 5. Et l'annulation aussi ───────────────────────────────────────────────
MOTIF_ANNULE = '''        cible_sid = defi["cible_sid"] if defi else None
    if cible_sid:
        sio.emit("defi_annule", {"defi_id": defi_id}, to=cible_sid)'''

AJOUT_ANNULE = '''        # Toutes les sockets de la cible : un defi annule ne doit pas rester
        # affiche sur le second appareil. `cible_sids` manque aux defis poses
        # avant ce correctif — on retombe alors sur l'unique.
        cibles = (defi.get("cible_sids") or
                  ([defi["cible_sid"]] if defi else [])) if defi else []
    for _cible in cibles:
        sio.emit("defi_annule", {"defi_id": defi_id}, to=_cible)'''


CORRECTIONS = [
    ("toutes les sockets", MOTIF_HELPER, AJOUT_HELPER),
    ("la recherche de la cible", MOTIF_CIBLES, AJOUT_CIBLES),
    ("la liste retenue", MOTIF_DEFIS, AJOUT_DEFIS),
    ("l'annonce du defi", MOTIF_EMIT, AJOUT_EMIT),
    ("l'annulation", MOTIF_ANNULE, AJOUT_ANNULE),
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
    sauvegarde = "%s.avant-defi-direct-%s" % (chemin, horodatage)
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
