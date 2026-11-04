# -*- coding: utf-8 -*-
"""Le classement : les trente meilleurs melos, standard ou random.

Nino : « dans l'histoire on doit creer un classement qui liste les trente
meilleurs melos. [...] Quand elle fait passer l'App en mode random, le popup
se met a afficher les meilleurs melos de random, et vice et versa. »

UNE SEULE ROUTE AJOUTEE, `/classement`, et RIEN D'AUTRE n'est touche : pas de
colonne, pas de table, aucune ecriture en base. Elle lit `users`, trie sur la
colonne du mode demande, et rend trente lignes.

LA COLONNE EST CHOISIE DANS UNE LISTE FERMEE, jamais recopiee depuis la
requete : `melo` ou `melo_random`, point. Un nom de colonne ne peut pas
passer par un parametre SQL — il faut l'ecrire dans le texte de la requete —
et c'est precisement la que naissent les injections. Ici le client n'envoie
qu'un booleen, et le serveur choisit seul entre deux constantes.

MA PROPRE LIGNE VOYAGE AVEC LA LISTE, et avec mon vrai rang, meme au-dela
du trentieme. Nino : « le classement doit afficher une ligne fixe en bas,
qui est la ligne de l'utilisateur, pour pouvoir comparer son propre melo
avec celui des 30 meilleurs joueurs du volet defilant juste au-dessus. » Le
rang se COMPTE — combien de comptes me precedent, plus un — avec exactement
le meme ordre que la liste, sans quoi le trentieme de la liste et un joueur
annonce trente-et-unieme pourraient etre le meme.

LA PHOTO EST RENDUE QUAND LA BASE EN A UNE, et une chaine vide sinon : on lit
la ligne entiere et on y cherche la colonne, plutot que de la nommer dans le
SELECT, pour qu'une base qui ne l'aurait pas reponde quand meme. L'App sait
retrouver une photo manquante par `get_profile`, qu'elle garde en cache.

CE QUE LE CLASSEMENT NE FAIT PAS. Il ne filtre pas les comptes qui n'ont
jamais joue : un compte neuf est a 1500, et si personne n'a encore depasse
1500 le classement sera un classement de 1500. C'est volontaire — le filtre
demanderait de compter les parties de chacun, et Nino dira s'il le veut.

USAGE
    python3 patch_classement.py /chemin/vers/server.py

Le script REFUSE d'ecrire si le motif n'est pas trouve exactement une fois,
y compris sur un fichier deja corrige. Une sauvegarde horodatee est posee a
cote avant toute ecriture.
"""
import datetime
import hashlib
import io
import os
import shutil
import sys


# La route des enveloppes sert d'ancre : elle existe depuis `patch_enveloppes`
# et ne figure qu'une fois. On se pose JUSTE AVANT elle.
MOTIF = '''@flask_app.route("/env_liste", methods=["POST"])'''

AJOUT = '''# Les deux seules colonnes de classement. Le client envoie un booleen, le
# serveur choisit : un nom de colonne venu du dehors serait une injection.
_CLASSEMENT_COLONNES = {False: "melo", True: "melo_random"}

# Trente, comme demande. Une constante plutot qu'un nombre dans la requete :
# c'est le genre de chiffre qu'on veut pouvoir changer en un endroit.
_CLASSEMENT_TAILLE = 30


def _classement_melo(ligne, colonne):
    """Le melo d'une ligne dans la colonne du mode, 1500 a defaut."""
    try:
        return int(ligne.get(colonne) or 1500)
    except Exception:
        return 1500


@flask_app.route("/classement", methods=["POST"])
def classement():
    """Les trente meilleurs melos du mode demande.

    Renvoie, pour chacun : son rang (1 a 30), son pseudo, son melo et sa
    photo quand la base en garde une.
    """
    data = request.get_json(silent=True) or {}
    me = user_from_token(data.get("token", ""))
    if not me:
        return jsonify({"ok": False, "error": "Token invalide"}), 401
    rnd = bool(data.get("random"))
    colonne = _CLASSEMENT_COLONNES[rnd]
    try:
        base = get_db()
        lignes = base.execute(
            "SELECT * FROM users ORDER BY %s DESC, pseudo ASC LIMIT %d"
            % (colonne, _CLASSEMENT_TAILLE)).fetchall()
        # MON rang : combien de comptes me precedent, plus un. Le depart
        # est exactement celui de la liste — melo decroissant, puis pseudo
        # croissant — sinon deux joueurs pourraient se dire du meme rang.
        moi = dict(base.execute(
            "SELECT * FROM users WHERE id=?", (me["id"],)).fetchone() or {})
        mon_melo = _classement_melo(moi, colonne)
        devant = base.execute(
            "SELECT COUNT(*) AS n FROM users WHERE %s > ?"
            " OR (%s = ? AND pseudo < ?)" % (colonne, colonne),
            (mon_melo, mon_melo, moi.get("pseudo") or "")).fetchone()["n"]
    except Exception:
        return jsonify({"ok": False, "error": "Classement indisponible"}), 500
    joueurs = [
        {
            "rang": rang,
            "pseudo": dict(ligne).get("pseudo") or "",
            "melo": _classement_melo(dict(ligne), colonne),
            "photo": dict(ligne).get("photo") or "",
        }
        for rang, ligne in enumerate(lignes, 1)
    ]
    return jsonify({"ok": True, "random": rnd, "joueurs": joueurs,
                    "moi": {"rang": devant + 1,
                            "pseudo": moi.get("pseudo") or "",
                            "melo": mon_melo,
                            "photo": moi.get("photo") or ""}})


@flask_app.route("/env_liste", methods=["POST"])'''


def main():
    if len(sys.argv) < 2:
        print("usage: python3 patch_classement.py /chemin/vers/server.py")
        return 2
    chemin = sys.argv[1]
    if not os.path.isfile(chemin):
        print("introuvable : %s" % chemin)
        return 2

    source = io.open(chemin, encoding="utf-8").read()
    print("avant : %d lignes, sha256 %s"
          % (source.count("\n") + 1,
             hashlib.sha256(source.encode("utf-8")).hexdigest()))

    n = source.count(MOTIF)
    if n != 1:
        print("REFUS : l'ancre a ete trouvee %d fois au lieu d'une." % n)
        print("        Le fichier n'est pas celui attendu, ou il est deja")
        print("        corrige. Rien n'a ete ecrit.")
        return 1
    if "/classement" in source:
        print("REFUS : la route /classement existe deja. Rien n'a ete ecrit.")
        return 1

    sortie = source.replace(MOTIF, AJOUT, 1)

    try:
        compile(sortie, chemin, "exec")
    except SyntaxError as e:
        print("REFUS : le resultat ne compile pas (%s). Rien n'a ete ecrit." % e)
        return 1

    horodatage = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    sauvegarde = "%s.avant-classement-%s" % (chemin, horodatage)
    shutil.copy2(chemin, sauvegarde)
    print("sauvegarde : %s" % sauvegarde)

    io.open(chemin, "w", encoding="utf-8").write(sortie)
    print("apres : %d lignes, sha256 %s"
          % (sortie.count("\n") + 1,
             hashlib.sha256(sortie.encode("utf-8")).hexdigest()))
    print("ECRIT.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
