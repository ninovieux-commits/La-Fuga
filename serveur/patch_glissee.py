# -*- coding: utf-8 -*-
"""La vitesse de glissee des pieces suit le COMPTE, comme l'instrument.

Meme histoire, meme forme : le reglage vivait sur l'appareil, il s'enregistre
maintenant dans le compte et se retrouve d'un telephone a l'autre.

CE QUI EST AJOUTE
    - colonne users.glissee     : -1 quand le compte n'a jamais rien dit
    - POST /set_glissee         : le jumeau de /set_instrument
    - /register, /login, /ping  : rendent `glissee` avec le reste

POURQUOI -1 ET NON 0. Une duree est toujours positive ou nulle, et ZERO EST UN
CHOIX : c'est la glissee instantanee, que des joueurs veulent. Le marqueur
« ce compte n'a jamais rien dit » ne peut donc pas etre zero, sinon on
remplacerait leur choix par celui de l'appareil a chaque connexion. Une valeur
negative, impossible par ailleurs, porte ce sens sans ambiguite.

AUCUNE BORNE SUPERIEURE INVENTEE ICI. Le serveur refuse ce qui n'est pas un
nombre et coupe a [0, 10] secondes — de quoi tenir toute echelle que
l'application voudra offrir, sans avoir a le redeployer quand elle change son
curseur.

N'ENLEVE RIEN. Une application pas encore corrigee n'appelle jamais
/set_glissee et ignore la cle `glissee` qu'on lui rend.

A APPLIQUER APRES patch_instrument.py, dont il reprend la place dans les trois
reponses.

USAGE
    python3 patch_glissee.py /chemin/vers/server.py

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


# ── 1. La colonne ───────────────────────────────────────────────────────────
MOTIF_SCHEMA = '''    try:
        c.execute("ALTER TABLE users ADD COLUMN instrument TEXT DEFAULT ''")
    except Exception:
        pass'''

REMPLACEMENT_SCHEMA = '''    try:
        c.execute("ALTER TABLE users ADD COLUMN instrument TEXT DEFAULT ''")
    except Exception:
        pass
    # Vitesse de glissee des pieces, en secondes. Defaut -1 : « jamais rien
    # dit ». Pas zero — zero est un CHOIX, la glissee instantanee.
    try:
        c.execute("ALTER TABLE users ADD COLUMN glissee REAL DEFAULT -1")
    except Exception:
        pass'''


# ── 2. La route ─────────────────────────────────────────────────────────────
MOTIF_ROUTE = '''@flask_app.route("/set_instrument", methods=["POST"])'''

REMPLACEMENT_ROUTE = '''@flask_app.route("/set_glissee", methods=["POST"])
def set_glissee():
    """Enregistre la vitesse de glissee choisie par le joueur (retrouvee a
    chaque connexion, meme depuis un autre appareil)."""
    data = request.get_json(silent=True) or {}
    me = user_from_token(data.get("token", ""))
    if not me:
        return jsonify({"ok": False, "error": "Token invalide"}), 401
    try:
        glissee = float(data.get("glissee"))
    except (TypeError, ValueError):
        return jsonify({"ok": False, "error": "glissee invalide"}), 400
    if glissee != glissee or glissee in (float("inf"), float("-inf")):
        return jsonify({"ok": False, "error": "glissee invalide"}), 400
    # Bornes larges : de quoi tenir toute echelle que l'application voudra
    # offrir, sans redeployer le serveur quand elle change son curseur.
    glissee = max(0.0, min(10.0, glissee))
    conn = get_db()
    conn.execute("UPDATE users SET glissee = ? WHERE id = ?",
                 (glissee, me["id"]))
    conn.commit()
    conn.close()
    return jsonify({"ok": True, "glissee": glissee})


@flask_app.route("/set_instrument", methods=["POST"])'''


# ── 3. Les trois reponses ───────────────────────────────────────────────────
MOTIF_REGISTER = '''    return jsonify({"ok": True, "token": token, "pseudo": pseudo, "melo": 1500, "melo_random": 1500, "theme": "original", "instrument": ""})'''

REMPLACEMENT_REGISTER = '''    return jsonify({"ok": True, "token": token, "pseudo": pseudo, "melo": 1500, "melo_random": 1500, "theme": "original", "instrument": "", "glissee": -1})'''


MOTIF_LOGIN = '''                    "theme": user.get("theme") or "original",
                    "instrument": user.get("instrument") or ""})'''

REMPLACEMENT_LOGIN = '''                    "theme": user.get("theme") or "original",
                    "instrument": user.get("instrument") or "",
                    "glissee": _glissee_de(user)})'''


MOTIF_PING = '''    return jsonify({"ok": True, "pseudo": user["pseudo"], "melo": user["melo"], "melo_random": user.get("melo_random", 1500), "theme": user.get("theme") or "original", "instrument": user.get("instrument") or ""})'''

REMPLACEMENT_PING = '''    return jsonify({"ok": True, "pseudo": user["pseudo"], "melo": user["melo"], "melo_random": user.get("melo_random", 1500), "theme": user.get("theme") or "original", "instrument": user.get("instrument") or "", "glissee": _glissee_de(user)})'''


# ── 4. La lecture, qui doit distinguer zero de l'absence ────────────────────
MOTIF_HELPER = '''@flask_app.route("/set_glissee", methods=["POST"])'''

REMPLACEMENT_HELPER = '''def _glissee_de(user):
    """La glissee d'un compte, ou -1 quand il n'a jamais rien dit.

    `user.get("glissee") or -1` SERAIT FAUX : zero est un choix — la glissee
    instantanee — et `or` le prendrait pour une absence. L'application
    remplacerait alors ce choix par celui de l'appareil a chaque connexion.
    """
    try:
        v = user.get("glissee")
    except AttributeError:
        v = None
    return -1 if v is None else float(v)


@flask_app.route("/set_glissee", methods=["POST"])'''


CORRECTIONS = [
    ("schema : users.glissee", MOTIF_SCHEMA, REMPLACEMENT_SCHEMA),
    ("route /set_glissee", MOTIF_ROUTE, REMPLACEMENT_ROUTE),
    ("lecture : zero n'est pas une absence", MOTIF_HELPER, REMPLACEMENT_HELPER),
    ("/register rend la glissee", MOTIF_REGISTER, REMPLACEMENT_REGISTER),
    ("/login rend la glissee", MOTIF_LOGIN, REMPLACEMENT_LOGIN),
    ("/ping rend la glissee", MOTIF_PING, REMPLACEMENT_PING),
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

    # Les corrections 2 et 3 touchent le meme endroit : la seconde s'applique
    # au texte que la premiere vient d'ecrire. On les verifie donc en chaine,
    # et non toutes sur le fichier d'origine.
    courant = source
    for nom, motif, remplacement in CORRECTIONS:
        n = courant.count(motif)
        if n != 1:
            print("REFUS : le motif « %s » apparait %d fois (attendu : 1)."
                  % (nom, n))
            print("Le fichier n'a PAS ete modifie.")
            print("Un fichier deja corrige donne 0 : il n'y a rien a refaire.")
            print("patch_instrument.py doit avoir ete applique avant celui-ci.")
            return 1
        courant = courant.replace(motif, remplacement)

    horodatage = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    sauvegarde = "%s.avant-glissee-%s" % (chemin, horodatage)
    shutil.copy2(chemin, sauvegarde)
    with io.open(chemin, "w", encoding="utf-8") as f:
        f.write(courant)

    print("Sauvegarde : %s" % sauvegarde)
    print("%d corrections appliquees." % len(CORRECTIONS))
    print("sha256 du fichier corrige : %s"
          % hashlib.sha256(courant.encode("utf-8")).hexdigest())
    print("")
    print("Redemarrez le service :  sudo systemctl restart lafuga")
    return 0


if __name__ == "__main__":
    sys.exit(main())
