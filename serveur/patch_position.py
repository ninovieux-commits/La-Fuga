# -*- coding: utf-8 -*-
"""Le mode position personnalisee en correspondance, cote serveur.

Une partie de correspondance pouvait partir de deux endroits : la position de
toujours, ou une des positions tirees au sort (un code Random Fuga). Elle peut
maintenant partir d'une position COMPOSEE, decrite au format `.fug` sur une
seule ligne :

    B/sgshgsg/gnnnnns/---c---/-------/-------/---C---/GNNNNNS/SGSHGSG

La premiere lettre dit qui a le trait (`B` ou `N`), puis huit rangees de sept
caracteres, de do1 a si1 d'abord. Minuscule pour les Blancs, majuscule pour
les Noirs ; `h` Heritier, `n` Nurse, `c` Chevalier, `g` Garde, `s` Soldat,
`-` case vide.

CE QUI EST AJOUTE
    - colonnes mode / position / couleur sur corr_games
    - /corr_defier     : lit `mode`, `position`, `couleur` et les enregistre
    - /corr_repondre   : TIRE LA COULEUR a l'acceptation, quand elle est
                         aleatoire
    - _corr_game_dict  : renvoie `mode`, `position`, `couleur`
    - _archive_corr_game : ecrit `[Position "..."]` dans l'en-tete du .nmc

LE TRAIT VIENT DE LA POSITION. Une partie demarrait toujours aux Blancs. Une
position composee peut vouloir que les Noirs commencent : le `turn` de la
partie est donc lu dans la premiere lettre du `.fug`.

LE SERVEUR VERIFIE LA POSITION, il ne la croit pas. L'application la verifie
deja, mais c'est le serveur qui garde la partie : une position mal formee s'y
installerait pour de bon, et chaque client la relirait de travers. Les deux
regles de Nino sont donc appliquees ici aussi — un Heritier par camp, et des
carrees qui peuvent bouger des deux cotes. Elles ne demandent pas de connaitre
les regles du jeu : compter des lettres et regarder les voisines suffit.

LA COULEUR ALEATOIRE SE TIRE A L'ACCEPTATION. « Aucun des deux joueurs ne doit
savoir qui va avoir les blancs tant que la partie n'a pas demarre. » Un
serveur ne peut pas cacher ce qu'il a ecrit : il envoie `ma_couleur` avec
chaque defi, et le masquer demanderait un garde a chaque endroit qui le lit.
Il ne l'ecrit donc qu'une fois la partie partie. La repartition posee a la
creation reste provisoire et ne veut rien dire — elle est refaite au moment ou
le defi est accepte.

Le tirage a l'acceptation ne concerne QUE les defis venus d'une application
corrigee (celles-la portent un `mode`). Un defi lance par une ancienne
application garde exactement l'ancien comportement : sa couleur a ete tiree a
la creation, et elle ne change plus.

N'ENLEVE RIEN. Une partie standard se comporte comme avant : `mode` vaut
alors 'standard', `position` et `couleur` sont vides, et le trait reste aux
Blancs. Random Fuga n'est pas touche — son code continue de voyager dans
`random_code`.

USAGE
    python3 patch_position.py /chemin/vers/server.py

Le script REFUSE d'ecrire si un motif n'est pas trouve exactement une fois, y
compris sur un fichier deja corrige. Une sauvegarde horodatee est posee a
cote avant toute ecriture.
"""
import datetime
import hashlib
import io
import os
import shutil
import sys


# ── 1. Le schema : trois colonnes de plus ───────────────────────────────────
MOTIF_SCHEMA = '''    # Migration douce : code Random Fuga de la partie ('' = position standard).
    # Permet de jouer/relire/reconstruire la même position aléatoire des deux côtés.
    try:
        c.execute("ALTER TABLE corr_games ADD COLUMN random_code TEXT DEFAULT ''")
    except Exception:
        pass'''

REMPLACEMENT_SCHEMA = '''    # Migration douce : code Random Fuga de la partie ('' = position standard).
    # Permet de jouer/relire/reconstruire la même position aléatoire des deux côtés.
    try:
        c.execute("ALTER TABLE corr_games ADD COLUMN random_code TEXT DEFAULT ''")
    except Exception:
        pass
    # Migration douce : d'ou part la partie.
    #   mode     : '' (parties d'avant), 'standard', 'random', 'personnalise'
    #   position : la position composee, au format .fug sur une seule ligne
    #   couleur  : la couleur DEMANDEE PAR LE DEFIEUR ('' = aleatoire)
    # `mode` vide marque une partie creee avant ce patch : sa couleur a ete
    # tiree a la creation, et le tirage a l'acceptation ne la concerne pas.
    for _col in ("mode", "position", "couleur"):
        try:
            c.execute("ALTER TABLE corr_games ADD COLUMN %s TEXT DEFAULT ''" % _col)
        except Exception:
            pass'''


# ── 2. Lire et juger une position ───────────────────────────────────────────
# Place juste avant _archive_corr_game, qui en a besoin pour l'en-tete.
MOTIF_HELPERS = '''def _archive_corr_game(row, resultat, methode):'''

REMPLACEMENT_HELPERS = '''# ── Positions composees (.fug) ──────────────────────────────────────────────
# Le serveur ne connait pas les regles du jeu. Il n'en a pas besoin ici : lire
# une position, c'est compter des lettres, et les deux regles de validite se
# verifient en regardant les voisines d'une case.

# Sept colonnes (une par note), huit rangees jouables.
_FUG_COLS = 7
_FUG_RANGEES = 8

# Les carrees sont le Soldat et le Garde, et elles seules : le Chevalier bouge
# toujours, l'Heritier et la Nurse sont rondes.
_FUG_CARREES = "sg"


def _fug_lire(ligne):
    """Lit un .fug d'une ligne. Rend (grille, trait) ou None si mal forme.

    `grille[r][c]` porte la lettre telle qu'ecrite — la casse dit le camp —
    et la rangee 0 est do1..si1.
    """
    parties = (ligne or "").strip().split("/")
    if len(parties) != _FUG_RANGEES + 1:
        return None
    trait = parties[0].strip().upper()
    if trait not in ("B", "N"):
        return None
    grille = []
    for rangee in parties[1:]:
        if len(rangee) != _FUG_COLS:
            return None
        for ch in rangee:
            if ch != "-" and ch.lower() not in "hncgs":
                return None
        grille.append(rangee)
    return (grille, "Blanc" if trait == "B" else "Noir")


def _fug_carree_mobile(grille, majuscule):
    """Ce camp a-t-il une carree qui peut bouger ?

    Une carree ne bouge que si elle touche une autre carree, de n'importe quel
    camp, dans l'une des huit directions. Un camp dont aucune carree ne peut
    bouger ne peut rien entreprendre : la position serait nulle d'entree.
    """
    for r in range(_FUG_RANGEES):
        for c in range(_FUG_COLS):
            ch = grille[r][c]
            if ch.lower() not in _FUG_CARREES:
                continue
            if (ch == ch.upper()) != majuscule:
                continue
            for dr in (-1, 0, 1):
                for dc in (-1, 0, 1):
                    if dr == 0 and dc == 0:
                        continue
                    vr, vc = r + dr, c + dc
                    if not (0 <= vr < _FUG_RANGEES and 0 <= vc < _FUG_COLS):
                        continue
                    if grille[vr][vc].lower() in _FUG_CARREES:
                        return True
    return False


def _fug_refus(grille):
    """Pourquoi cette position ne peut pas servir de depart, ou None.

    Les deux regles de Nino, et elles seules : un Heritier par camp, et des
    carrees qui peuvent bouger des deux cotes. Pour le reste on ne juge rien —
    dix Gardes d'un cote, c'est permis.
    """
    plat = "".join(grille)
    if plat.count("h") != 1 or plat.count("H") != 1:
        return "heritier"
    for majuscule in (False, True):
        if not _fug_carree_mobile(grille, majuscule):
            return "carrees"
    return None


def _corr_tirage_a_lacceptation(row):
    """La couleur de cette partie reste-t-elle a tirer ?

    Oui quand le defieur a demande « aleatoire » (`couleur` vide) ET que son
    application a envoye un `mode` : c'est a dire qu'elle sait que personne ne
    doit connaitre sa couleur avant le depart. Un defi d'une ancienne
    application n'a pas de mode et garde sa couleur de creation.
    """
    cles = row.keys()
    mode = (row["mode"] if "mode" in cles else "") or ""
    couleur = (row["couleur"] if "couleur" in cles else "") or ""
    return bool(mode) and not couleur


def _corr_mode_lu(row):
    """Le mode de cette partie, toujours un mot que le client comprend.

    Les parties d'avant n'ont pas de mode : il se deduit alors du code Random
    Fuga, exactement comme le client le faisait de son cote.
    """
    cles = row.keys()
    mode = (row["mode"] if "mode" in cles else "") or ""
    if mode:
        return mode
    rcode = (row["random_code"] if "random_code" in cles else "") or ""
    return "random" if rcode else "standard"


def _archive_corr_game(row, resultat, methode):'''


# ── 3. L'archive .nmc garde la position ─────────────────────────────────────
MOTIF_ARCHIVE = '''    rcode = row["random_code"] if "random_code" in row.keys() else ""
    if rcode:
        header += '[Random "%s"]\\n' % rcode
    header += "\\n"'''

REMPLACEMENT_ARCHIVE = '''    rcode = row["random_code"] if "random_code" in row.keys() else ""
    if rcode:
        header += '[Random "%s"]\\n' % rcode
    # Position composee : sans elle, la partie se rejouerait depuis la position
    # standard — c'est-a-dire n'importe quoi. Le code Random tient en six
    # caracteres, une position en soixante-trois : c'est la meme idee, en plus
    # long.
    pos = (row["position"] if "position" in row.keys() else "") or ""
    if pos:
        header += '[Position "%s"]\\n' % pos
    header += "\\n"'''


# ── 4. Ce que le client recoit ──────────────────────────────────────────────
MOTIF_DICT = '''        "random_code": (row["random_code"] if "random_code" in row.keys() else "") or "",
        "updated_at": row["updated_at"],
    }'''

REMPLACEMENT_DICT = '''        "random_code": (row["random_code"] if "random_code" in row.keys() else "") or "",
        # D'ou part la partie. `couleur` est celle que le DEFIEUR a demandee ;
        # vide, elle veut dire aleatoire, et le client affiche « Aleatoire »
        # jusqu'au depart. Celle qu'on joue vraiment est `ma_couleur`.
        "mode": _corr_mode_lu(row),
        "position": (row["position"] if "position" in row.keys() else "") or "",
        "couleur": (row["couleur"] if "couleur" in row.keys() else "") or "",
        "updated_at": row["updated_at"],
    }'''


# ── 5. Le defi : lire le mode, la position, la couleur ──────────────────────
MOTIF_DEFIER = '''    pseudo = (data.get("pseudo") or "").strip()
    objectif = data.get("objectif", "partie")
    # Random Fuga : si le défieur est en mode random, tirer un code (commun aux
    # deux joueurs). '' = partie standard.
    rcode = _rf_random_code() if bool(data.get("random", False)) else ""'''

REMPLACEMENT_DEFIER = '''    pseudo = (data.get("pseudo") or "").strip()
    objectif = data.get("objectif", "partie")
    # D'ou part la partie.
    #
    # Une ANCIENNE application n'envoie pas de `mode` : on n'en invente pas un
    # pour elle, et la colonne reste vide. C'est a ca qu'on reconnait ses
    # parties, et elles gardent exactement l'ancien comportement — couleur
    # tiree ici, a la creation. Le client Kivy oriente en effet l'apercu d'un
    # defi selon la couleur recue : la lui changer a l'acceptation retournerait
    # son plateau sous ses yeux.
    mode = (data.get("mode") or "").strip()
    if mode not in ("standard", "random", "personnalise"):
        mode = ""
    position = (data.get("position") or "").strip()
    couleur = (data.get("couleur") or "").strip()
    if couleur not in ("Blanc", "Noir"):
        couleur = ""          # aleatoire : le tirage aura lieu a l'acceptation
    # Random Fuga : si le défieur est en mode random, tirer un code (commun aux
    # deux joueurs). '' = partie standard. Une position composee n'en a pas :
    # elle EST la position de depart, un code en plus la contredirait.
    rcode = ("" if mode == "personnalise"
             else (_rf_random_code()
                   if (mode == "random" or bool(data.get("random", False)))
                   else ""))
    # Le trait vient de la position : une position composee peut vouloir que
    # les Noirs commencent. Partout ailleurs, ce sont les Blancs.
    trait = "Blanc"
    if mode == "personnalise":
        lu = _fug_lire(position)
        if lu is None:
            return jsonify({"ok": False, "error": "position_illisible",
                            "message": "Position illisible"}), 400
        grille, trait = lu
        refus = _fug_refus(grille)
        if refus is not None:
            return jsonify({"ok": False, "error": "position_%s" % refus,
                            "message": "Position invalide"}), 400
    else:
        position = ""         # une position n'a de sens qu'en personnalise'''


MOTIF_TIRAGE = '''    # Couleur aléatoire
    import random
    if random.random() < 0.5:
        bu, bp, nu, np_ = me["id"], me["pseudo"], cible["id"], cible["pseudo"]
    else:
        bu, bp, nu, np_ = cible["id"], cible["pseudo"], me["id"], me["pseudo"]'''

REMPLACEMENT_TIRAGE = '''    # La couleur demandee par le defieur, quand il en a demande une.
    #
    # Sinon, repartition PROVISOIRE : le vrai tirage a lieu a l'acceptation,
    # pour que personne ne connaisse sa couleur avant le depart. Ce qui est
    # ecrit ici ne veut donc rien dire, et c'est voulu — le serveur n'a pas a
    # cacher un secret qu'il n'a pas encore fabrique.
    import random
    if couleur == "Blanc":
        bu, bp, nu, np_ = me["id"], me["pseudo"], cible["id"], cible["pseudo"]
    elif couleur == "Noir":
        bu, bp, nu, np_ = cible["id"], cible["pseudo"], me["id"], me["pseudo"]
    elif random.random() < 0.5:
        bu, bp, nu, np_ = me["id"], me["pseudo"], cible["id"], cible["pseudo"]
    else:
        bu, bp, nu, np_ = cible["id"], cible["pseudo"], me["id"], me["pseudo"]'''


MOTIF_INSERT = '''    cur.execute(
        "INSERT INTO corr_games (blanc_user_id, noir_user_id, blanc_pseudo, "
        "noir_pseudo, defieur_user_id, objectif, statut, turn, moves_text, "
        "random_code, created_at, updated_at) "
        "VALUES (?,?,?,?,?,?,'defi','Blanc','',?,?,?)",
        (bu, nu, bp, np_, me["id"], objectif, rcode, now, now))'''

REMPLACEMENT_INSERT = '''    cur.execute(
        "INSERT INTO corr_games (blanc_user_id, noir_user_id, blanc_pseudo, "
        "noir_pseudo, defieur_user_id, objectif, statut, turn, moves_text, "
        "random_code, mode, position, couleur, created_at, updated_at) "
        "VALUES (?,?,?,?,?,?,'defi',?,'',?,?,?,?,?,?)",
        (bu, nu, bp, np_, me["id"], objectif, trait, rcode, mode, position,
         couleur, now, now))'''


# ── 6. L'acceptation : le tirage de la couleur ──────────────────────────────
MOTIF_ACCEPTE = '''    if accepte:
        conn.execute("UPDATE corr_games SET statut='en_cours', updated_at=? "
                     "WHERE id=?", (int(time.time()), gid))
    else:'''

REMPLACEMENT_ACCEPTE = '''    blanc_uid = row["blanc_user_id"]
    if accepte:
        now = int(time.time())
        if _corr_tirage_a_lacceptation(row):
            # LE TIRAGE A LIEU MAINTENANT. La partie demarre : c'est le premier
            # instant ou l'on a le droit de savoir qui a les Blancs. Jusqu'ici,
            # la repartition en base etait provisoire.
            #
            # Les deux joueurs sont deja dans la ligne, l'un des deux est le
            # defieur ; on les reprend par la pour ne pas relire users.
            import random as _rnd
            if row["blanc_user_id"] == row["defieur_user_id"]:
                d_uid, d_ps = row["blanc_user_id"], row["blanc_pseudo"]
                o_uid, o_ps = row["noir_user_id"], row["noir_pseudo"]
            else:
                d_uid, d_ps = row["noir_user_id"], row["noir_pseudo"]
                o_uid, o_ps = row["blanc_user_id"], row["blanc_pseudo"]
            if _rnd.random() < 0.5:
                bu, bp, nu, np_ = d_uid, d_ps, o_uid, o_ps
            else:
                bu, bp, nu, np_ = o_uid, o_ps, d_uid, d_ps
            conn.execute("UPDATE corr_games SET statut='en_cours', "
                         "blanc_user_id=?, noir_user_id=?, blanc_pseudo=?, "
                         "noir_pseudo=?, updated_at=? WHERE id=?",
                         (bu, nu, bp, np_, now, gid))
            blanc_uid = bu
        else:
            conn.execute("UPDATE corr_games SET statut='en_cours', updated_at=? "
                         "WHERE id=?", (now, gid))
    else:'''


MOTIF_NOTIF = '''            blanc_uid = row["blanc_user_id"]
            if blanc_uid and blanc_uid != me["id"]:'''

REMPLACEMENT_NOTIF = '''            # `blanc_uid` vient du tirage ci-dessus quand il a eu lieu : la
            # ligne relue n'aurait plus la bonne couleur.
            if blanc_uid and blanc_uid != me["id"]:'''


CORRECTIONS = [
    ("schema : mode / position / couleur", MOTIF_SCHEMA, REMPLACEMENT_SCHEMA),
    ("lecture d'une position .fug", MOTIF_HELPERS, REMPLACEMENT_HELPERS),
    ("archive .nmc : [Position]", MOTIF_ARCHIVE, REMPLACEMENT_ARCHIVE),
    ("dict client : mode / position / couleur", MOTIF_DICT, REMPLACEMENT_DICT),
    ("/corr_defier : lecture du mode", MOTIF_DEFIER, REMPLACEMENT_DEFIER),
    ("/corr_defier : couleur demandee", MOTIF_TIRAGE, REMPLACEMENT_TIRAGE),
    ("/corr_defier : insertion", MOTIF_INSERT, REMPLACEMENT_INSERT),
    ("/corr_repondre : tirage a l'acceptation", MOTIF_ACCEPTE,
     REMPLACEMENT_ACCEPTE),
    ("/corr_repondre : notification des Blancs", MOTIF_NOTIF,
     REMPLACEMENT_NOTIF),
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
    sauvegarde = "%s.avant-position-%s" % (chemin, horodatage)
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
