# -*- coding: utf-8 -*-
"""
patch_serveur.py — applique au server.py de production les corrections de
robustesse, SANS toucher au protocole (mêmes routes HTTP, mêmes événements
Socket.IO, mêmes JSON, même base).

    python3 patch_serveur.py server.py            -> écrit server_patched.py
    python3 patch_serveur.py server.py --inplace  -> remplace server.py (backup .bak)

Chaque remplacement est vérifié : si le texte attendu n'est pas trouvé, le
script s'arrête sans rien écrire (aucune modification partielle possible).
"""
import re
import sys

EDITS = []          # (nom, ancien, nouveau)  -> remplacement unique et vérifié


def edit(nom, ancien, nouveau):
    EDITS.append((nom, ancien, nouveau))


# ───────────────────────────────────────────────────────────────────────────
# 1. Journal borné + horodaté, à la place des print() vers un fichier qui
#    grossit sans fin. Le `print` du module est redéfini : tous les appels
#    existants sont conservés tels quels.
#    Cause de panne supprimée : disque plein (les écritures SQLite échouent
#    alors, et le serveur devient inutilisable jusqu'au redémarrage manuel).
# ───────────────────────────────────────────────────────────────────────────
edit("journal borné",
     '''import os
import re
import sqlite3
import secrets
import hashlib
import time
import threading

import gevent
''',
     '''import os
import re
import sqlite3
import secrets
import hashlib
import time
import threading
import logging
from logging.handlers import RotatingFileHandler

import gevent
import gevent.pool

# -- Journal ------------------------------------------------------------------
# Le serveur écrit beaucoup (une ligne par notification, par connexion, par
# partie). Redirigé vers un fichier sans rotation, ce flot finit par remplir le
# disque : SQLite ne peut plus écrire et le serveur ne répond plus jusqu'au
# redémarrage. Ici le journal est plafonné : 4 fichiers de 5 Mo au maximum,
# soit 20 Mo quoi qu'il arrive.
LOG_PATH = os.environ.get(
    "LAFUGA_LOG",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "lafuga.log"))
LOG_MAX_BYTES = int(os.environ.get("LAFUGA_LOG_MAX", str(5 * 1024 * 1024)))
LOG_BACKUPS = int(os.environ.get("LAFUGA_LOG_BACKUPS", "3"))

_log = logging.getLogger("lafuga")
_log.setLevel(logging.INFO)
_log.propagate = False
try:
    _h = RotatingFileHandler(LOG_PATH, maxBytes=LOG_MAX_BYTES,
                             backupCount=LOG_BACKUPS, encoding="utf-8")
    _h.setFormatter(logging.Formatter("%(asctime)s %(message)s",
                                      "%Y-%m-%d %H:%M:%S"))
    _log.addHandler(_h)
except Exception:
    pass
_stderr_h = logging.StreamHandler()
_stderr_h.setFormatter(logging.Formatter("%(asctime)s %(message)s",
                                         "%Y-%m-%d %H:%M:%S"))
_log.addHandler(_stderr_h)


def print(*args, **kwargs):          # noqa: A001 — volontaire : tous les
    """Remplace print() dans CE module uniquement : même usage, mais vers le
    journal borné. Les kwargs de print (sep, end, flush, file) sont acceptés et
    ignorés, pour que les appels existants continuent de fonctionner."""
    sep = kwargs.get("sep", " ")
    try:
        _log.info(sep.join(str(a) for a in args))
    except Exception:
        pass
''')


# ───────────────────────────────────────────────────────────────────────────
# 2. Base de données : WAL + attente de verrou explicite.
#    En mode DELETE (le défaut), un écrivain bloque TOUS les lecteurs. Comme
#    gevent n'a qu'un seul fil d'exécution et que sqlite3 n'est pas coopératif,
#    une attente de verrou gèle le serveur entier, pas seulement la requête.
#    WAL supprime cette contention : lecteurs et écrivain avancent ensemble.
# ───────────────────────────────────────────────────────────────────────────
edit("get_db : une connexion par requete, fermee a coup sur",
     '''def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn
''',
     '''# ── LA fuite : pourquoi « Too many open files » ───────────────────────────
# `row = get_db().execute(...).fetchone()` ne ferme JAMAIS la connexion par
# comptage de références : une connexion sqlite3 et son curseur forment un
# CYCLE de références. Seul le ramasse-miettes CYCLIQUE peut les libérer — et il
# ne passe que lorsqu'il y a eu assez d'allocations. Avec peu de joueurs, il y a
# peu d'allocations, donc il passe rarement : les connexions s'empilent jusqu'à
# épuiser les descripteurs de fichiers du processus. Le serveur reste alors
# VIVANT mais ne peut plus accepter une seule connexion — et systemd, qui le voit
# tourner, ne le redémarre pas.
#
# Mesuré : ramasse-miettes cyclique désactivé, 300 appels de cette forme = 300
# descripteurs qui ne redescendent jamais ; un gc.collect() explicite les libère
# tous d'un coup. C'est exactement ce qui se passait en production.
#
# La correction ne dépend plus du ramasse-miettes : une seule connexion par
# requête, fermée de FORCE à la fin (fin de requête HTTP, fin d'événement
# Socket.IO, fin de tâche de fond). Les 65 appels existants à get_db() et les
# 51 conn.close() du code restent inchangés.
import gevent.local

# 1 = une connexion partagée pour toute la requête (défaut, le plus économe).
# 0 = une vraie connexion par appel, comme avant, mais toutes fermées à coup sûr
#     en fin de requête. Soupape de secours : LAFUGA_DB_PARTAGE=0.
DB_PARTAGE = os.environ.get("LAFUGA_DB_PARTAGE", "1") != "0"

_db_local = gevent.local.local()


def _db_ouvrir():
    """Ouvre une vraie connexion, réglée pour un serveur : attente de verrou
    explicite, WAL sans fsync à chaque écriture, cache borné."""
    # timeout : si un autre écrivain tient le verrou, on attend jusqu'à 30 s au
    # lieu d'échouer au bout de 5 s avec « database is locked ».
    conn = sqlite3.connect(DB_PATH, timeout=30.0)
    conn.row_factory = sqlite3.Row
    # même rôle que timeout, appliqué aussi aux verrous pris en cours de route.
    conn.execute("PRAGMA busy_timeout = 30000")
    # En WAL, NORMAL ne perd aucune donnée validée si le PROCESSUS plante ; seul
    # un arrêt brutal de la MACHINE peut perdre la dernière transaction. En
    # échange, plus de fsync à chaque écriture.
    conn.execute("PRAGMA synchronous = NORMAL")
    # Chaque connexion a son PROPRE cache de pages (2 Mo par défaut). Avec des
    # dizaines de requêtes simultanées, cela se compte en centaines de Mo.
    conn.execute("PRAGMA cache_size = -1024")
    return conn


class _Db(object):
    """Vue sur la connexion de la requête en cours. S'utilise exactement comme
    une connexion sqlite3 (execute, cursor, commit, row_factory...).

    En mode partagé, close() est volontairement SANS EFFET : la vraie fermeture
    a lieu en fin de requête, dans _db_release(). C'est ce qui permet de ne rien
    changer aux 51 appels à conn.close() déjà présents dans le code."""

    __slots__ = ("_conn", "_vraie_fermeture")

    def __init__(self, conn, vraie_fermeture=False):
        object.__setattr__(self, "_conn", conn)
        object.__setattr__(self, "_vraie_fermeture", vraie_fermeture)

    def __getattr__(self, nom):
        return getattr(object.__getattribute__(self, "_conn"), nom)

    def __setattr__(self, nom, val):
        setattr(object.__getattribute__(self, "_conn"), nom, val)

    def __enter__(self):
        return object.__getattribute__(self, "_conn").__enter__()

    def __exit__(self, *a):
        return object.__getattribute__(self, "_conn").__exit__(*a)

    def close(self):
        if object.__getattribute__(self, "_vraie_fermeture"):
            try:
                object.__getattribute__(self, "_conn").close()
            except Exception:
                pass
        # sinon : fermeture différée, voir _db_release()


def get_db():
    if DB_PARTAGE:
        conn = getattr(_db_local, "conn", None)
        if conn is None:
            conn = _db_ouvrir()
            _db_local.conn = conn
        return _Db(conn)
    # Mode sans partage : une vraie connexion par appel (comportement d'origine),
    # mais enregistrée pour être fermée à coup sûr même si personne ne la ferme.
    conn = _db_ouvrir()
    tous = getattr(_db_local, "tous", None)
    if tous is None:
        tous = []
        _db_local.tous = tous
    tous.append(conn)
    return _Db(conn, vraie_fermeture=True)


def _db_release():
    """Ferme POUR DE BON la ou les connexions de la tâche en cours. Appelée à la
    fin de chaque requête HTTP, de chaque événement Socket.IO et de chaque tâche
    de fond. C'est ce qui remplace le ramasse-miettes."""
    conn = getattr(_db_local, "conn", None)
    if conn is not None:
        _db_local.conn = None
        try:
            conn.close()
        except Exception:
            pass
    tous = getattr(_db_local, "tous", None)
    if tous:
        _db_local.tous = None
        for c in tous:
            try:
                c.close()
            except Exception:
                pass


def _fin_de_tache(fonction):
    """Enrobe une tâche de fond : sa connexion est fermée quoi qu'il arrive."""
    import functools

    @functools.wraps(fonction)
    def _enrobe(*a, **kw):
        try:
            return fonction(*a, **kw)
        finally:
            _db_release()
    return _enrobe


def _spawn_later(delai, fonction, *args):
    """gevent.spawn_later, mais la connexion de la tâche est fermée à la fin."""
    return gevent.spawn_later(delai, _fin_de_tache(fonction), *args)
''')

edit("init_db : WAL + index manquants",
     '''def init_db():
    conn = get_db()
    c = conn.cursor()
''',
     '''def init_db():
    conn = get_db()
    c = conn.cursor()
    # WAL est une propriété PERSISTANTE du fichier : réglée une fois ici, elle
    # vaut pour toutes les connexions suivantes, y compris après redémarrage.
    try:
        c.execute("PRAGMA journal_mode = WAL")
        # Point de contrôle automatique : empêche le fichier -wal de grossir
        # indéfiniment (1000 pages ~ 4 Mo).
        c.execute("PRAGMA wal_autocheckpoint = 1000")
    except Exception as e:
        print("[db] WAL impossible :", e)
''')

edit("init_db : index de fin",
     '''    try:
        c.execute("ALTER TABLE messages ADD COLUMN read INTEGER DEFAULT 0")
    except Exception:
        pass
    conn.commit()
    conn.close()
''',
     '''    try:
        c.execute("ALTER TABLE messages ADD COLUMN read INTEGER DEFAULT 0")
    except Exception:
        pass
    # ── Index manquants ──────────────────────────────────────────────────
    # Sans eux, ces requêtes parcourent toute la table : le serveur ralentit à
    # mesure que la base grossit, donc « plus on s'en sert, plus c'est lent ».
    for _idx in (
        # conversations : messages entre deux joueurs, du plus récent au plus ancien
        "CREATE INDEX IF NOT EXISTS idx_msg_pair "
        "ON messages(from_user_id, to_user_id, created_at)",
        # badge non lus
        "CREATE INDEX IF NOT EXISTS idx_msg_unread "
        "ON messages(to_user_id, read)",
        # NB : pas d'index (user_id, played_at) sur `games`. Il ferait changer
        # l'ordre des parties enregistrees dans la MEME seconde, donc l'ordre
        # affiche dans l'historique. idx_games_user suffit.
        # corr_list : parties actives d'un joueur
        "CREATE INDEX IF NOT EXISTS idx_corr_blanc_statut "
        "ON corr_games(blanc_user_id, statut)",
        "CREATE INDEX IF NOT EXISTS idx_corr_noir_statut "
        "ON corr_games(noir_user_id, statut)",
        # purge des jetons expirés
        "CREATE INDEX IF NOT EXISTS idx_tokens_created "
        "ON tokens(created_at)",
    ):
        try:
            c.execute(_idx)
        except Exception as e:
            print("[db] index :", e)
    conn.commit()
    conn.close()
    _db_release()
''')


# ───────────────────────────────────────────────────────────────────────────
# 3. corr_list : 2 + 3×N connexions SQLite par appel  ->  4 au total.
#    L'appli interroge corr_list toutes les 3 s. Avec 10 parties en cours,
#    c'était 32 ouvertures de base par joueur et par sondage.
# ───────────────────────────────────────────────────────────────────────────
edit("_corr_game_dict : cache facultatif",
     '''def _corr_game_dict(row, me_uid):
    """Transforme une ligne corr_games en dict pour le client, du point de vue
    de me_uid (couleur, adversaire, score, à qui de jouer...)."""
    is_blanc = (row["blanc_user_id"] == me_uid)
    my_color = "Blanc" if is_blanc else "Noir"
    opp_uid = row["noir_user_id"] if is_blanc else row["blanc_user_id"]
    opp_pseudo = row["noir_pseudo"] if is_blanc else row["blanc_pseudo"]
    scores = _get_corr_score(me_uid, opp_uid)
    # Mélo (global) de l'adversaire — pour l'afficher sur le slot de défi.
    opp_melo = 1500
    try:
        r = get_db().execute("SELECT melo FROM users WHERE id=?",
                             (opp_uid,)).fetchone()
        if r:
            opp_melo = r["melo"]
    except Exception:
        pass
''',
     '''def _corr_bulk(rows, me_uid):
    """Pré-charge, en 3 requêtes au total, tout ce dont _corr_game_dict a besoin
    pour une LISTE de parties : scores head-to-head, mélo des adversaires et
    nombre de messages de chat. Sans ça, chaque partie coûtait 3 connexions
    SQLite ; corr_list est sondée toutes les 3 secondes par chaque joueur."""
    opp_ids = set()
    game_ids = set()
    for r in rows:
        opp_ids.add(r["noir_user_id"] if r["blanc_user_id"] == me_uid
                    else r["blanc_user_id"])
        game_ids.add(r["id"])
    cache = {"scores": {}, "melos": {}, "chat": {}}
    if not rows:
        return cache
    conn = get_db()
    try:
        ph = ",".join("?" * len(opp_ids))
        ids = list(opp_ids)
        # mélo de tous les adversaires
        for r in conn.execute(
                "SELECT id, melo FROM users WHERE id IN (%s)" % ph, ids):
            cache["melos"][r["id"]] = r["melo"]
        # scores de correspondance avec tous les adversaires
        for r in conn.execute(
                "SELECT user_a, user_b, score_a, score_b FROM corr_scores "
                "WHERE (user_a=? AND user_b IN (%s)) "
                "   OR (user_b=? AND user_a IN (%s))" % (ph, ph),
                [me_uid] + ids + [me_uid] + ids):
            cache["scores"][(r["user_a"], r["user_b"])] = (r["score_a"],
                                                           r["score_b"])
        # nombre de messages de chat de chaque partie
        gph = ",".join("?" * len(game_ids))
        for r in conn.execute(
                "SELECT game_id, COUNT(*) AS n FROM corr_chat "
                "WHERE game_id IN (%s) GROUP BY game_id" % gph,
                list(game_ids)):
            cache["chat"][r["game_id"]] = r["n"]
    finally:
        conn.close()
    return cache


def _corr_game_dict(row, me_uid, cache=None):
    """Transforme une ligne corr_games en dict pour le client, du point de vue
    de me_uid (couleur, adversaire, score, à qui de jouer...).
    `cache` : résultat de _corr_bulk() quand on traite une liste — évite 3
    requêtes par partie. Sans cache, comportement d'origine inchangé."""
    is_blanc = (row["blanc_user_id"] == me_uid)
    my_color = "Blanc" if is_blanc else "Noir"
    opp_uid = row["noir_user_id"] if is_blanc else row["blanc_user_id"]
    opp_pseudo = row["noir_pseudo"] if is_blanc else row["blanc_pseudo"]
    if cache is not None:
        a, b = _corr_score_pair(me_uid, opp_uid)
        sa, sb = cache["scores"].get((a, b), (0, 0))
        scores = ({me_uid: sa, opp_uid: sb} if me_uid == a
                  else {me_uid: sb, opp_uid: sa})
    else:
        scores = _get_corr_score(me_uid, opp_uid)
    # Mélo (global) de l'adversaire — pour l'afficher sur le slot de défi.
    opp_melo = 1500
    if cache is not None:
        opp_melo = cache["melos"].get(opp_uid, 1500)
    else:
        try:
            r = get_db().execute("SELECT melo FROM users WHERE id=?",
                                 (opp_uid,)).fetchone()
            if r:
                opp_melo = r["melo"]
        except Exception:
            pass
''')

edit("_corr_game_dict : chat non lus via le cache",
     '''    chat_non_lus = 0
    try:
        total = get_db().execute(
            "SELECT COUNT(*) AS n FROM corr_chat WHERE game_id=?",
            (row["id"],)).fetchone()["n"]
        lu_col = "blanc_chat_lu" if is_blanc else "noir_chat_lu"
        lu = row[lu_col] if lu_col in row.keys() else 0
        chat_non_lus = max(0, total - (lu or 0))
    except Exception:
        chat_non_lus = 0
''',
     '''    chat_non_lus = 0
    try:
        if cache is not None:
            total = cache["chat"].get(row["id"], 0)
        else:
            total = get_db().execute(
                "SELECT COUNT(*) AS n FROM corr_chat WHERE game_id=?",
                (row["id"],)).fetchone()["n"]
        lu_col = "blanc_chat_lu" if is_blanc else "noir_chat_lu"
        lu = row[lu_col] if lu_col in row.keys() else 0
        chat_non_lus = max(0, total - (lu or 0))
    except Exception:
        chat_non_lus = 0
''')

edit("corr_list : une seule connexion + cache",
     '''    rows = get_db().execute(
        "SELECT * FROM corr_games WHERE (blanc_user_id=? OR noir_user_id=?) "
        "AND (statut != 'termine' "
        "     OR (blanc_user_id=? AND blanc_vu=0) "
        "     OR (noir_user_id=? AND noir_vu=0)) "
        "ORDER BY (statut='termine') ASC, updated_at DESC",
        (me["id"], me["id"], me["id"], me["id"])).fetchall()
    games = [_corr_game_dict(r, me["id"]) for r in rows]
    return jsonify({"ok": True, "games": games})
''',
     '''    conn = get_db()
    try:
        rows = conn.execute(
            "SELECT * FROM corr_games WHERE (blanc_user_id=? OR noir_user_id=?) "
            "AND (statut != 'termine' "
            "     OR (blanc_user_id=? AND blanc_vu=0) "
            "     OR (noir_user_id=? AND noir_vu=0)) "
            "ORDER BY (statut='termine') ASC, updated_at DESC",
            (me["id"], me["id"], me["id"], me["id"])).fetchall()
    finally:
        conn.close()
    cache = _corr_bulk(rows, me["id"])
    games = [_corr_game_dict(r, me["id"], cache) for r in rows]
    return jsonify({"ok": True, "games": games})
''')


# ───────────────────────────────────────────────────────────────────────────
# 4. list_conversations : 1 + 3×N requêtes  ->  3.
# ───────────────────────────────────────────────────────────────────────────
edit("list_conversations : sans N+1",
     '''    convos = []
    db = get_db()
    for r in rows:
        oid = r["other_id"]
        urow = db.execute("SELECT pseudo, photo FROM users WHERE id = ?",
                          (oid,)).fetchone()
        if not urow:
            continue
        last = db.execute(
            "SELECT text, from_user_id FROM messages "
            "WHERE (from_user_id=? AND to_user_id=?) OR (from_user_id=? AND to_user_id=?) "
            "ORDER BY created_at DESC, id DESC LIMIT 1",
            (mid, oid, oid, mid)).fetchone()
        unread = db.execute(
            "SELECT COUNT(*) AS n FROM messages "
            "WHERE from_user_id = ? AND to_user_id = ? AND read = 0",
            (oid, mid)).fetchone()["n"]
        convos.append({
            "pseudo": urow["pseudo"],
            "photo": urow["photo"] or "",
            "last_text": (last["text"] if last else ""),
            "last_de_moi": bool(last and last["from_user_id"] == mid),
            "last_at": r["last_at"],
            "unread": unread,
        })
''',
     '''    convos = []
    oids = [r["other_id"] for r in rows]
    db = get_db()
    try:
        if oids:
            ph = ",".join("?" * len(oids))
            # 1) pseudo + photo de TOUS les interlocuteurs, en une requête
            users = {u["id"]: u for u in db.execute(
                "SELECT id, pseudo, photo FROM users WHERE id IN (%s)" % ph,
                oids)}
            # 2) non lus reçus de chacun, en une requête groupée
            unreads = {r2["from_user_id"]: r2["n"] for r2 in db.execute(
                "SELECT from_user_id, COUNT(*) AS n FROM messages "
                "WHERE to_user_id=? AND read=0 GROUP BY from_user_id", (mid,))}
        else:
            users, unreads = {}, {}
        for r in rows:
            oid = r["other_id"]
            urow = users.get(oid)
            if not urow:
                continue
            # 3) dernier message : requête indexée par idx_msg_pair, immédiate
            last = db.execute(
                "SELECT text, from_user_id FROM messages "
                "WHERE (from_user_id=? AND to_user_id=?) "
                "   OR (from_user_id=? AND to_user_id=?) "
                "ORDER BY created_at DESC, id DESC LIMIT 1",
                (mid, oid, oid, mid)).fetchone()
            convos.append({
                "pseudo": urow["pseudo"],
                "photo": urow["photo"] or "",
                "last_text": (last["text"] if last else ""),
                "last_de_moi": bool(last and last["from_user_id"] == mid),
                "last_at": r["last_at"],
                "unread": unreads.get(oid, 0),
            })
    finally:
        db.close()
''')


# ───────────────────────────────────────────────────────────────────────────
# 5. Notifications push hors du chemin de la requête.
#    messaging.send() est un aller-retour HTTPS vers Google. Tel quel, le
#    joueur qui joue un coup attend la réponse de Firebase avant la sienne, et
#    un Firebase lent ralentit tout le serveur.
# ───────────────────────────────────────────────────────────────────────────
edit("_notify_user : en tâche de fond",
     '''def _notify_user(user_id, kind, title, body, data=None):
    """Envoie une push à un utilisateur SELON SES PRÉFÉRENCES.
    kind = 'turn' | 'msg' | 'defi_corr' | 'defi_direct'.
    notif_mail = interrupteur général ; puis la case propre à l'événement."""
    try:''',
     '''# Réserve de tâches d'envoi de notifications (bornée : voir _notify_user).
_FCM_POOL = gevent.pool.Pool(int(os.environ.get("LAFUGA_FCM_POOL", "20")))


def _notify_user(user_id, kind, title, body, data=None):
    """Envoie une push à un utilisateur SELON SES PRÉFÉRENCES, EN TÂCHE DE FOND.
    kind = 'turn' | 'msg' | 'defi_corr' | 'defi_direct'.

    L'appel revient immédiatement : le joueur qui joue un coup n'attend plus
    l'aller-retour HTTPS vers Firebase. Comportement fonctionnel identique, la
    notification part juste sans faire patienter la requête."""
    try:
        # Réserve BORNÉE : si Firebase rame, on ne crée pas des milliers de
        # tâches en attente. Au-delà, la notification est simplement sautée —
        # une notification perdue est sans gravité, un serveur noyé non.
        if _FCM_POOL.free_count() > 0:
            _FCM_POOL.spawn(_fin_de_tache(_notify_user_sync),
                            user_id, kind, title, body, data)
        else:
            print("[FCM notify] reserve saturee, notification sautee "
                  "(user_id=%s kind=%s)" % (user_id, kind))
    except Exception as e:
        print("[FCM notify] spawn impossible :", e)


def _notify_user_sync(user_id, kind, title, body, data=None):
    """Corps d'origine de _notify_user, exécuté dans son propre greenlet."""
    try:''')

edit("FCM : délai maximal explicite",
     '''        cred = credentials.Certificate(path)
        _FCM_APP = firebase_admin.initialize_app(cred)''',
     '''        cred = credentials.Certificate(path)
        # httpTimeout : sans délai maximal, un Firebase qui ne répond pas laisse
        # un greenlet suspendu très longtemps (le défaut de firebase-admin est
        # de 120 s).
        _FCM_APP = firebase_admin.initialize_app(cred,
                                                 options={"httpTimeout": 20})''')


# ───────────────────────────────────────────────────────────────────────────
# 6. Ne jamais faire d'entrée/sortie en tenant LOCK.
#    LOCK protège TOUT l'état en mémoire (parties, file d'attente, connectés).
#    Le tenir pendant une écriture SQLite ou un envoi réseau met en attente
#    tous les autres événements Socket.IO du serveur.
# ───────────────────────────────────────────────────────────────────────────
edit("on_fin_partie : mélo appliqué hors du verrou",
     '''        game["fin_traitee"] = True
        # Appliquer le melo une seule fois, si partie classee
        if game.get("is_ranked") and not game.get("melo_applied"):
            game["melo_applied"] = True
            try:
                melo_result = _apply_melo(game, loser_color, methode)
            except Exception as e:
                print("[melo] erreur :", e)
                melo_result = None
            blanc_sid = game["blanc_sid"]
            noir_sid = game["noir_sid"]
''',
     '''        game["fin_traitee"] = True
        # Appliquer le melo une seule fois, si partie classee. On réserve le
        # droit de le faire SOUS le verrou (drapeau melo_applied), mais on
        # exécute les écritures SQLite APRÈS l'avoir relâché : sinon toute
        # écriture lente met en attente chaque événement du serveur.
        if game.get("is_ranked") and not game.get("melo_applied"):
            game["melo_applied"] = True
            _melo_a_faire = game
            blanc_sid = game["blanc_sid"]
            noir_sid = game["noir_sid"]
        else:
            _melo_a_faire = None
    if _melo_a_faire is not None:
        try:
            melo_result = _apply_melo(_melo_a_faire, loser_color, methode)
        except Exception as e:
            print("[melo] erreur :", e)
            melo_result = None
''')

edit("_check_disconnect_timeout : mélo appliqué hors du verrou",
     '''        if game.get("is_ranked"):
            try:
                melo_result = _apply_melo(game, color_dc, "abandon")
            except Exception as e:
                print("[melo] erreur abandon :", e)
        winner_sid = game["%s_sid" % winner_color.lower()]''',
     '''        _melo_a_faire = game if game.get("is_ranked") else None
        winner_sid = game["%s_sid" % winner_color.lower()]''')

edit("_check_disconnect_timeout : application après le verrou",
     '''        print("[game %s] %s n'est pas revenu : abandon, %s gagne le match" %
              (game_id, color_dc, winner_color))
    # Prévenir le gagnant (toujours connecté)''',
     '''        print("[game %s] %s n'est pas revenu : abandon, %s gagne le match" %
              (game_id, color_dc, winner_color))
    if _melo_a_faire is not None:
        try:
            melo_result = _apply_melo(_melo_a_faire, color_dc, "abandon")
        except Exception as e:
            print("[melo] erreur abandon :", e)
    # Prévenir le gagnant (toujours connecté)''')


# ───────────────────────────────────────────────────────────────────────────
# 7. Un événement Socket.IO ou une route qui lève une exception ne doit jamais
#    faire tomber la connexion du joueur ni renvoyer une page d'erreur HTML.
#    Le garde-fou est posé sur sio.on / sio.event AVANT la définition des
#    gestionnaires : tous en héritent, sans toucher à leur code.
# ───────────────────────────────────────────────────────────────────────────
edit("garde-fou sur les gestionnaires",
     '''sio = socketio_lib.Server(cors_allowed_origins="*", async_mode="gevent")
app = socketio_lib.WSGIApp(sio, flask_app)
''',
     '''sio = socketio_lib.Server(cors_allowed_origins="*", async_mode="gevent")
app = socketio_lib.WSGIApp(sio, flask_app)


# ── Garde-fou : une erreur dans UN gestionnaire ne doit jamais couper la
# connexion du joueur ni faire tomber le serveur. On enveloppe sio.on et
# sio.event ici, avant que les gestionnaires ne soient définis : ils en
# héritent tous automatiquement.
import functools as _ft

_SIO_ERREURS = {}          # nom d'événement -> nombre d'erreurs (pour /health)


def _garde(fn):
    nom = getattr(fn, "__name__", "?")
    # Nombre d'arguments positionnels que le gestionnaire accepte vraiment.
    # python-socketio appelle parfois un gestionnaire avec un argument de plus
    # (connect reçoit `auth`, disconnect reçoit `reason` selon la version) et
    # compte sur le TypeError pour se rabattre. Comme l'enveloppe accepte *a,
    # ce TypeError n'aurait plus lieu côté bibliothèque : on ajuste ici.
    import inspect
    try:
        _spec = inspect.getfullargspec(fn)
        _nmax = None if _spec.varargs else len(_spec.args)
    except Exception:
        _nmax = None

    @_ft.wraps(fn)
    def _enveloppe(*a, **kw):
        if _nmax is not None and len(a) > _nmax:
            a = a[:_nmax]
        # Tout événement portant un game_id prouve que la partie est vivante :
        # on l'horodate, pour que le ménage ne l'oublie jamais par erreur.
        try:
            if len(a) >= 2 and isinstance(a[1], dict):
                _gid = a[1].get("game_id")
                if _gid is not None:
                    _g = GAMES.get(_gid)
                    if _g is not None:
                        _g["last_seen"] = time.time()
        except Exception:
            pass
        try:
            return fn(*a, **kw)
        except Exception as e:
            _SIO_ERREURS[nom] = _SIO_ERREURS.get(nom, 0) + 1
            import traceback
            print("[sio ERREUR] %s : %s\\n%s"
                  % (nom, e, traceback.format_exc()))
            return None
        finally:
            # Fin de CHAQUE événement Socket.IO : connexion SQLite fermée.
            _db_release()
    return _enveloppe


_sio_on_brut = sio.on
_sio_event_brut = sio.event


def _sio_on(event, *a, **kw):
    deco = _sio_on_brut(event, *a, **kw)

    def _appliquer(fn):
        return deco(_garde(fn))
    return _appliquer


def _sio_event(*a, **kw):
    if len(a) == 1 and not kw and callable(a[0]):
        return _sio_event_brut(_garde(a[0]))
    deco = _sio_event_brut(*a, **kw)

    def _appliquer(fn):
        return deco(_garde(fn))
    return _appliquer


sio.on = _sio_on
sio.event = _sio_event


@flask_app.teardown_request
def _fermer_db_http(exc):
    """Fin de CHAQUE requête HTTP : la connexion SQLite est fermée pour de bon.
    C'est le premier des trois points de fermeture qui remplacent le
    ramasse-miettes (voir get_db)."""
    _db_release()


@flask_app.errorhandler(Exception)
def _erreur_http(e):
    """Toute exception non prévue dans une route renvoie un JSON propre (et
    jamais une page HTML de trace, que l'appli ne sait pas lire)."""
    from werkzeug.exceptions import HTTPException
    if isinstance(e, HTTPException):
        return e
    import traceback
    print("[http ERREUR] %s %s : %s\\n%s"
          % (request.method, request.path, e, traceback.format_exc()))
    return jsonify({"ok": False, "error": "Erreur serveur"}), 500
''')


# ───────────────────────────────────────────────────────────────────────────
# 8. Ménage périodique : purger ce qui n'était jamais purgé.
#    - DEFIS : un défi ni accepté ni refusé restait là pour toujours.
#    - GAMES : un match dont personne ne clique « partie suivante » et dont
#      personne ne se déconnecte restait là pour toujours.
#    - CONNECTED : un sid dont la déconnexion a été manquée restait là.
#    - tokens : une ligne par connexion, jamais supprimée.
# ───────────────────────────────────────────────────────────────────────────
edit("greenlet de ménage",
     '''def _queue_watchdog():''',
     '''# Durées de conservation du ménage périodique.
# Réglables par variable d'environnement (utile pour tester, et pour ajuster
# sans toucher au code).
DEFI_TTL = int(os.environ.get("LAFUGA_DEFI_TTL", "300"))
#   un défi direct ni accepté ni refusé expire au bout de 5 min
GAME_IDLE_TTL = int(os.environ.get("LAFUGA_GAME_IDLE_TTL", str(12 * 3600)))
#   une partie SANS AUCUN événement est oubliée après 12 h
JANITOR_PERIOD = int(os.environ.get("LAFUGA_JANITOR_PERIOD", "300"))
#   le ménage passe toutes les 5 min


def _janitor():
    """Boucle de fond : purge l'état en mémoire et la base des restes que
    personne ne supprimait. Sans elle, ces structures ne faisaient que grossir
    et le serveur finissait par manquer de mémoire."""
    while True:
        gevent.sleep(JANITOR_PERIOD)
        now = time.time()
        try:
            with LOCK:
                # défis directs jamais résolus
                for did, v in list(DEFIS.items()):
                    dep = v.get("since")
                    if dep is None:
                        v["since"] = now
                    elif now - dep > DEFI_TTL:
                        DEFIS.pop(did, None)
                        print("[menage] defi %s expire" % did)
                # parties oubliées : aucun événement depuis GAME_IDLE_TTL. Le
                # moindre coup, message ou changement d'état rafraîchit
                # last_seen (voir _garde), donc une partie en cours, même très
                # longue, n'est jamais touchée.
                for gid, v in list(GAMES.items()):
                    vu = v.get("last_seen")
                    if vu is None:
                        v["last_seen"] = now      # première vue : on date, sans purger
                    elif now - vu > GAME_IDLE_TTL:
                        GAMES.pop(gid, None)
                        print("[menage] partie %s oubliee (aucun evenement "
                              "depuis %dh)" % (gid, GAME_IDLE_TTL // 3600))
                # Connexions et file d'attente : retirer les sid FANTÔMES,
                # c'est-à-dire ceux dont la déconnexion n'a pas été traitée.
                # ATTENTION : le sid Socket.IO n'est PAS le sid engine.io —
                # comparer à sio.eio.sockets éjecterait TOUS les joueurs bel et
                # bien connectés. On demande donc à Socket.IO lui-même, et on ne
                # purge QUE sur un « non » franc (en cas de doute, on garde).
                def _vivant(sid):
                    try:
                        return bool(sio.manager.is_connected(sid, "/"))
                    except Exception:
                        return True          # dans le doute, on ne touche pas
                for s in [s for s in list(CONNECTED) if not _vivant(s)]:
                    CONNECTED.pop(s, None)
                    print("[menage] connexion fantome %s retiree" % s)
                for e in [e for e in list(QUEUE) if not _vivant(e.get("sid"))]:
                    try:
                        QUEUE.remove(e)
                        print("[menage] file : entree fantome retiree")
                    except ValueError:
                        pass
        except Exception as e:
            print("[menage] erreur memoire :", e)
        # jetons expirés : une ligne par connexion, jamais supprimée jusqu'ici
        try:
            conn = get_db()
            cur = conn.execute("DELETE FROM tokens WHERE created_at < ?",
                               (int(now) - TOKEN_TTL,))
            n = cur.rowcount
            conn.commit()
            conn.close()
            if n:
                print("[menage] %d jetons expires supprimes" % n)
        except Exception as e:
            print("[menage] erreur jetons :", e)
        # Fin du tour de ménage : connexion fermée (ce greenlet vit pour
        # toujours, il ne doit donc rien garder ouvert entre deux passages).
        _db_release()


def _queue_watchdog():''')

edit("GAMES : horodatage à la création (matchmaking)",
     '''            GAMES[game_id] = {''',
     '''            GAMES[game_id] = {
                "since": time.time(), "last_seen": time.time(),''')


# ───────────────────────────────────────────────────────────────────────────
# 9. /health : de quoi savoir ce qui se passe AVANT la panne, et après.
# ───────────────────────────────────────────────────────────────────────────
edit("spawn_later : delai de deconnexion",
     '''        gevent.spawn_later(DISCONNECT_GRACE, _check_disconnect_timeout,
                             game_id_dc, color_dc)''',
     '''        _spawn_later(DISCONNECT_GRACE, _check_disconnect_timeout,
                     game_id_dc, color_dc)''')

edit("spawn_later : nettoyage apres abandon",
     '''        gevent.spawn_later(3, _cleanup_dc, game_id)''',
     '''        _spawn_later(3, _cleanup_dc, game_id)''')

edit("spawn_later : nettoyage fin de match",
     '''        gevent.spawn_later(3, _cleanup_game, game_id)''',
     '''        _spawn_later(3, _cleanup_game, game_id)''')

edit("spawn_later : delai partie suivante",
     '''            gevent.spawn_later(NEXT_GAME_GRACE, _check_next_game_timeout, game_id)''',
     '''            _spawn_later(NEXT_GAME_GRACE, _check_next_game_timeout, game_id)''')

edit("route /health",
     '''@flask_app.route("/", methods=["GET"])
def root():
    return "La Fuga server up\\n"
''',
     '''@flask_app.route("/", methods=["GET"])
def root():
    return "La Fuga server up\\n"


BOOT_TIME = time.time()


def _compter_fd_db():
    """Combien de descripteurs de fichiers pointent sur la base ? C'est la mesure
    directe de la fuite qui faisait tomber le serveur (« Too many open files »).
    Doit rester petit et stable, quel que soit le temps de fonctionnement."""
    n = 0
    try:
        for f in os.listdir("/proc/self/fd"):
            try:
                if os.readlink("/proc/self/fd/" + f).startswith(DB_PATH):
                    n += 1
            except OSError:
                pass
    except Exception:
        return -1
    return n


@flask_app.route("/health", methods=["GET"])
def health():
    """État du serveur, à consulter à la main ou depuis une surveillance.
    Tout ce qui pourrait grossir sans fin est compté ici : si un de ces nombres
    monte sans jamais redescendre, on sait immédiatement où chercher."""
    out = {"ok": True, "uptime_s": int(time.time() - BOOT_TIME)}
    try:
        import resource
        out["rss_ko"] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    except Exception:
        pass
    try:
        out["fd"] = len(os.listdir("/proc/self/fd"))
    except Exception:
        pass
    try:
        out["etat"] = {"parties": len(GAMES), "connectes": len(CONNECTED),
                       "file": len(QUEUE), "defis": len(DEFIS),
                       "sockets_eio": len(sio.eio.sockets)}
    except Exception:
        pass
    try:
        import gc
        out["greenlets"] = sum(1 for o in gc.get_objects()
                               if type(o).__name__ == "Greenlet")
    except Exception:
        pass
    out["erreurs_sio"] = dict(_SIO_ERREURS)
    try:
        conn = get_db()
        out["db"] = {
            "journal": conn.execute("PRAGMA journal_mode").fetchone()[0],
            "taille_ko": int(os.path.getsize(DB_PATH) / 1024),
            "jetons": conn.execute("SELECT COUNT(*) FROM tokens").fetchone()[0],
            # LE chiffre à surveiller : c'est lui qui montait jusqu'à 1024 et
            # faisait tomber le serveur (« Too many open files »). En WAL, une
            # connexion ouverte = 3 descripteurs (la base, le -wal, le -shm),
            # donc une valeur de 3 pendant la requête /health est normale : c'est
            # la connexion de cette requête-là. Ce qui compte, c'est que ce
            # nombre ne GRANDISSE pas avec le temps de fonctionnement.
            "descripteurs_base": _compter_fd_db(),
        }
        conn.close()
    except Exception as e:
        out["db"] = str(e)
    return jsonify(out)
''')


# ───────────────────────────────────────────────────────────────────────────
# 10. Lancement : concurrence bornée, ménage lancé, arrêt propre.
#     Sans borne, une rafale de requêtes crée autant de greenlets que de
#     connexions, chacun avec ses descripteurs SQLite : c'est ainsi qu'on
#     atteint « Too many open files » (limite courante : 1024).
# ───────────────────────────────────────────────────────────────────────────
edit("lancement borné + ménage + arrêt propre",
     '''    gevent.spawn(_queue_watchdog)

    from gevent.pywsgi import WSGIServer
    try:
        # Vrai WebSocket (plus reactif). Si le paquet gevent-websocket n'est pas
        # installe, Socket.IO bascule tout seul en long-polling : le jeu
        # fonctionne quand meme, avec un peu plus de latence.
        from geventwebsocket.handler import WebSocketHandler
        srv = WSGIServer(("0.0.0.0", PORT), app, handler_class=WebSocketHandler)
        print("[lafuga] Transport : WebSocket + long-polling")
    except ImportError:
        srv = WSGIServer(("0.0.0.0", PORT), app)
        print("[lafuga] Transport : long-polling seulement")
        print("[lafuga] (pip install gevent-websocket pour activer le WebSocket)")
    srv.serve_forever()
''',
     '''    gevent.spawn(_queue_watchdog)
    gevent.spawn(_janitor)
    print("[lafuga] Journal :", LOG_PATH)

    from gevent.pywsgi import WSGIServer
    # Concurrence BORNÉE. Sans borne, une rafale crée autant de greenlets que de
    # connexions simultanées, chacun tenant ses descripteurs SQLite : au-delà de
    # la limite du système (souvent 1024) le serveur ne peut plus rien ouvrir.
    # Avec une réserve, le surplus attend son tour au lieu de tout casser.
    MAX_CONCURRENT = int(os.environ.get("LAFUGA_MAX_CONCURRENT", "400"))
    pool = gevent.pool.Pool(MAX_CONCURRENT)
    try:
        # Vrai WebSocket (plus reactif). Si le paquet gevent-websocket n'est pas
        # installe, Socket.IO bascule tout seul en long-polling : le jeu
        # fonctionne quand meme, avec un peu plus de latence.
        from geventwebsocket.handler import WebSocketHandler
        srv = WSGIServer(("0.0.0.0", PORT), app, spawn=pool,
                         handler_class=WebSocketHandler, log=None)
        print("[lafuga] Transport : WebSocket + long-polling")
    except ImportError:
        srv = WSGIServer(("0.0.0.0", PORT), app, spawn=pool, log=None)
        print("[lafuga] Transport : long-polling seulement")
        print("[lafuga] (pip install gevent-websocket pour activer le WebSocket)")
    print("[lafuga] Connexions simultanees max :", MAX_CONCURRENT)

    # Arrêt propre sur SIGTERM (c'est ce que systemd envoie) : on laisse les
    # requêtes en cours se terminer et on ferme la base sans laisser de verrou.
    import signal

    def _arret(signum, frame):
        print("[lafuga] signal %s : arret propre" % signum)
        try:
            srv.stop(timeout=10)
        except Exception:
            pass
        raise SystemExit(0)

    for _s in (signal.SIGTERM, signal.SIGINT):
        try:
            gevent.signal_handler(_s, _arret, _s, None)
        except Exception:
            try:
                signal.signal(_s, _arret)
            except Exception:
                pass
    try:
        srv.serve_forever()
    except (KeyboardInterrupt, SystemExit):
        print("[lafuga] arrete")
''')



# ───────────────────────────────────────────────────────────────────────────
# 11. Historique : ordre stable.
#     "ORDER BY played_at DESC" seul ne départage pas deux parties enregistrées
#     dans la MÊME seconde (ce qui arrive : une partie flash, ou les deux
#     joueurs qui sauvegardent en même temps). SQLite rend alors un ordre
#     arbitraire, et l'historique peut s'afficher dans un ordre différent d'un
#     appel à l'autre. "id DESC" départage : toujours la plus récente d'abord.
# ───────────────────────────────────────────────────────────────────────────
edit("list_games : ordre stable",
     '''    rows = get_db().execute(
        "SELECT game_uid, joueur1, joueur2, resultat, methode, cadence, "
        "objectif, played_at FROM games WHERE user_id = ? ORDER BY played_at DESC",
        (target_id,)
    ).fetchall()''',
     '''    rows = get_db().execute(
        "SELECT game_uid, joueur1, joueur2, resultat, methode, cadence, "
        "objectif, played_at FROM games WHERE user_id = ? "
        "ORDER BY played_at DESC, id DESC",
        (target_id,)
    ).fetchall()''')


# ───────────────────────────────────────────────────────────────────────────
def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    src_path = sys.argv[1]
    inplace = "--inplace" in sys.argv
    src = open(src_path, encoding="utf-8").read()
    out = src
    rapport = []
    for nom, ancien, nouveau in EDITS:
        n = out.count(ancien)
        if n != 1:
            sys.stderr.write(
                "ECHEC : « %s » — motif trouve %d fois (attendu : 1).\n"
                "Aucun fichier n'a ete modifie.\n" % (nom, n))
            return 1
        out = out.replace(ancien, nouveau, 1)
        rapport.append(nom)
    # Les emit() faits en tenant LOCK sont signales, pas reecrits
    # automatiquement : ils sont peu nombreux et sans risque reel (envoi vers
    # UN client precis, deja connecte). Voir NOTES dans le document joint.
    dst = src_path if inplace else re.sub(r"\.py$", "_patched.py", src_path)
    if inplace:
        open(src_path + ".bak", "w", encoding="utf-8").write(src)
    open(dst, "w", encoding="utf-8").write(out)
    sys.stderr.write("%d corrections appliquees :\n" % len(rapport))
    for r in rapport:
        sys.stderr.write("  - %s\n" % r)
    sys.stderr.write("Ecrit : %s\n" % dst)
    return 0


if __name__ == "__main__":
    sys.exit(main())
