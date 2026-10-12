# -*- coding: utf-8 -*-
"""L'instrument appartient au JOUEUR, pas au telephone.

Le choix de l'instrument vivait sur l'appareil. Changer de telephone, ou se
reconnecter apres une reinstallation, et l'on retrouvait le piano. Il
s'enregistre maintenant dans le compte, exactement comme le theme : on le
retrouve partout ou l'on se connecte.

CE QUI EST AJOUTE
    - colonne users.instrument  : '' quand le compte n'a jamais rien dit
    - POST /set_instrument      : le jumeau de /set_theme
    - /register, /login, /ping  : rendent `instrument` avec le reste

LE VIDE COMPTE. Un compte qui n'a jamais choisi rend `''`, et non `'piano'`.
C'est ce qui distingue « ce compte veut le piano » de « ce compte n'a jamais
rien dit » : dans le second cas, c'est l'APPLICATION qui envoie l'instrument de
l'appareil, au lieu d'en adopter un. Les confondre remettrait le piano a
quelqu'un qui venait de choisir la harpe.

AUCUNE LISTE D'INSTRUMENTS ICI. Le serveur nettoie la valeur — lettres
minuscules, vingt caracteres au plus — mais ne tient pas la liste des
instruments qui existent. Sinon, ajouter une flute a l'application demanderait
de redeployer le serveur pour qu'il daigne l'enregistrer. L'application, elle,
se garde deja d'un nom inconnu : elle retombe sur le premier instrument plutot
que de rester muette.

N'ENLEVE RIEN. Une application pas encore corrigee n'appelle jamais
/set_instrument et ignore la cle `instrument` qu'on lui rend : elle se comporte
exactement comme avant.

USAGE
    python3 patch_instrument.py /chemin/vers/server.py

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
MOTIF_SCHEMA = '''    # Thème choisi par le joueur (retrouvé à chaque connexion, même autre appareil).
    try:
        c.execute("ALTER TABLE users ADD COLUMN theme TEXT DEFAULT 'original'")
    except Exception:
        pass'''

REMPLACEMENT_SCHEMA = '''    # Thème choisi par le joueur (retrouvé à chaque connexion, même autre appareil).
    try:
        c.execute("ALTER TABLE users ADD COLUMN theme TEXT DEFAULT 'original'")
    except Exception:
        pass
    # Instrument choisi par le joueur, retrouve de la meme facon.
    #
    # Defaut VIDE, et non 'piano' : le vide dit « ce compte n'a jamais rien
    # choisi », et c'est alors l'application qui y pose l'instrument de
    # l'appareil. Mettre un instrument par defaut ecraserait ce choix a chaque
    # connexion d'un compte d'avant.
    try:
        c.execute("ALTER TABLE users ADD COLUMN instrument TEXT DEFAULT ''")
    except Exception:
        pass'''


# ── 2. La route, jumelle de /set_theme ──────────────────────────────────────
MOTIF_ROUTE = '''@flask_app.route("/set_fcm_token", methods=["POST"])'''

REMPLACEMENT_ROUTE = '''@flask_app.route("/set_instrument", methods=["POST"])
def set_instrument():
    """Enregistre l'instrument choisi par le joueur (retrouve a chaque
    connexion, meme depuis un autre appareil)."""
    data = request.get_json(silent=True) or {}
    me = user_from_token(data.get("token", ""))
    if not me:
        return jsonify({"ok": False, "error": "Token invalide"}), 401
    # On NETTOIE sans juger : lettres minuscules, vingt caracteres au plus. Le
    # serveur ne tient pas la liste des instruments qui existent — sinon,
    # ajouter une flute a l'application demanderait de le redeployer. Un nom
    # vide est accepte : c'est ainsi qu'on efface son choix.
    brut = (data.get("instrument") or "").strip().lower()[:20]
    instrument = "".join(ch for ch in brut if "a" <= ch <= "z")
    conn = get_db()
    conn.execute("UPDATE users SET instrument = ? WHERE id = ?",
                 (instrument, me["id"]))
    conn.commit()
    conn.close()
    return jsonify({"ok": True, "instrument": instrument})


@flask_app.route("/set_fcm_token", methods=["POST"])'''


# ── 3. Les trois reponses qui portent deja le theme ─────────────────────────
# Un compte tout juste cree n'a rien choisi : il rend '' , et l'application y
# pose l'instrument de l'appareil.
MOTIF_REGISTER = '''    return jsonify({"ok": True, "token": token, "pseudo": pseudo, "melo": 1500, "melo_random": 1500, "theme": "original"})'''

REMPLACEMENT_REGISTER = '''    return jsonify({"ok": True, "token": token, "pseudo": pseudo, "melo": 1500, "melo_random": 1500, "theme": "original", "instrument": ""})'''


MOTIF_LOGIN = '''    return jsonify({"ok": True, "token": token,
                    "pseudo": user["pseudo"], "melo": user["melo"],
                    "melo_random": user.get("melo_random", 1500),
                    "theme": user.get("theme") or "original"})'''

REMPLACEMENT_LOGIN = '''    return jsonify({"ok": True, "token": token,
                    "pseudo": user["pseudo"], "melo": user["melo"],
                    "melo_random": user.get("melo_random", 1500),
                    "theme": user.get("theme") or "original",
                    "instrument": user.get("instrument") or ""})'''


MOTIF_PING = '''    return jsonify({"ok": True, "pseudo": user["pseudo"], "melo": user["melo"], "melo_random": user.get("melo_random", 1500), "theme": user.get("theme") or "original"})'''

REMPLACEMENT_PING = '''    return jsonify({"ok": True, "pseudo": user["pseudo"], "melo": user["melo"], "melo_random": user.get("melo_random", 1500), "theme": user.get("theme") or "original", "instrument": user.get("instrument") or ""})'''


CORRECTIONS = [
    ("schema : users.instrument", MOTIF_SCHEMA, REMPLACEMENT_SCHEMA),
    ("route /set_instrument", MOTIF_ROUTE, REMPLACEMENT_ROUTE),
    ("/register rend l'instrument", MOTIF_REGISTER, REMPLACEMENT_REGISTER),
    ("/login rend l'instrument", MOTIF_LOGIN, REMPLACEMENT_LOGIN),
    ("/ping rend l'instrument", MOTIF_PING, REMPLACEMENT_PING),
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
    sauvegarde = "%s.avant-instrument-%s" % (chemin, horodatage)
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
