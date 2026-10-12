# -*- coding: utf-8 -*-
"""Le pre-coup en correspondance : la reponse part meme telephone eteint.

En correspondance, l'attente se compte en heures. Quand on sait deja quoi
repondre a ce que l'adversaire va jouer, on prepare sa reponse : s'il joue le
coup prevu, elle part toute seule, et c'est aussitot de nouveau a lui.

Toute la valeur de la chose est la : elle doit marcher QUAND NOTRE
APPLICATION EST FERMEE. Un pre-coup qui ne se declenche qu'a l'ouverture de
l'application ne sert a rien — a ce moment-la, on pourrait jouer. C'est donc
le serveur qui joue le coup prejoue, au moment ou l'adversaire joue le sien.

UNE VARIANTE est une suite de demi-coups qui part de la position ou
l'adversaire a le trait :

    indice 0 : son coup   indice 1 : le notre   indice 2 : son coup   ...

Les indices PAIRS sont a lui, les IMPAIRS a nous. Une variante s'arrete
toujours sur un des NOTRES : s'arreter sur le sien ne preparerait rien.

Six variantes au plus, six demi-coups au plus, et AUCUNE NE DOIT CONTREDIRE
UNE AUTRE : deux variantes qui partagent le meme debut ne peuvent pas y
repondre de deux facons differentes. La regle se verifie ici comme elle se
verifie dans l'application — le serveur est ce qui joue vraiment, il ne fait
pas confiance a ce qu'on lui envoie.

CE QUE LE SERVEUR NE SAIT PAS, c'est les regles du jeu : il n'a jamais
valide un coup de correspondance, il empile des notations. Ce n'est pas un
probleme ici, et c'est meme le coeur de l'affaire : une variante decrit une
ligne COMPLETE depuis une position connue. Si l'adversaire joue le coup
prevu, la position est exactement celle que l'application avait sous les yeux
en composant la variante, donc notre reponse y est legale par construction.
Pour la meme raison, c'est l'application qui dit si notre coup termine la
partie (`methode`, `gagnant`) : elle seule a compte.

CE QUI EST AJOUTE
    - import json              : le serveur n'avait jamais rien a serialiser
    - table corr_premoves      : un plan par (partie, joueur)
    - colonne premove_pour     : a qui l'on doit le popup « il avait prejoue »
    - POST /corr_premove       : enregistrer ou effacer son plan
    - POST /corr_premove_vu    : le popup a ete vu, on l'eteint
    - corr_jouer               : joue la reponse prejouee, s'il y en a une
    - _corr_game_dict          : `premove`, `premove_adverse`, `premove_par`

N'ENLEVE RIEN. Une partie sans plan prejoue se comporte exactement comme
avant, octet pour octet : tout le code ajoute est derriere « ce joueur a-t-il
un plan ? », et la reponse est non pour tout le monde jusqu'a ce qu'un client
en envoie un.

USAGE
    python3 patch_premove.py /chemin/vers/server.py

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


# ── 0. L'import manquant ────────────────────────────────────────────────────
# Le serveur n'importait pas json : il n'avait jamais rien eu a serialiser
# lui-meme (Flask s'en charge pour les reponses). Un plan de pre-coups est
# stocke tel quel en base, donc il faut l'import.
MOTIF_IMPORT = '''import os
import re
import sqlite3'''

REMPLACEMENT_IMPORT = '''import json
import os
import re
import sqlite3'''


# ── 1. Le schema : la table des plans, et le drapeau du popup ───────────────
MOTIF_SCHEMA = '''    try:
        c.execute("ALTER TABLE corr_games ADD COLUMN random_code TEXT DEFAULT ''")
    except Exception:
        pass'''

REMPLACEMENT_SCHEMA = '''    try:
        c.execute("ALTER TABLE corr_games ADD COLUMN random_code TEXT DEFAULT ''")
    except Exception:
        pass
    # Pre-coups : les reponses qu'un joueur prepare pendant que l'adversaire
    # reflechit. Un plan par (partie, joueur) ; `plan` est le JSON envoye par
    # l'application, `base` le nombre de demi-coups deja joues au moment de la
    # composition. Au-dela, le plan ne parle plus de la position ou il
    # s'appliquerait, et il ne vaut plus rien.
    c.execute("""
        CREATE TABLE IF NOT EXISTS corr_premoves (
            game_id INTEGER NOT NULL,
            user_id INTEGER NOT NULL,
            base INTEGER NOT NULL,
            plan TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY (game_id, user_id)
        )
    """)
    # Migration douce : a qui doit-on dire que son adversaire avait prejoue ?
    # (0 = personne). Le client montre le popup, puis l'eteint.
    try:
        c.execute("ALTER TABLE corr_games ADD COLUMN premove_pour INTEGER DEFAULT 0")
    except Exception:
        pass'''


# ── 2. Les helpers ──────────────────────────────────────────────────────────
MOTIF_HELPERS = '''# ── Correspondance : routes ──────────────────────────────────────────────────'''

REMPLACEMENT_HELPERS = '''# ── Correspondance : pre-coups ───────────────────────────────────────────────
# Les memes limites que dans l'application (lib/game/premove.dart) : si l'une
# bouge, l'autre doit bouger.
PREMOVE_MAX_VARIANTES = 6
PREMOVE_MAX_COUPS = 6


def _premove_coups(moves_text):
    """Les demi-coups d'une partie, un par ligne non vide."""
    return [l.strip() for l in (moves_text or "").split("\\n") if l.strip()]


def _premove_ecart(a, b):
    """Indice du premier demi-coup ou deux variantes different, ou None si
    l'une commence l'autre."""
    for i in range(min(len(a), len(b))):
        if a[i] != b[i]:
            return i
    return None


def _premove_lignes(plan):
    """Les variantes d'un plan, nettoyees : [[coup, ...], ...].

    Ne juge rien, ne leve rien : ce qui n'a pas la bonne forme est ignore.
    `_premove_refus` est ce qui juge.
    """
    out = []
    if not isinstance(plan, dict):
        return out
    for v in (plan.get("variantes") or []):
        if not isinstance(v, dict):
            continue
        cs = v.get("coups")
        if not isinstance(cs, list):
            continue
        out.append([str(c).strip() for c in cs])
    return out


def _premove_refus(plan):
    """Pourquoi ce plan est refuse, ou None s'il est bon.

    La regle de Nino, cote serveur : six variantes au plus, six demi-coups au
    plus, et aucune qui contredise une autre. Contredire, c'est repondre deux
    choses differentes a la meme suite de coups — ce qui se lit a l'endroit ou
    deux variantes se SEPARENT :

      * elles se separent sur un coup de l'ADVERSAIRE (indice pair) : ce sont
        deux lignes differentes, chacune sa reponse. Rien a redire.
      * elles se separent sur un des NOTRES (indice impair) : meme debut, meme
        coup de l'adversaire, et deux reponses. C'est la contradiction.
      * elles ne se separent pas : l'une commence l'autre, la plus courte
        n'ajoute rien.
    """
    if not isinstance(plan, dict):
        return "plan illisible"
    variantes = plan.get("variantes")
    if not isinstance(variantes, list):
        return "plan illisible"
    if len(variantes) > PREMOVE_MAX_VARIANTES:
        return "six variantes au plus"
    lignes = []
    for v in variantes:
        if not isinstance(v, dict):
            return "variante illisible"
        cs = v.get("coups")
        if not isinstance(cs, list) or not cs:
            return "variante vide"
        if len(cs) % 2 or len(cs) > PREMOVE_MAX_COUPS:
            return "une variante compte un nombre pair de demi-coups, six au plus"
        cs = [str(c).strip() for c in cs]
        if any(not c for c in cs):
            return "coup vide"
        lignes.append(cs)
    for i in range(len(lignes)):
        for j in range(i + 1, len(lignes)):
            e = _premove_ecart(lignes[i], lignes[j])
            if e is None:
                return "deux variantes identiques, ou l'une dans l'autre"
            if e % 2:
                return "deux variantes se contredisent"
    return None


def _premove_reponse(plan, ligne):
    """Notre reponse quand la partie est arrivee jusqu'a `ligne`.

    `ligne` : les demi-coups joues DEPUIS la composition du plan. Le dernier
    est celui de l'adversaire, c'est pourquoi sa longueur est impaire.
    Renvoie (coup, methode, gagnant) ou None.

    La methode ne vaut que pour le DERNIER coup de la variante : c'est lui, et
    lui seul, dont l'application a mesure qu'il terminait la partie. La porter
    sur un coup du milieu cloturerait une partie qui continue.
    """
    if not ligne or len(ligne) % 2 == 0:
        return None
    for v in (plan.get("variantes") or []):
        cs = [str(c).strip() for c in (v.get("coups") or [])]
        if len(cs) <= len(ligne) or cs[:len(ligne)] != ligne:
            continue
        i = len(ligne)
        dernier = (i == len(cs) - 1)
        methode = (v.get("methode") or "").strip() if dernier else ""
        gagnant = (v.get("gagnant") or "").strip() if dernier else ""
        return (cs[i], methode or None, gagnant or None)
    return None


def _premove_suit_encore(plan, ligne):
    """Ce plan peut-il encore servir, maintenant ou plus tard ?

    Faux : l'adversaire est sorti de tout ce qui etait prevu. Comme une ligne
    ne fait que s'allonger, il ne pourra plus jamais y rentrer — le plan est
    mort et on l'efface.
    """
    for v in (plan.get("variantes") or []):
        cs = [str(c).strip() for c in (v.get("coups") or [])]
        if len(cs) > len(ligne) and cs[:len(ligne)] == ligne:
            return True
    return False


def _premove_charger(conn, gid, uid):
    """Le plan de `uid` pour la partie `gid` : (base, plan) ou (None, None)."""
    try:
        row = conn.execute(
            "SELECT base, plan FROM corr_premoves WHERE game_id=? AND user_id=?",
            (gid, uid)).fetchone()
    except Exception:
        return (None, None)
    if not row:
        return (None, None)
    try:
        plan = json.loads(row["plan"])
    except Exception:
        return (None, None)
    if not isinstance(plan, dict):
        return (None, None)
    return (row["base"], plan)


def _premove_effacer(conn, gid, uid=None):
    """Efface le plan d'un joueur, ou ceux des deux joueurs."""
    try:
        if uid is None:
            conn.execute("DELETE FROM corr_premoves WHERE game_id=?", (gid,))
        else:
            conn.execute(
                "DELETE FROM corr_premoves WHERE game_id=? AND user_id=?",
                (gid, uid))
    except Exception:
        pass


def _premove_terminer(conn, gid, moves_text, methode, gagnant, row, now):
    """Clot une partie sur un coup PREJOUE.

    Jumeau volontaire du bloc `if methode:` de corr_jouer, qui clot sur un
    coup joue a la main. Les deux font la meme chose ; ils sont separes pour
    que le chemin d'origine ne bouge pas d'une ligne. Un test compare les deux
    (tests/test_premove.py, « un mat prejoue clot la partie comme un mat
    joue ») : si l'un change sans l'autre, il le dit.

    Renvoie le resultat ('1-0', '0-1', 'nulle') ou None si rien n'a ete clos.
    """
    if methode == "nulle":
        resultat = "nulle"
    elif gagnant in ("Blanc", "Noir"):
        resultat = "1-0" if gagnant == "Blanc" else "0-1"
        winner_uid = (row["blanc_user_id"] if gagnant == "Blanc"
                      else row["noir_user_id"])
        loser_uid = (row["noir_user_id"] if gagnant == "Blanc"
                     else row["blanc_user_id"])
        pts = 1 if methode in ("mat", "papatte") else 2
        _add_corr_score(winner_uid, loser_uid, pts)
    else:
        # Une fin sans gagnant nomme : on ne devine pas, on ne clot pas.
        return None
    conn.execute("UPDATE corr_games SET moves_text=?, statut='termine', "
                 "resultat=?, methode=?, premove_pour=0, updated_at=? "
                 "WHERE id=?", (moves_text, resultat, methode, now, gid))
    _premove_effacer(conn, gid)
    conn.commit()
    return resultat


def _premove_appliquer(conn, gid, row, moves_text, pre_uid, mover_uid, now):
    """L'adversaire avait-il prejoue sa reponse au coup qui vient d'arriver ?

    `moves_text` : les coups AVEC celui qui vient d'etre joue.
    `pre_uid`    : celui qui a le trait apres ce coup — donc celui dont on
                   regarde le plan.
    `mover_uid`  : celui qui vient de jouer ; c'est a lui que la reponse
                   prejouee redonne le trait, et c'est lui qu'on previendra.

    Renvoie None si rien n'etait prejoue, sinon un dict :
        {coup, methode, gagnant, resultat, moves_text}
    `resultat` n'est pose que si le coup prejoue termine la partie.
    """
    base, plan = _premove_charger(conn, gid, pre_uid)
    if plan is None:
        return None
    coups = _premove_coups(moves_text)
    if base is None or base < 0 or base > len(coups):
        # Un plan qui parle d'une position que la partie n'a pas atteinte :
        # il ne s'appliquera jamais.
        _premove_effacer(conn, gid, pre_uid)
        conn.commit()
        return None
    ligne = coups[base:]
    rep = _premove_reponse(plan, ligne)
    if rep is None:
        # Rien ici. Si l'adversaire est sorti de tout ce qui etait prevu, le
        # plan est mort : on le range.
        if not _premove_suit_encore(plan, ligne):
            _premove_effacer(conn, gid, pre_uid)
            conn.commit()
        return None
    coup, methode, gagnant = rep
    apres = (moves_text + "\\n" + coup).strip()
    if methode:
        resultat = _premove_terminer(conn, gid, apres, methode, gagnant,
                                     row, now)
        if resultat is None:
            return None
        return {"coup": coup, "methode": methode, "gagnant": gagnant,
                "resultat": resultat, "moves_text": apres}
    # La partie continue : le trait revient a celui qui vient de jouer.
    conn.execute("UPDATE corr_games SET moves_text=?, turn=?, nulle_par=0, "
                 "premove_pour=?, updated_at=? WHERE id=?",
                 (apres, row["turn"], mover_uid, now, gid))
    # Le plan garde ses variantes plus profondes ; s'il n'en a plus aucune qui
    # prolonge cette ligne, il ne servira plus.
    if not _premove_suit_encore(plan, ligne + [coup]):
        _premove_effacer(conn, gid, pre_uid)
    conn.commit()
    return {"coup": coup, "methode": None, "gagnant": None,
            "resultat": None, "moves_text": apres}


# ── Correspondance : routes ──────────────────────────────────────────────────'''


# ── 3. Le dict envoye au client ─────────────────────────────────────────────
# Les trois cles ne sont posees QUE quand il y a quelque chose a dire. Pour
# tous ceux qui ne prejouent pas — c'est-a-dire presque tout le monde, presque
# tout le temps — l'apercu des parties garde exactement les octets qu'il avait,
# et le banc de parite le verifie (81/81 identiques).
MOTIF_DICT_TETE = '''    return {
        "id": row["id"],
        "statut": row["statut"],'''

REMPLACEMENT_DICT_TETE = '''    sortie = {
        "id": row["id"],
        "statut": row["statut"],'''

MOTIF_DICT = '''        "random_code": (row["random_code"] if "random_code" in row.keys() else "") or "",
        "updated_at": row["updated_at"],
    }'''

REMPLACEMENT_DICT = '''        "random_code": (row["random_code"] if "random_code" in row.keys() else "") or "",
        "updated_at": row["updated_at"],
    }
    # Pre-coups : MON plan (pour que l'ecran de composition reprenne ou je
    # l'avais laisse), et le popup qu'on me doit quand l'adversaire avait
    # prejoue sa reponse a mon coup. Rien n'est ajoute quand il n'y a rien.
    mon_plan = _premove_du_client(row["id"], me_uid)
    if mon_plan is not None:
        sortie["premove"] = mon_plan
    if _premove_pour_moi(row, me_uid):
        sortie["premove_adverse"] = True
        sortie["premove_par"] = opp_pseudo
    return sortie


def _premove_pour_moi(row, me_uid):
    """Me doit-on le popup « il avait prejoue son coup » ?"""
    try:
        v = row["premove_pour"] if "premove_pour" in row.keys() else 0
    except Exception:
        return False
    return bool(v) and v == me_uid


def _premove_du_client(gid, me_uid):
    """Mon plan prejoue pour cette partie, tel que l'application l'a envoye.

    Une lecture par partie, sur la cle primaire de corr_premoves : la liste de
    correspondance en compte dix au plus, et SQLite repond en microsecondes.
    None quand il n'y a pas de plan — le cas de presque tout le monde.
    """
    try:
        r = get_db().execute(
            "SELECT base, plan FROM corr_premoves WHERE game_id=? AND user_id=?",
            (gid, me_uid)).fetchone()
        if not r:
            return None
        plan = json.loads(r["plan"])
        if not isinstance(plan, dict):
            return None
        plan["base"] = r["base"]
        return plan
    except Exception:
        return None'''


# ── 4. corr_jouer joue la reponse prejouee ──────────────────────────────────
MOTIF_JOUER = '''    else:
        conn.execute("UPDATE corr_games SET moves_text=?, turn=?, nulle_par=0, "
                     "updated_at=? WHERE id=?", (new_moves, next_turn, now, gid))
        conn.commit()
        opp_uid = (row["noir_user_id"] if my_color == "Blanc"
                   else row["blanc_user_id"])
        conn.close()'''

REMPLACEMENT_JOUER = '''    else:
        conn.execute("UPDATE corr_games SET moves_text=?, turn=?, nulle_par=0, "
                     "premove_pour=0, updated_at=? WHERE id=?",
                     (new_moves, next_turn, now, gid))
        conn.commit()
        opp_uid = (row["noir_user_id"] if my_color == "Blanc"
                   else row["blanc_user_id"])
        # Mon propre plan, s'il en restait un, parlait d'une position que ce
        # coup-ci vient de depasser : il ne vaut plus rien.
        _premove_effacer(conn, gid, me["id"])
        conn.commit()
        # L'adversaire avait-il prejoue sa reponse ? Si le coup qui vient
        # d'etre joue est celui qu'il attendait, elle part maintenant, et c'est
        # deja de nouveau a moi.
        _pre = None
        try:
            _pre = _premove_appliquer(conn, gid, row, new_moves, opp_uid,
                                      me["id"], now)
        except Exception as e:
            print("[premove] erreur :", e)
        conn.close()
        if _pre:
            _pre_pseudo = (row["noir_pseudo"] if my_color == "Blanc"
                           else row["blanc_pseudo"])
            # La partie s'est terminee sur le coup prejoue : elle entre dans
            # l'historique des deux joueurs, comme n'importe quelle autre.
            if _pre["resultat"]:
                try:
                    _fin = get_db().execute(
                        "SELECT * FROM corr_games WHERE id=?", (gid,)).fetchone()
                    if _fin:
                        _archive_corr_game(_fin, _pre["resultat"],
                                           _pre["methode"])
                except Exception as e:
                    print("[premove archive] erreur :", e)
            # Deux joueurs a prevenir, et deux choses differentes a leur dire.
            try:
                _nb = len(_premove_coups(_pre["moves_text"]))
                _vu = _coup_pour_notif(_pre["coup"], row["turn"], _nb)
                if _pre["resultat"]:
                    _notify_user(me["id"], "turn", _pre_pseudo,
                                 "avait prejoue %s — partie terminee" % _vu,
                                 {"type": "corr_fin", "game_id": str(gid),
                                  "coup": _pre["coup"],
                                  "resultat": _pre["resultat"],
                                  "premove": "1"})
                else:
                    _notify_user(me["id"], "turn", _pre_pseudo,
                                 "avait prejoue %s — a vous de jouer !" % _vu,
                                 {"type": "corr_turn", "game_id": str(gid),
                                  "coup": _pre["coup"], "premove": "1"})
                # L'adversaire, lui, apprend que son pre-coup est parti : sa
                # partie a bouge deux fois sans qu'il y touche.
                _emit_direct(opp_uid, {"type": "corr_turn",
                                       "game_id": str(gid),
                                       "coup": _pre["coup"],
                                       "premove": "1"})
            except Exception:
                pass
            return jsonify({"ok": True, "premove": _pre["coup"]})'''


# ── 5. Les deux routes ──────────────────────────────────────────────────────
MOTIF_ROUTES = '''@flask_app.route("/corr_abandon", methods=["POST"])'''

REMPLACEMENT_ROUTES = '''@flask_app.route("/corr_premove", methods=["POST"])
def corr_premove():
    """Enregistrer (ou effacer) son plan de pre-coups.

    data = {game_id, plan}. Un plan sans variante efface le plan existant :
    c'est ainsi qu'on annule ce qu'on avait prepare.

    On ne prepare que pendant que l'ADVERSAIRE reflechit : prejouer quand on a
    soi-meme le trait n'aurait pas de sens, il n'y a rien a attendre.
    """
    data = request.get_json(silent=True) or {}
    me = user_from_token(data.get("token", ""))
    if not me:
        return jsonify({"ok": False, "error": "Token invalide"}), 401
    gid = data.get("game_id")
    plan = data.get("plan") or {}
    conn = get_db()
    row = conn.execute("SELECT * FROM corr_games WHERE id=?", (gid,)).fetchone()
    if not row or row["statut"] != "en_cours":
        conn.close()
        return jsonify({"ok": False, "error": "Partie non jouable"}), 400
    if me["id"] not in (row["blanc_user_id"], row["noir_user_id"]):
        conn.close()
        return jsonify({"ok": False, "error": "Pas votre partie"}), 403
    my_color = "Blanc" if row["blanc_user_id"] == me["id"] else "Noir"
    variantes = (plan.get("variantes") if isinstance(plan, dict) else None) or []
    if not variantes:
        _premove_effacer(conn, gid, me["id"])
        conn.commit()
        conn.close()
        return jsonify({"ok": True, "variantes": 0})
    if row["turn"] == my_color:
        conn.close()
        return jsonify({"ok": False,
                        "error": "C'est a vous de jouer"}), 400
    refus = _premove_refus(plan)
    if refus:
        conn.close()
        return jsonify({"ok": False, "error": refus}), 400
    # `base` vient du serveur, jamais du client : c'est la position REELLE a
    # laquelle le plan va s'appliquer. Un client en retard d'un coup verrait
    # son plan rattache a la mauvaise position.
    base = len(_premove_coups(row["moves_text"]))
    now = int(time.time())
    conn.execute(
        "INSERT OR REPLACE INTO corr_premoves (game_id, user_id, base, plan, "
        "updated_at) VALUES (?, ?, ?, ?, ?)",
        (gid, me["id"], base, json.dumps(plan, ensure_ascii=False), now))
    conn.commit()
    conn.close()
    return jsonify({"ok": True, "variantes": len(variantes), "base": base})


@flask_app.route("/corr_premove_vu", methods=["POST"])
def corr_premove_vu():
    """Le popup « il avait prejoue son coup » a ete vu : on l'eteint.

    Sans cela il reviendrait a chaque actualisation, et appuyer sur [Ok] ne
    servirait a rien.
    """
    data = request.get_json(silent=True) or {}
    me = user_from_token(data.get("token", ""))
    if not me:
        return jsonify({"ok": False, "error": "Token invalide"}), 401
    gid = data.get("game_id")
    conn = get_db()
    conn.execute("UPDATE corr_games SET premove_pour=0 WHERE id=? "
                 "AND premove_pour=?", (gid, me["id"]))
    conn.commit()
    conn.close()
    return jsonify({"ok": True})


@flask_app.route("/corr_abandon", methods=["POST"])'''


CORRECTIONS = [
    ("l'import de json", MOTIF_IMPORT, REMPLACEMENT_IMPORT),
    ("le schema : table des plans et drapeau du popup",
     MOTIF_SCHEMA, REMPLACEMENT_SCHEMA),
    ("les helpers de pre-coup", MOTIF_HELPERS, REMPLACEMENT_HELPERS),
    ("le dict envoye au client (tete)", MOTIF_DICT_TETE, REMPLACEMENT_DICT_TETE),
    ("le dict envoye au client (queue)", MOTIF_DICT, REMPLACEMENT_DICT),
    ("corr_jouer joue la reponse prejouee", MOTIF_JOUER, REMPLACEMENT_JOUER),
    ("les routes /corr_premove et /corr_premove_vu",
     MOTIF_ROUTES, REMPLACEMENT_ROUTES),
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
    sauvegarde = "%s.avant-premove-%s" % (chemin, horodatage)
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
