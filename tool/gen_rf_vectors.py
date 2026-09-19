"""Vecteurs Random Fuga : les 3500 positions, signées par leur clé de plateau."""
import json, itertools, sys
COLS, ROWS = 7, 8
_RF_COMBOS = list(itertools.combinations(range(8), 4))

def rf_parse_code(code):
    try:
        code=(code or "").strip(); sym=code[0]
        if sym not in (".","/"): return None
        ps,ds=code[1:].split("-"); P=int(ps); D=int(ds)
        if not (1<=P<=25 and 1<=D<=70): return None
        return (sym,P,D)
    except Exception: return None

def rf_build_board(code):
    parsed=rf_parse_code(code)
    if not parsed: return None
    sym,P,D=parsed
    board=[[None]*ROWS for _ in range(COLS)]
    iH=(P-1)//5; iC=(P-1)%5
    col_H=1+iH; col_C=1+iC
    board[col_H][0]={"type":"Héritier","camp":"Blanc"}
    board[col_C][2]={"type":"Chevalier","camp":"Blanc"}
    for c in range(1,6): board[c][1]={"type":"Nurse","camp":"Blanc"}
    milieu=[c for c in range(1,6) if c!=col_H]
    slots=[(0,1),(0,0)]+[(c,0) for c in milieu]+[(6,0),(6,1)]
    garde_idx=_RF_COMBOS[D-1]
    for i,(c,r) in enumerate(slots):
        board[c][r]={"type":"Garde" if i in garde_idx else "Soldat","camp":"Blanc"}
    for c in range(COLS):
        for r in range(3):
            p=board[c][r]
            if not p: continue
            nc,nr=(c,7-r) if sym=="/" else (6-c,7-r)
            board[nc][nr]={"type":p["type"],"camp":"Noir"}
    return board

def bkey(board):
    return "".join("." if board[c][r] is None else
                   board[c][r]["type"][0]+board[c][r]["camp"][0]
                   for c in range(COLS) for r in range(ROWS))

out={}
for sym in (".","/"):
    for P in range(1,26):
        for D in range(1,71):
            code="%s%02d-%02d"%(sym,P,D)
            out[code]=bkey(rf_build_board(code))
json.dump(out, open("../test/fixtures/random_fuga.json","w",encoding="utf-8"))
print(f"{len(out)} codes Random Fuga générés")
# Contrôle : même matériel partout ?
import collections
mats=set()
for k in out.values():
    mats.add(tuple(sorted(collections.Counter(
        k[i:i+2] for i in range(0,len(k),2)).items())))
print(f"{len(mats)} composition(s) de matériel distincte(s) (doit être 1)")
print(sorted(mats)[0])
