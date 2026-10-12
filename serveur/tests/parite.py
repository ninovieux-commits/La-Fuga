# -*- coding: utf-8 -*-
"""Parite : rejoue EXACTEMENT le meme scenario sur deux serveurs (A = original,
B = corrige) et compare toutes les reponses JSON, champ par champ."""
import json, sys, time, urllib.request

A = "http://127.0.0.1:%s" % sys.argv[1]
B = "http://127.0.0.1:%s" % sys.argv[2]

def post(base, path, payload):
    req = urllib.request.Request(base + path, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        try: return e.code, json.loads(e.read())
        except Exception: return e.code, {"_raw": "?"}
    except Exception as e:
        return -1, {"_err": repr(e)[:150]}

VOLATILE = {"token", "created_at", "played_at", "updated_at", "ts", "last_at",
            "date", "since", "uptime_s", "rss_ko", "fd", "greenlets"}

def norm(o):
    if isinstance(o, dict):
        d = {k: ("<v>" if k in VOLATILE else norm(v)) for k, v in o.items()}
        # /list_games : l'ordre de deux parties enregistrees dans la MEME
        # seconde est arbitraire cote original (SQLite ne departage pas) et
        # volontairement stabilise cote corrige. On compare donc le contenu,
        # pas cet ordre. (Verifie separement par test_ordre_historique.)
        g = d.get("games")
        if isinstance(g, list) and g and isinstance(g[0], dict) and "game_uid" in g[0]:
            d["games"] = sorted(g, key=lambda x: json.dumps(x, sort_keys=True))
        return d
    if isinstance(o, list):
        return [norm(x) for x in o]
    return o

RESULTS = []
TOK = {}          # base -> {pseudo: token}

def both(path, payload_fn, label=None):
    """payload_fn(base) -> payload (permet d'injecter le bon token par serveur)."""
    out = {}
    for base in (A, B):
        out[base] = post(base, path, payload_fn(base))
    sa, ra = out[A]; sb, rb = out[B]
    ok = (sa == sb) and (norm(ra) == norm(rb))
    RESULTS.append((label or path, ok, sa, sb, ra, rb))
    return out

def tok(base, pseudo):
    return TOK.setdefault(base, {}).get(pseudo, "")

# ── comptes ────────────────────────────────────────────────────────────────
for p in ("Nino", "Ana", "Tiers"):
    o = both("/register", lambda b, p=p: {"pseudo": p, "password": "motdepasse"},
             "register %s" % p)
    for base in (A, B):
        r = o[base][1]
        if r.get("token"):
            TOK.setdefault(base, {})[p] = r["token"]
# doublon + erreurs de validation
both("/register", lambda b: {"pseudo": "Nino", "password": "motdepasse"}, "register doublon")
both("/register", lambda b: {"pseudo": "xy", "password": "motdepasse"}, "register pseudo court")
both("/register", lambda b: {"pseudo": "Zzz", "password": "a"}, "register mdp court")
both("/login", lambda b: {"pseudo": "Nino", "password": "motdepasse"}, "login")
both("/login", lambda b: {"pseudo": "Nino", "password": "faux"}, "login faux mdp")
both("/login", lambda b: {"pseudo": "Inconnu", "password": "x"}, "login inconnu")
both("/ping", lambda b: {"token": tok(b, "Nino")}, "ping")
both("/ping", lambda b: {"token": "bidon"}, "ping token invalide")

# ── profils, favoris, blocages ─────────────────────────────────────────────
both("/set_photo", lambda b: {"token": tok(b, "Nino"), "photo": "nurse"}, "set_photo")
both("/set_description", lambda b: {"token": tok(b, "Nino"), "description": "Salut !"}, "set_description")
both("/set_theme", lambda b: {"token": tok(b, "Nino"), "theme": "insectes"}, "set_theme")
both("/set_email", lambda b: {"token": tok(b, "Nino"), "email": "n@example.com"}, "set_email")
both("/set_fcm_token", lambda b: {"token": tok(b, "Nino"), "fcm_token": "FAKE"}, "set_fcm_token")
both("/set_notif_prefs", lambda b: {"token": tok(b, "Nino"), "notif_mail": 1,
                                    "notif_turn": 1, "notif_msg": 0}, "set_notif_prefs")
both("/account_info", lambda b: {"token": tok(b, "Nino")}, "account_info")
both("/search_user", lambda b: {"token": tok(b, "Nino"), "q": "an"}, "search_user")
both("/search_user", lambda b: {"token": tok(b, "Nino"), "q": "zzzz"}, "search_user vide")
both("/add_favorite", lambda b: {"token": tok(b, "Nino"), "pseudo": "Ana"}, "add_favorite")
both("/add_favorite", lambda b: {"token": tok(b, "Nino"), "pseudo": "Ana"}, "add_favorite bis")
both("/list_favorites", lambda b: {"token": tok(b, "Nino")}, "list_favorites")
both("/list_followers", lambda b: {"token": tok(b, "Ana")}, "list_followers")
both("/get_profile", lambda b: {"token": tok(b, "Nino")}, "get_profile moi")
both("/get_profile", lambda b: {"token": tok(b, "Nino"), "pseudo": "Ana"}, "get_profile autre")
both("/get_profile", lambda b: {"token": tok(b, "Nino"), "pseudo": "Zorglub"}, "get_profile inconnu")
both("/block_user", lambda b: {"token": tok(b, "Nino"), "pseudo": "Tiers"}, "block_user")
both("/list_blocked", lambda b: {"token": tok(b, "Nino")}, "list_blocked")
both("/send_message", lambda b: {"token": tok(b, "Tiers"), "pseudo": "Nino", "text": "bloque ?"}, "message bloque")
both("/unblock_user", lambda b: {"token": tok(b, "Nino"), "pseudo": "Tiers"}, "unblock_user")
both("/remove_favorite", lambda b: {"token": tok(b, "Nino"), "pseudo": "Ana"}, "remove_favorite")

# ── messagerie ─────────────────────────────────────────────────────────────
for i in range(3):
    both("/send_message", lambda b, i=i: {"token": tok(b, "Nino"), "pseudo": "Ana",
                                          "text": "msg %d" % i}, "send_message %d" % i)
both("/send_message", lambda b: {"token": tok(b, "Ana"), "pseudo": "Nino", "text": "reponse"}, "send_message retour")
both("/send_message", lambda b: {"token": tok(b, "Nino"), "pseudo": "Zorglub", "text": "x"}, "send_message inconnu")
both("/send_message", lambda b: {"token": tok(b, "Nino"), "pseudo": "Ana", "text": ""}, "send_message vide")
both("/list_conversation", lambda b: {"token": tok(b, "Nino"), "pseudo": "Ana"}, "list_conversation")
both("/list_conversations", lambda b: {"token": tok(b, "Nino")}, "list_conversations")
both("/list_conversations", lambda b: {"token": tok(b, "Ana")}, "list_conversations Ana")
both("/mark_read", lambda b: {"token": tok(b, "Ana"), "pseudo": "Nino"}, "mark_read")
both("/list_conversations", lambda b: {"token": tok(b, "Ana")}, "list_conversations apres lecture")

# ── historique ─────────────────────────────────────────────────────────────
NMC = "[Blanc \"Nino\"]\n[Noir \"Ana\"]\n1. a1-b2 c3-d4\n"
for i in range(3):
    both("/save_game", lambda b, i=i: {"token": tok(b, "Nino"), "game_uid": "uid%d" % i,
         "nmc_text": NMC, "joueur1": "Nino", "joueur2": "Ana", "resultat": "1-0",
         "methode": "mat", "cadence": "5", "objectif": "3"}, "save_game %d" % i)
both("/save_game", lambda b: {"token": tok(b, "Nino"), "game_uid": "uid0",
     "nmc_text": NMC}, "save_game doublon")
both("/save_game", lambda b: {"token": tok(b, "Nino"), "game_uid": "", "nmc_text": ""}, "save_game vide")
both("/list_games", lambda b: {"token": tok(b, "Nino")}, "list_games")
both("/list_games", lambda b: {"token": tok(b, "Nino"), "pseudo": "Ana"}, "list_games autre")
both("/get_game", lambda b: {"token": tok(b, "Nino"), "game_uid": "uid1"}, "get_game")
both("/get_game", lambda b: {"token": tok(b, "Nino"), "game_uid": "nexistepas"}, "get_game absent")

# ── correspondance ─────────────────────────────────────────────────────────
both("/corr_list", lambda b: {"token": tok(b, "Nino")}, "corr_list vide")
GID = {}
for i in range(3):
    o = both("/corr_defier", lambda b, i=i: {"token": tok(b, "Nino"), "pseudo": "Ana",
             "objectif": "3", "random": False}, "corr_defier %d" % i)
    for base in (A, B):
        GID.setdefault(base, []).append(o[base][1].get("game_id"))
both("/corr_defier", lambda b: {"token": tok(b, "Nino"), "pseudo": "Nino",
     "objectif": "3"}, "corr_defier soi-meme")
both("/corr_defier", lambda b: {"token": tok(b, "Nino"), "pseudo": "Zorglub"}, "corr_defier inconnu")
both("/corr_list", lambda b: {"token": tok(b, "Ana")}, "corr_list defis")
both("/corr_repondre", lambda b: {"token": tok(b, "Ana"), "game_id": GID[b][0],
     "accepte": True}, "corr_repondre oui")
both("/corr_repondre", lambda b: {"token": tok(b, "Ana"), "game_id": GID[b][1],
     "accepte": False}, "corr_repondre non")
both("/corr_repondre", lambda b: {"token": tok(b, "Nino"), "game_id": GID[b][2],
     "accepte": True}, "corr_repondre par le defieur")
both("/corr_list", lambda b: {"token": tok(b, "Ana")}, "corr_list apres reponses")
both("/corr_chat_send", lambda b: {"token": tok(b, "Nino"), "game_id": GID[b][0],
     "texte": "bonne partie"}, "corr_chat_send")
both("/corr_chat_list", lambda b: {"token": tok(b, "Ana"), "game_id": GID[b][0]}, "corr_chat_list")
both("/corr_list", lambda b: {"token": tok(b, "Nino")}, "corr_list avec chat")
# coups : c'est au Blanc de jouer, on essaie avec les deux tokens
for who, notation in (("Nino", "a1-b2"), ("Ana", "c3-d4"), ("Nino", "e5-f6"),
                      ("Ana", "g7-h8")):
    both("/corr_jouer", lambda b, w=who, n=notation: {"token": tok(b, w),
         "game_id": GID[b][0], "notation": n}, "corr_jouer %s %s" % (who, notation))
both("/corr_proposer_nulle", lambda b: {"token": tok(b, "Nino"), "game_id": GID[b][0]}, "corr_proposer_nulle")
both("/corr_list", lambda b: {"token": tok(b, "Ana")}, "corr_list nulle proposee")
both("/corr_repondre_nulle", lambda b: {"token": tok(b, "Ana"), "game_id": GID[b][0],
     "accepte": False}, "corr_repondre_nulle non")
both("/corr_proposer_nulle", lambda b: {"token": tok(b, "Ana"), "game_id": GID[b][0]}, "corr_proposer_nulle 2")
both("/corr_repondre_nulle", lambda b: {"token": tok(b, "Nino"), "game_id": GID[b][0],
     "accepte": True}, "corr_repondre_nulle oui")
both("/corr_list", lambda b: {"token": tok(b, "Nino")}, "corr_list apres nulle")
both("/corr_close", lambda b: {"token": tok(b, "Nino"), "game_id": GID[b][0]}, "corr_close")
both("/corr_list", lambda b: {"token": tok(b, "Nino")}, "corr_list apres close")
both("/corr_abandon", lambda b: {"token": tok(b, "Nino"), "game_id": GID[b][2]}, "corr_abandon")
both("/get_profile", lambda b: {"token": tok(b, "Nino"), "pseudo": "Ana"}, "get_profile h2h")
both("/list_games", lambda b: {"token": tok(b, "Nino")}, "list_games apres corresp")

# ── rapport ────────────────────────────────────────────────────────────────
ko = [r for r in RESULTS if not r[1]]
print("%d appels compares — %d identiques, %d differents"
      % (len(RESULTS), len(RESULTS) - len(ko), len(ko)))
for label, ok, sa, sb, ra, rb in ko:
    print("\n=== DIFFERENT : %s ===" % label)
    print("  A (%s) : %s" % (sa, json.dumps(norm(ra), sort_keys=True, ensure_ascii=False)[:600]))
    print("  B (%s) : %s" % (sb, json.dumps(norm(rb), sort_keys=True, ensure_ascii=False)[:600]))
sys.exit(1 if ko else 0)
