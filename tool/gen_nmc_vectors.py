"""Vecteurs de fidélité de la couche `.nmc`, produits par le code de Kivy.

Trois familles :

1. `notations` — pour un lot de positions, la notation Kivy de CHAQUE coup
   légal, avec le plateau d'après. Le test Dart vérifie que sa propre notation
   est la même chaîne, et que `resolveNotation` retrouve bien ce coup-là.
2. `files` — des parties entières passées par `make_nmc_content`. Le test
   compare octet pour octet.
3. `parses` — des contenus `.nmc` (propres, bancals, hors normes) passés par
   `parse_nmc_content` puis `_parse_moves_text`.
"""
import json, random, sys
sys.path.insert(0, ".")
from py_engine_ref import (dg_generate_moves, COLS, ROWS, setup_initial,
                           to_json_board)
from py_nmc_ref import (ai_notation, ai_compute_push_targets, make_nmc_content,
                        parse_nmc_content, parse_moves_text)



def notations_of(board, camp):
    out = []
    for m in dg_generate_moves(board, camp):
        targets = ai_compute_push_targets(m)
        out.append({
            "notation": ai_notation(m, targets),
            "after": to_json_board(m["board"]),
            "kind": m.get("kind", ""),
        })
    return out


random.seed(20260920)
vectors = {"notations": [], "files": [], "parses": []}

# ── 1. Notations de tous les coups légaux, sur une marche aléatoire ──
board = setup_initial()
for cp in ("Blanc", "Noir"):
    vectors["notations"].append({"board": to_json_board(board), "camp": cp,
                                 "moves": notations_of(board, cp)})

games = []   # parties complètes, pour les fichiers
for game in range(10):
    board = setup_initial()
    camp = "Blanc"
    history = []
    for ply in range(60):
        mv = dg_generate_moves(board, camp)
        if not mv: break
        if ply % 4 == 0 and len(vectors["notations"]) < 120:
            vectors["notations"].append({"board": to_json_board(board),
                                         "camp": camp,
                                         "moves": notations_of(board, camp)})
        chosen = random.choice(mv)
        history.append(ai_notation(chosen, ai_compute_push_targets(chosen)))
        if chosen.get("fugue") or chosen.get("mat_on") or chosen.get("fugue_by"):
            break
        board = chosen["board"]
        camp = "Noir" if camp == "Blanc" else "Blanc"
    games.append(history)

# ── 2. Fichiers .nmc complets ──
metas = [
    {"date": "2026-09-20 14:03", "player1": "nino", "player2": "deep grey",
     "blanc": "nino", "objectif": "partie", "cadence": "15",
     "result": "1-0", "method": "mat", "points": "1", "random": None},
    {"date": "2026-01-02 09:00", "player1": "Ada", "player2": "Bob",
     "blanc": "Bob", "objectif": "partie", "cadence": "zen",
     "result": "0-1", "method": "fugue", "points": "2", "random": "0418s"},
    {"date": "2025-12-31 23:59", "player1": "joueur \"guillemets\"",
     "player2": "accentué é à ü", "blanc": "accentué é à ü",
     "objectif": "partie", "cadence": "5", "result": "½-½",
     "method": "nulle", "points": "0", "random": None},
]
for meta, history in zip(metas, games):
    hist = [(n, None) for n in history]
    vectors["files"].append({
        "meta": meta,
        "moves": history,
        "content": make_nmc_content(meta, hist),
    })
# Une partie vide, et une partie à un seul coup : les deux bords de la boucle.
for meta, history in ((metas[0], []), (metas[1], [games[0][0]])):
    vectors["files"].append({
        "meta": meta, "moves": history,
        "content": make_nmc_content(meta, [(n, None) for n in history]),
    })

# ── 3. Contenus à relire ──
contents = [v["content"] for v in vectors["files"]]
contents += [
    # En-tête incomplet, coups sur plusieurs lignes.
    '[Date "2026-09-20 14:03"]\n[Joueur1 "nino"]\n\n1.Do1-Do2/Do8-Do7\n2.Ré1-Ré2/Ré8-Ré7',
    # Pas de ligne vide : l'en-tête s'arrête au premier coup.
    '[Date "x"]\n1.Do1-Do2',
    # Lignes vides en tête, espaces en fin de ligne, tabulations.
    '\n\n[Objectif "partie"]  \n\n  1.Do1-Do2   2.Ré1-Ré2  \n',
    # Une ligne d'en-tête bancale (pas de guillemets) : ignorée.
    '[Date 2026]\n[Cadence "zen"]\n\n1.Do1-Do2',
    # Coup unique sans numéro de tour.
    'Do1-Do2',
    # Poussées, manœuvres, fugues et suffixes de fin.
    '[Methode "fugue"]\n\n1.Do1-Do2>/Si8-Si7>La7Si6  2.(Do2Ré1)-Do3/Mi8*',
    # Contenu vide.
    '',
    # Que des en-têtes.
    '[Date "x"]\n[Joueur1 "y"]\n',
    # Un tour incomplet : Blanc a joué, Noir non.
    '[Date "x"]\n\n1.Do1-Do2/Do8-Do7  2.Ré1-Ré2',
]
for content in contents:
    meta, moves_text = parse_nmc_content(content)
    vectors["parses"].append({
        "content": content,
        "meta": meta,
        "moves_text": moves_text,
        "moves": parse_moves_text(moves_text),
    })

json.dump(vectors, open("../test/fixtures/nmc_vectors.json", "w", encoding="utf-8"),
          ensure_ascii=False)
tot = sum(len(v["moves"]) for v in vectors["notations"])
print(f"{len(vectors['notations'])} positions, {tot} notations")
print(f"{len(vectors['files'])} fichiers, {len(vectors['parses'])} relectures")
