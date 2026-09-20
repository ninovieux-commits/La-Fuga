"""Génère des vecteurs de test depuis le moteur Python de référence.

Pour chaque position : le plateau, le camp au trait, et la signature triée des
plateaux résultants. Le test Dart rejoue exactement la même chose et compare.
"""
import json, random, sys
sys.path.insert(0, ".")
from py_engine_ref import (dg_generate_moves, COLS, ROWS, RALLY,
                           setup_initial, to_json_board)

def bkey(board):
    parts=[]
    for c in range(COLS):
        for r in range(ROWS):
            p=board[c][r]
            parts.append("." if p is None else p["type"][0]+p["camp"][0])
    return "".join(parts)

def _norm_cells(m):
    cells = list(m.get("moved_cells", []))
    if m.get("kind") == "maneuver" and len(cells) > 1:
        cells = [cells[0]] + sorted(cells[1:])
    return ",".join(str(x) for x in cells)


def signature(moves):
    """Signature complète d'un coup : plateau résultant + métadonnées."""
    sigs=[]
    for m in moves:
        sigs.append("|".join([
            bkey(m["board"]),
            m.get("kind",""),
            "F" if m.get("fugue") else "-",
            (m.get("fugue_by") or "-"),
            (m.get("mat_on") or "-"),
            str(m.get("ej_ally",0)), str(m.get("ej_opp",0)),
            str(m.get("total_pushed",0)),
            str(m.get("from")),
            # Manœuvre : le Python itère un set, donc l'ordre de la queue est
            # un artefact d'implémentation. On normalise (maître en tête, reste
            # trié) pour comparer le contenu, qui seul fait sens.
            _norm_cells(m),
        ]))
    return sorted(sigs)

random.seed(20260919)
vectors=[]
board = setup_initial()
camp = "Blanc"

# Position initiale, les deux camps
for cp in ("Blanc","Noir"):
    mv = dg_generate_moves(board, cp)
    vectors.append({"board": to_json_board(board), "camp": cp,
                    "count": len(mv), "sigs": signature(mv)})

# Marche aléatoire : 180 positions réparties sur plusieurs parties
for game in range(12):
    board = setup_initial()
    camp = "Blanc"
    for ply in range(40):
        mv = dg_generate_moves(board, camp)
        if not mv: break
        if ply % 3 == 0 and len(vectors) < 200:
            vectors.append({"board": to_json_board(board), "camp": camp,
                            "count": len(mv), "sigs": signature(mv)})
        chosen = random.choice(mv)
        if chosen.get("fugue") or chosen.get("mat_on") or chosen.get("fugue_by"):
            break
        board = chosen["board"]
        camp = "Noir" if camp=="Blanc" else "Blanc"

json.dump(vectors, open("../test/fixtures/move_vectors.json","w",encoding="utf-8"),
          ensure_ascii=False)
tot = sum(v["count"] for v in vectors)
print(f"{len(vectors)} positions, {tot} coups au total")
print("min/max coups par position :",
      min(v['count'] for v in vectors), "/", max(v['count'] for v in vectors))
