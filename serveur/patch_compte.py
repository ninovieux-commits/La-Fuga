# -*- coding: utf-8 -*-
"""CHANGER DE PSEUDO, CHANGER DE MOT DE PASSE.

Nino le demande depuis longtemps : un compte doit pouvoir changer de nom et
de mot de passe sans qu'on touche a la base a la main.

Deux routes, posees juste avant /login — c'est la que vivent les affaires de
compte.

    /changer_pseudo   token + pseudo
    /changer_mdp      token + ancien + nouveau

## Le pseudo se change PARTOUT A LA FOIS

Trois tables gardent un pseudo en toutes lettres, et non par identifiant :

    games        joueur1, joueur2        (l'historique)
    corr_games   blanc_pseudo, noir_pseudo
    corr_chat    auteur

Les oublier, ce serait laisser l'historique au nom d'avant — et pire, l'ecran
d'historique ne saurait plus de quel cote le joueur etait, puisqu'il se
reconnait par son nom : il afficherait de travers qui a gagne. Les cinq
colonnes sont donc renommees dans la MEME transaction que le compte.

Les sockets ouvertes portent aussi le pseudo, en memoire : on les corrige
dans la foulee, sans quoi un message envoye juste apres le changement ne
trouverait plus personne.

LE JETON NE CHANGE PAS : il est range par identifiant de compte, pas par nom.
On ne deconnecte donc personne.

## Le mot de passe se change avec l'ancien

Et il ferme les AUTRES sessions : changer son mot de passe sert justement a
chasser quelqu'un. Celle qui demande le changement reste ouverte — on ne
punit pas celui qui fait le menage.

Les deux routes passent par `validate_pseudo` et `validate_password`, celles
de l'inscription : on ne doit pas pouvoir se donner par changement un nom ou
un mot de passe qu'on n'aurait pas pu choisir au depart.

USAGE
    python3 patch_compte.py /chemin/vers/server.py

Le script REFUSE d'ecrire si le motif n'est pas trouve exactement une fois, y
compris sur un fichier deja corrige. Une sauvegarde horodatee est posee a
cote avant toute ecriture, et le resultat est compile avant d'etre ecrit.
"""
import datetime
import hashlib
import io
import os
import shutil
import sys


MOTIF = '''@flask_app.route("/login", methods=["POST"])'''

AJOUT = '''# ---------------------------------------------------------------------------
# LE COMPTE : changer de nom, changer de mot de passe.
# ---------------------------------------------------------------------------


def _renomme_partout(conn, ancien, nouveau):
    """Reecrit le pseudo la ou il est garde en toutes lettres.

    Trois tables : l'historique (games), la correspondance (corr_games) et son
    chat (corr_chat). Partout ailleurs on range par identifiant, et il n'y a
    rien a faire.

    La comparaison ignore la casse, comme tout le reste du serveur : un
    « Nino » et un « nino » sont le meme joueur.
    """
    bas = ancien.lower()
    conn.execute("UPDATE games SET joueur1 = ? WHERE lower(joueur1) = ?",
                 (nouveau, bas))
    conn.execute("UPDATE games SET joueur2 = ? WHERE lower(joueur2) = ?",
                 (nouveau, bas))
    conn.execute(
        "UPDATE corr_games SET blanc_pseudo = ? WHERE lower(blanc_pseudo) = ?",
        (nouveau, bas))
    conn.execute(
        "UPDATE corr_games SET noir_pseudo = ? WHERE lower(noir_pseudo) = ?",
        (nouveau, bas))
    conn.execute("UPDATE corr_chat SET auteur = ? WHERE lower(auteur) = ?",
                 (nouveau, bas))


@flask_app.route("/changer_pseudo", methods=["POST"])
def changer_pseudo():
    """Change le nom du compte, et partout ou il est ecrit."""
    data = request.get_json(silent=True) or {}
    me = user_from_token(data.get("token", ""))
    if not me:
        return jsonify({"ok": False, "error": "Token invalide"}), 401
    nouveau = (data.get("pseudo") or "").strip()

    err = validate_pseudo(nouveau)
    if err:
        return jsonify({"ok": False, "error": err}), 400

    ancien = me["pseudo"]
    if nouveau == ancien:
        return jsonify({"ok": True, "pseudo": ancien})

    bas = nouveau.lower()
    conn = get_db()
    # Pris par QUELQU'UN D'AUTRE : se renommer « Nino » quand on s'appelle
    # « nino » doit rester possible.
    pris = conn.execute(
        "SELECT id FROM users WHERE pseudo_lower = ? AND id <> ?",
        (bas, me["id"])).fetchone()
    if pris:
        conn.close()
        return jsonify({"ok": False, "error": "Pseudo deja pris"}), 409

    try:
        conn.execute(
            "UPDATE users SET pseudo = ?, pseudo_lower = ? WHERE id = ?",
            (nouveau, bas, me["id"]))
        _renomme_partout(conn, ancien, nouveau)
        conn.commit()
    except Exception as e:
        print("[compte] renommage impossible :", e)
        conn.close()
        return jsonify({"ok": False, "error": "Changement impossible"}), 500
    conn.close()

    # Les sockets ouvertes portent le pseudo en memoire : sans cela, un
    # message envoye juste apres ne trouverait plus personne.
    try:
        for _s, _info in list(CONNECTED.items()):
            if _info.get("user_id") == me["id"]:
                _info["pseudo"] = nouveau
    except Exception as e:
        print("[compte] sockets non mises a jour :", e)

    print("[compte] %s devient %s" % (ancien, nouveau))
    return jsonify({"ok": True, "pseudo": nouveau, "ancien": ancien})


@flask_app.route("/changer_mdp", methods=["POST"])
def changer_mdp():
    """Change le mot de passe, l'ancien en main, et ferme les autres sessions."""
    data = request.get_json(silent=True) or {}
    token = data.get("token", "")
    me = user_from_token(token)
    if not me:
        return jsonify({"ok": False, "error": "Token invalide"}), 401
    ancien = data.get("ancien") or ""
    nouveau = data.get("nouveau") or ""

    if hash_password(ancien, me["salt"]) != me["password_hash"]:
        return jsonify({"ok": False, "error": "Mot de passe incorrect"}), 401
    err = validate_password(nouveau)
    if err:
        return jsonify({"ok": False, "error": err}), 400
    if nouveau == ancien:
        return jsonify({"ok": False,
                        "error": "Le nouveau est l'ancien"}), 400

    sel = secrets.token_hex(16)
    conn = get_db()
    try:
        conn.execute(
            "UPDATE users SET password_hash = ?, salt = ? WHERE id = ?",
            (hash_password(nouveau, sel), sel, me["id"]))
        # LES AUTRES SESSIONS SE FERMENT : changer son mot de passe sert
        # justement a chasser quelqu'un. Celle qui le demande reste ouverte.
        conn.execute("DELETE FROM tokens WHERE user_id = ? AND token <> ?",
                     (me["id"], token))
        conn.commit()
    except Exception as e:
        print("[compte] mot de passe non change :", e)
        conn.close()
        return jsonify({"ok": False, "error": "Changement impossible"}), 500
    conn.close()
    print("[compte] mot de passe change pour", me["pseudo"])
    return jsonify({"ok": True})


@flask_app.route("/login", methods=["POST"])'''


CORRECTIONS = [("les routes de compte", MOTIF, AJOUT)]


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
    sauvegarde = "%s.avant-compte-%s" % (chemin, horodatage)
    shutil.copy2(chemin, sauvegarde)
    with io.open(chemin, "w", encoding="utf-8") as f:
        f.write(corrige)

    print("Sauvegarde : %s" % sauvegarde)
    print("%d correction appliquee." % len(CORRECTIONS))
    print("sha256 du fichier corrige : %s"
          % hashlib.sha256(corrige.encode("utf-8")).hexdigest())
    print("")
    print("Redemarrez le service :  sudo systemctl restart lafuga")
    return 0


if __name__ == "__main__":
    sys.exit(main())
