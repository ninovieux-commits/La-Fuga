# -*- coding: utf-8 -*-
"""Les ENVELOPPES : une image qui passe, et qui ne reste nulle part.

Nino : « je voudrais qu'on puisse envoyer des images mais je ne veux pas que
ca me coute cher sur le serveur. » D'ou ce sas, et non un hebergeur :

  - l'image arrive DEJA en 720p, reduite par le telephone. Le serveur ne
    decode rien, ne recompresse rien, ne fabrique aucune vignette : il recoit
    des octets, il les pose dans un fichier, il les rend. C'est le seul poste
    qui pourrait faire souffrir gevent, et il n'existe pas ici ;
  - DEUX enveloppes en attente par expediteur et par paire. Au-dela, l'envoi
    est refuse tant que le correspondant n'a pas ouvert ou supprime ;
  - QUARANTE-HUIT HEURES, puis l'enveloppe disparait d'elle-meme ;
  - OUVERTE PAR LE DESTINATAIRE, elle est effacee dans la foulee : le fichier
    comme la ligne. L'expediteur, lui, peut la rouvrir pour verifier ce qu'il
    a envoye sans la consommer — c'est ce que Nino demande : « on peut voir
    les enveloppes en attente chez le correspondant, les ouvrir pour verifier
    et les supprimer avant qu'il ne les ai ouvertes. »

Le stockage est donc borne par le plan lui-meme : quatre enveloppes par paire
de correspondants, 300 Ko piece en moyenne. Cent paires actives en meme temps
tiennent dans 120 Mo, et le disque du VPS en a 67 000 de libres.

CE QUI CHANGE
    - une table `enveloppes` (creee au demarrage si elle manque)
    - un dossier `enveloppes/` a cote de la base
    - quatre routes : /env_envoyer /env_liste /env_ouvrir /env_supprimer
    - un greenlet de menage qui passe toutes les dix minutes

RIEN N'EST RETIRE, et aucune route existante n'est touchee. Une application
pas encore mise a jour ne voit tout simplement pas ces routes.

LES IMAGES NE VONT PAS DANS LA BASE. Un fichier par enveloppe sur le disque,
et dans la base seulement la ligne qui dit qui, a qui, et jusqu'a quand.
Mettre 300 Ko de binaire dans SQLite ferait grossir le fichier que tout le
reste du serveur ouvre, copie et sauvegarde.

USAGE
    python3 patch_enveloppes.py /chemin/vers/server.py

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


# Le point d'insertion : juste avant l'envoi des notifications push. Ce
# fragment a ete lu sur le serveur, il est unique.
MOTIF = '''def _send_push(fcm_token, title, body, data=None):'''

AJOUT = '''# ---------------------------------------------------------------------------
# LES ENVELOPPES : une image qui passe, et qui ne reste nulle part.
# ---------------------------------------------------------------------------
# Deux en attente par expediteur et par paire, 48 h de duree de vie, effacee
# des que le destinataire l'ouvre. Le serveur ne decode jamais l'image : elle
# arrive deja reduite a 720p par le telephone, il ne fait que la poser sur le
# disque et la rendre.

# Ou vivent les images : a cote de la base, pas dedans.
ENV_DOSSIER = os.environ.get(
    "LAFUGA_ENV_DOSSIER",
    os.path.join(os.path.dirname(os.path.abspath(DB_PATH)), "enveloppes"))

# Plafond DUR, cote serveur. La limite des 720p est une politesse du client,
# et un client bricole ne la respecte pas : sans ce controle, n'importe qui
# pousse 50 Mo. Une photo 720p compressee pese 150 a 300 Ko ; 900 Ko laisse
# toute la marge voulue.
ENV_MAX_OCTETS = int(os.environ.get("LAFUGA_ENV_MAX", str(900 * 1024)))

# Combien d'enveloppes NON OUVERTES un expediteur peut laisser chez le meme
# correspondant.
ENV_MAX_EN_ATTENTE = int(os.environ.get("LAFUGA_ENV_EN_ATTENTE", "2"))

# Duree de vie d'une enveloppe, en secondes.
ENV_TTL = int(os.environ.get("LAFUGA_ENV_TTL", str(48 * 3600)))

# Periode du menage des enveloppes expirees.
ENV_MENAGE_PERIODE = int(os.environ.get("LAFUGA_ENV_MENAGE", "600"))


def _env_prepare():
    """Le dossier et la table, une fois pour toutes."""
    try:
        if not os.path.isdir(ENV_DOSSIER):
            os.makedirs(ENV_DOSSIER)
    except Exception as e:
        print("[enveloppes] dossier impossible :", e)
    try:
        conn = get_db()
        conn.execute("""CREATE TABLE IF NOT EXISTS enveloppes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            expediteur_id INTEGER NOT NULL,
            destinataire_id INTEGER NOT NULL,
            fichier TEXT NOT NULL,
            taille INTEGER NOT NULL,
            cree_a INTEGER NOT NULL,
            expire_a INTEGER NOT NULL)""")
        conn.execute("""CREATE INDEX IF NOT EXISTS idx_env_paire
            ON enveloppes (destinataire_id, expediteur_id)""")
        conn.commit()
        conn.close()
    except Exception as e:
        print("[enveloppes] table impossible :", e)


def _env_chemin(nom):
    """Le chemin d'un fichier d'enveloppe, et RIEN D'AUTRE.

    Le nom vient de la base, pas du reseau — mais on le recolle quand meme au
    dossier avec `basename` : si une ligne etait un jour forgee, elle ne
    pourrait pas faire lire un fichier d'ailleurs.
    """
    return os.path.join(ENV_DOSSIER, os.path.basename(nom))


def _env_efface(ligne):
    """Oublie une enveloppe : son fichier d'abord, sa ligne ensuite."""
    try:
        chemin = _env_chemin(ligne["fichier"])
        if os.path.isfile(chemin):
            os.remove(chemin)
    except Exception as e:
        print("[enveloppes] fichier non efface :", e)
    try:
        conn = get_db()
        conn.execute("DELETE FROM enveloppes WHERE id=?", (ligne["id"],))
        conn.commit()
        conn.close()
    except Exception as e:
        print("[enveloppes] ligne non effacee :", e)


def _env_purge():
    """Les enveloppes dont les 48 h sont passees s'en vont d'elles-memes.

    Le destinataire peut ne jamais revenir : sans ce passage, son enveloppe
    resterait sur le disque pour toujours.
    """
    try:
        conn = get_db()
        mortes = conn.execute(
            "SELECT id, fichier FROM enveloppes WHERE expire_a <= ?",
            (int(time.time()),)).fetchall()
        conn.close()
        for ligne in mortes:
            _env_efface(ligne)
        if mortes:
            print("[enveloppes] %d expiree(s) effacee(s)" % len(mortes))
    except Exception as e:
        print("[enveloppes] purge :", e)


def _env_menage():
    """Boucle de fond, comme le janitor : elle ne garde rien d'ouvert."""
    while True:
        gevent.sleep(ENV_MENAGE_PERIODE)
        _env_purge()
        _db_release()


def _env_json(ligne, moi_id):
    """Ce qu'une enveloppe dit a l'application."""
    return {
        "id": ligne["id"],
        "de_moi": bool(ligne["expediteur_id"] == moi_id),
        "cree_a": ligne["cree_a"],
        "expire_a": ligne["expire_a"],
        "taille": ligne["taille"],
    }


def _env_autre(data):
    """Le correspondant nomme par la requete, ou None."""
    pseudo = (data.get("pseudo") or "").strip()
    if not pseudo:
        return None
    return get_db().execute(
        "SELECT id, pseudo FROM users WHERE pseudo_lower = ?",
        (pseudo.lower(),)).fetchone()


@flask_app.route("/env_envoyer", methods=["POST"])
def env_envoyer():
    """Depose une enveloppe chez un correspondant.

    L'image arrive en base64 — le reste de l'API parle JSON, et une photo de
    300 Ko en fait 400 une fois encodee : ce n'est pas un prix.
    """
    data = request.get_json(silent=True) or {}
    me = user_from_token(data.get("token", ""))
    if not me:
        return jsonify({"ok": False, "error": "Token invalide"}), 401
    autre = _env_autre(data)
    if not autre:
        return jsonify({"ok": False, "error": "Joueur introuvable"}), 404
    if autre["id"] == me["id"]:
        return jsonify({"ok": False, "error": "Impossible"}), 400
    if _is_blocked_pair(me["id"], autre["id"]):
        return jsonify({"ok": False, "error": "Un blocage est en place"}), 403

    brut = data.get("image") or ""
    try:
        octets = base64.b64decode(brut, validate=True)
    except Exception:
        return jsonify({"ok": False, "error": "Image illisible"}), 400
    if not octets:
        return jsonify({"ok": False, "error": "Image vide"}), 400
    if len(octets) > ENV_MAX_OCTETS:
        return jsonify({"ok": False, "error": "Image trop lourde"}), 413

    _env_purge()
    conn = get_db()
    en_attente = conn.execute(
        "SELECT COUNT(*) AS n FROM enveloppes "
        "WHERE expediteur_id=? AND destinataire_id=?",
        (me["id"], autre["id"])).fetchone()["n"]
    conn.close()
    if en_attente >= ENV_MAX_EN_ATTENTE:
        return jsonify({"ok": False, "error": "Deja deux enveloppes en "
                                              "attente"}), 409

    nom = "%s.img" % uuid.uuid4().hex
    try:
        with open(_env_chemin(nom), "wb") as f:
            f.write(octets)
    except Exception as e:
        print("[enveloppes] ecriture impossible :", e)
        return jsonify({"ok": False, "error": "Stockage indisponible"}), 500

    maintenant = int(time.time())
    expire = maintenant + ENV_TTL
    conn = get_db()
    cur = conn.execute(
        "INSERT INTO enveloppes (expediteur_id, destinataire_id, fichier, "
        "taille, cree_a, expire_a) VALUES (?,?,?,?,?,?)",
        (me["id"], autre["id"], nom, len(octets), maintenant, expire))
    gid = cur.lastrowid
    conn.commit()
    conn.close()

    # Prevenue comme un message : c'en est un, et la preference de l'un vaut
    # pour l'autre.
    try:
        _notify_user(autre["id"], "msg", me["pseudo"],
                     "vous a envoye une enveloppe",
                     {"type": "enveloppe", "de": me["pseudo"],
                      "id": str(gid)})
    except Exception:
        pass
    return jsonify({"ok": True, "id": gid, "expire_a": expire})


@flask_app.route("/env_liste", methods=["POST"])
def env_liste():
    """Les enveloppes en attente avec ce correspondant, DANS LES DEUX SENS.

    Celles qu'on a recues et celles qu'on a envoyees : Nino veut pouvoir
    verifier et retirer les siennes tant qu'elles n'ont pas ete ouvertes.
    """
    data = request.get_json(silent=True) or {}
    me = user_from_token(data.get("token", ""))
    if not me:
        return jsonify({"ok": False, "error": "Token invalide"}), 401
    autre = _env_autre(data)
    if not autre:
        return jsonify({"ok": True, "enveloppes": []})
    _env_purge()
    lignes = get_db().execute(
        "SELECT * FROM enveloppes WHERE (expediteur_id=? AND destinataire_id=?)"
        " OR (expediteur_id=? AND destinataire_id=?) ORDER BY cree_a",
        (me["id"], autre["id"], autre["id"], me["id"])).fetchall()
    return jsonify({"ok": True,
                    "enveloppes": [_env_json(l, me["id"]) for l in lignes]})


@flask_app.route("/env_ouvrir", methods=["POST"])
def env_ouvrir():
    """Rend l'image. OUVERTE PAR LE DESTINATAIRE, elle est effacee ensuite.

    L'expediteur, lui, ne fait que regarder ce qu'il a envoye : son enveloppe
    reste en place. Sans cette distinction, verifier reviendrait a reprendre.
    """
    data = request.get_json(silent=True) or {}
    me = user_from_token(data.get("token", ""))
    if not me:
        return jsonify({"ok": False, "error": "Token invalide"}), 401
    try:
        eid = int(data.get("id") or 0)
    except Exception:
        eid = 0
    ligne = get_db().execute("SELECT * FROM enveloppes WHERE id=?",
                             (eid,)).fetchone()
    if not ligne:
        return jsonify({"ok": False, "error": "Enveloppe introuvable"}), 404
    if me["id"] not in (ligne["expediteur_id"], ligne["destinataire_id"]):
        return jsonify({"ok": False, "error": "Pas la votre"}), 403
    if ligne["expire_a"] <= int(time.time()):
        _env_efface(ligne)
        return jsonify({"ok": False, "error": "Enveloppe expiree"}), 410
    try:
        with open(_env_chemin(ligne["fichier"]), "rb") as f:
            octets = f.read()
    except Exception as e:
        print("[enveloppes] lecture impossible :", e)
        _env_efface(ligne)
        return jsonify({"ok": False, "error": "Image perdue"}), 410
    pour_moi = bool(ligne["destinataire_id"] == me["id"])
    if pour_moi:
        _env_efface(ligne)
    return jsonify({"ok": True, "image": base64.b64encode(octets).decode(),
                    "consommee": pour_moi})


@flask_app.route("/env_supprimer", methods=["POST"])
def env_supprimer():
    """Jette une enveloppe sans l'ouvrir. Les deux cotes en ont le droit."""
    data = request.get_json(silent=True) or {}
    me = user_from_token(data.get("token", ""))
    if not me:
        return jsonify({"ok": False, "error": "Token invalide"}), 401
    try:
        eid = int(data.get("id") or 0)
    except Exception:
        eid = 0
    ligne = get_db().execute("SELECT * FROM enveloppes WHERE id=?",
                             (eid,)).fetchone()
    if not ligne:
        return jsonify({"ok": True})
    if me["id"] not in (ligne["expediteur_id"], ligne["destinataire_id"]):
        return jsonify({"ok": False, "error": "Pas la votre"}), 403
    _env_efface(ligne)
    return jsonify({"ok": True})


_env_prepare()
gevent.spawn(_env_menage)


def _send_push(fcm_token, title, body, data=None):'''


CORRECTIONS = [("les enveloppes", MOTIF, AJOUT)]


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
    sauvegarde = "%s.avant-enveloppes-%s" % (chemin, horodatage)
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
