COLS, ROWS = 7, 8

RALLY = frozenset({2,3,4})

def _dg_clone(board):
    # Les pièces (dicts {"type","camp"}) ne sont jamais modifiées en place dans
    # le moteur : on déplace les références, on ne mute pas leur contenu. On peut
    # donc partager les références de pièces et ne copier que la structure des
    # colonnes. Beaucoup plus rapide que dict(p) pour chaque pièce, et strictement
    # équivalent en résultat (vérifié : aucun p["type"]=... dans le code).
    return [col[:] for col in board]

def _dg_on_board(c, r):
    return 0 <= c < COLS and 0 <= r < ROWS

def _dg_is_round(p):
    return p is not None and p["type"] in ("Nurse", "Héritier")

def _dg_is_square(p):
    return p is not None and p["type"] in ("Soldat", "Garde")

def _dg_has_round_nbr(board, c, r):
    for dc in (-1, 0, 1):
        for dr in (-1, 0, 1):
            if dc == dr == 0: continue
            nc, nr = c + dc, r + dr
            if _dg_on_board(nc, nr) and _dg_is_round(board[nc][nr]):
                return True
    return False

def _dg_has_square_nbr(board, c, r):
    for dc in (-1, 0, 1):
        for dr in (-1, 0, 1):
            if dc == dr == 0: continue
            nc, nr = c + dc, r + dr
            if _dg_on_board(nc, nr) and _dg_is_square(board[nc][nr]):
                return True
    return False

def _dg_group_of(board, c, r):
    p = board[c][r]
    if not _dg_is_square(p): return set()
    camp = p["camp"]
    seen = {(c, r)}; stack = [(c, r)]
    while stack:
        x, y = stack.pop()
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if dx == dy == 0: continue
                nx, ny = x + dx, y + dy
                if (nx, ny) in seen: continue
                if not _dg_on_board(nx, ny): continue
                q = board[nx][ny]
                if _dg_is_square(q) and q["camp"] == camp:
                    seen.add((nx, ny)); stack.append((nx, ny))
    return seen

def _dg_rally_row(camp):
    return 8 if camp == "Blanc" else -1

def _dg_is_fugue_dest(c, r, piece):
    if piece["type"] != "Héritier": return False
    if c not in RALLY: return False
    return r == _dg_rally_row(piece["camp"])

def _dg_push_activated(ptype, dc, dr):
    if ptype == "Soldat": return abs(dc) + abs(dr) == 1
    if ptype == "Garde":  return abs(dc) == abs(dr) == 1
    return False

def dg_generate_moves(board, camp):
    """Génère tous les coups légaux pour `camp`.
    Chaque coup = dict {board: nouveau_board, kind: ..., fugue: bool, mat_on: camp|None,
                        ejected: int, moved_cells: [...]}.
    On ne simule PAS les sous-choix de poussée multiples : on pousse toutes les
    directions activées (comportement simple, suffisant pour l'IA)."""
    moves = []
    opp = "Noir" if camp == "Blanc" else "Blanc"

    for c in range(COLS):
        for r in range(ROWS):
            p = board[c][r]
            if not p or p["camp"] != camp:
                continue

            # ── Pièces rondes (Nurse, Héritier) ──
            if _dg_is_round(p):
                if not _dg_has_round_nbr(board, c, r):
                    continue   # isolée → immobile
                # Déplacements simples (8 directions, 1 case)
                for dc in (-1, 0, 1):
                    for dr in (-1, 0, 1):
                        if dc == dr == 0: continue
                        nc, nr = c + dc, r + dr
                        # Fugue ?
                        if p["type"] == "Héritier" and _dg_is_fugue_dest(nc, nr, p):
                            nb = _dg_clone(board)
                            nb[c][r] = None
                            moves.append({"board": nb, "kind": "fugue",
                                          "fugue": True, "mat_on": None,
                                          "ejected": 0, "moved_cells": [(nc, nr)],
                                          "from": (c, r)})
                            continue
                        if not _dg_on_board(nc, nr): continue
                        if board[nc][nr] is not None: continue
                        nb = _dg_clone(board)
                        nb[nc][nr] = nb[c][r]; nb[c][r] = None
                        moves.append({"board": nb, "kind": "move",
                                      "fugue": False, "mat_on": None,
                                      "ejected": 0, "moved_cells": [(nc, nr)],
                                      "from": (c, r)})
                # Sauts simples ET multisauts : exploration récursive en
                # maintenant un board simulé. Règle : on ne peut pas re-sauter
                # IMMÉDIATEMENT par-dessus la même nurse qu'au saut précédent
                # (mais on peut la re-sauter plus tard).
                start = (c, r)
                start_piece = board[c][r]
                sim_board = _dg_clone(board)
                sim_board[c][r] = None
                # to_explore : (pos, visited_cases, last_jumped_cell_or_None)
                to_explore = [(c, r, frozenset({(c, r)}), None)]
                jump_destinations = set()
                while to_explore:
                    cur_c, cur_r, visited, last_jumped = to_explore.pop()
                    for jdc in (-1, 0, 1):
                        for jdr in (-1, 0, 1):
                            if jdc == 0 and jdr == 0: continue
                            mc, mr = cur_c + jdc, cur_r + jdr       # case sautée
                            nc, nr = cur_c + 2*jdc, cur_r + 2*jdr   # case d'arrivée

                            # Règle anti-aller-retour : on ne peut pas re-sauter
                            # immédiatement par-dessus la nurse qu'on vient de sauter
                            if last_jumped is not None and (mc, mr) == last_jumped:
                                continue

                            # Cas fugue par saut (Héritier seulement)
                            if start_piece["type"] == "Héritier" and \
                               _dg_is_fugue_dest(nc, nr, start_piece):
                                if _dg_on_board(mc, mr) and \
                                   _dg_is_round(sim_board[mc][mr]):
                                    nb = _dg_clone(board)
                                    nb[c][r] = None
                                    moves.append({"board": nb, "kind": "fugue",
                                                  "fugue": True, "mat_on": None,
                                                  "ejected": 0,
                                                  "moved_cells": [(nc, nr)],
                                                  "from": (c, r)})
                                continue

                            if not _dg_on_board(mc, mr): continue
                            if not _dg_on_board(nc, nr): continue
                            jumped = sim_board[mc][mr]
                            if jumped is None: continue
                            if not _dg_is_round(jumped): continue
                            if sim_board[nc][nr] is not None: continue
                            if (nc, nr) in visited: continue

                            if (nc, nr) not in jump_destinations:
                                jump_destinations.add((nc, nr))
                                nb = _dg_clone(board)
                                nb[nc][nr] = nb[c][r]; nb[c][r] = None
                                moves.append({"board": nb, "kind": "jump",
                                              "fugue": False, "mat_on": None,
                                              "ejected": 0,
                                              "moved_cells": [(nc, nr)],
                                              "from": (c, r)})
                            # On note la nurse qui vient d'être sautée
                            to_explore.append((nc, nr, visited | {(nc, nr)}, (mc, mr)))

            # ── Pièces carrées (Soldat, Garde) ──
            elif _dg_is_square(p):
                if not _dg_has_square_nbr(board, c, r):
                    continue   # isolée → immobile
                # Déplacement simple + poussée éventuelle
                for dc in (-1, 0, 1):
                    for dr in (-1, 0, 1):
                        if dc == dr == 0: continue
                        nc, nr = c + dc, r + dr
                        if not _dg_on_board(nc, nr): continue
                        if board[nc][nr] is not None: continue
                        nb = _dg_clone(board)
                        nb[nc][nr] = nb[c][r]; nb[c][r] = None
                        # Poussée activée ?
                        if _dg_push_activated(p["type"], dc, dr):
                            # Identifier les directions où il y a effectivement
                            # une pièce à pousser (case adjacente non vide).
                            if p["type"] == "Soldat":
                                all_push_dirs = [(-1, -1), (1, -1), (-1, 1), (1, 1)]
                            else:
                                all_push_dirs = [(0, -1), (0, 1), (-1, 0), (1, 0)]
                            available_dirs = []
                            for pdc, pdr in all_push_dirs:
                                ac, ar = nc + pdc, nr + pdr
                                if _dg_on_board(ac, ar) and nb[ac][ar] is not None:
                                    available_dirs.append((pdc, pdr))
                            # Toujours générer le déplacement sans pousser
                            moves.append({"board": _dg_clone(nb), "kind": "square",
                                          "fugue": False, "fugue_by": None,
                                          "mat_on": None,
                                          "ej_ally": 0, "ej_opp": 0,
                                          "ejected": 0, "total_pushed": 0,
                                          "push_dirs_used": [],
                                          "moved_cells": [(nc, nr)], "from": (c, r)})
                            # Puis générer toutes les combinaisons non vides
                            n_dirs = len(available_dirs)
                            for mask in range(1, 1 << n_dirs):
                                chosen = [available_dirs[i] for i in range(n_dirs)
                                          if mask & (1 << i)]
                                nb_var = _dg_clone(nb)
                                ej_ally, ej_opp, mat_on, fugue_by, total_pushed = (
                                    _dg_apply_pushes(nb_var, nc, nr, p["type"], camp,
                                                     dirs_to_use=chosen))
                                moves.append({"board": nb_var, "kind": "square",
                                              "fugue": False, "fugue_by": fugue_by,
                                              "mat_on": mat_on,
                                              "ej_ally": ej_ally, "ej_opp": ej_opp,
                                              "ejected": ej_ally + ej_opp,
                                              "total_pushed": total_pushed,
                                              "push_dirs_used": chosen,
                                              "moved_cells": [(nc, nr)], "from": (c, r)})
                        else:
                            # Poussée non activée : juste le déplacement
                            moves.append({"board": nb, "kind": "square",
                                          "fugue": False, "fugue_by": None,
                                          "mat_on": None,
                                          "ej_ally": 0, "ej_opp": 0,
                                          "ejected": 0, "total_pushed": 0,
                                          "push_dirs_used": [],
                                          "moved_cells": [(nc, nr)], "from": (c, r)})
                # Manœuvres de groupe (déplacer tout le groupe d'1 case)
                grp = _dg_group_of(board, c, r)
                if len(grp) >= 2:
                    for dc in (-1, 0, 1):
                        for dr in (-1, 0, 1):
                            if dc == dr == 0: continue
                            ok = True
                            for (gc, gr) in grp:
                                tc, tr = gc + dc, gr + dr
                                if not _dg_on_board(tc, tr): ok = False; break
                                tgt = board[tc][tr]
                                if tgt is not None and (tc, tr) not in grp:
                                    ok = False; break
                            if not ok: continue
                            nb = _dg_clone(board)
                            pieces = {(gc, gr): nb[gc][gr] for (gc, gr) in grp}
                            for (gc, gr) in grp:
                                nb[gc][gr] = None
                            for (gc, gr), pp in pieces.items():
                                nb[gc + dc][gr + dr] = pp
                            # Maître = (c, r) (la case d'origine du scan).
                            # moved_cells doit avoir le maître en premier pour
                            # que la notation/highlight parse correctement.
                            moved = [(c + dc, r + dr)]
                            for (gc, gr) in grp:
                                if (gc, gr) == (c, r): continue
                                moved.append((gc + dc, gr + dr))
                            from_cells_ordered = [(c, r)]
                            for (gc, gr) in grp:
                                if (gc, gr) == (c, r): continue
                                from_cells_ordered.append((gc, gr))
                            moves.append({"board": nb, "kind": "maneuver",
                                          "fugue": False, "mat_on": None,
                                          "ejected": 0, "moved_cells": moved,
                                          "from_cells": from_cells_ordered,
                                          "from": (c, r)})

            # ── Chevalier ──
            # Le Chevalier se déplace d'1 case dans les 8 directions, vers une
            # case vide, sans condition de voisinage et sans pousser. Il est
            # immortel (il ne peut pas être éjecté), mais il PEUT bloquer.
            elif p["type"] == "Chevalier":
                for dc in (-1, 0, 1):
                    for dr in (-1, 0, 1):
                        if dc == dr == 0: continue
                        nc, nr = c + dc, r + dr
                        if not _dg_on_board(nc, nr): continue
                        if board[nc][nr] is not None: continue
                        nb = _dg_clone(board)
                        nb[nc][nr] = nb[c][r]; nb[c][r] = None
                        moves.append({"board": nb, "kind": "knight",
                                      "fugue": False, "fugue_by": None,
                                      "mat_on": None, "ejected": 0,
                                      "moved_cells": [(nc, nr)], "from": (c, r)})
    return moves

def _dg_apply_pushes(board, c, r, ptype, camp, dirs_to_use=None):
    """Applique les poussées (lignes entières) depuis (c,r) après le déplacement.
    Si dirs_to_use est fourni : ne pousse que dans ce sous-ensemble de directions.
    Sinon : pousse dans toutes les directions de poussée activées.
    Retourne (ej_ally, ej_opp, mat_on, fugue_by, total_pushed)."""
    opp = "Noir" if camp == "Blanc" else "Blanc"
    if ptype == "Soldat":
        all_dirs = [(-1, -1), (1, -1), (-1, 1), (1, 1)]
    else:
        all_dirs = [(0, -1), (0, 1), (-1, 0), (1, 0)]
    dirs = dirs_to_use if dirs_to_use is not None else all_dirs
    ej_ally = 0
    ej_opp = 0
    mat_on = None
    fugue_by = None
    total_pushed = 0
    for dc, dr in dirs:
        # Construire la ligne de pièces consécutives depuis (c+dc, r+dr)
        line = []
        cc, rr = c + dc, r + dr
        while _dg_on_board(cc, rr):
            p = board[cc][rr]
            if p is None: break
            if p["type"] == "Chevalier":
                line = None
                break
            line.append((cc, rr, p))
            cc += dc; rr += dr
        if not line:
            continue
        for cc, rr, p in reversed(line):
            nc2, nr2 = cc + dc, rr + dr
            board[cc][rr] = None
            if _dg_on_board(nc2, nr2):
                board[nc2][nr2] = p
                total_pushed += 1
            else:
                if p["type"] == "Héritier" and nc2 in RALLY and (
                    (p["camp"] == "Blanc" and nr2 == 8) or
                    (p["camp"] == "Noir"  and nr2 == -1)):
                    fugue_by = p["camp"]
                elif p["type"] == "Héritier":
                    mat_on = p["camp"]
                    if p["camp"] == camp: ej_ally += 1
                    else:                  ej_opp += 1
                else:
                    if p["camp"] == camp: ej_ally += 1
                    else:                  ej_opp += 1
                total_pushed += 1
    return ej_ally, ej_opp, mat_on, fugue_by, total_pushed


def setup_initial():
    board = [[None]*ROWS for _ in range(COLS)]
    layout = ["Soldat","Garde","Soldat","Chevalier","Garde","Soldat","Garde"]
    for c,t in enumerate(layout):
        board[c][0] = {"type": t, "camp": "Blanc"}
        board[c][7] = {"type": t, "camp": "Noir"}
    for c in [1,2,4,5]:
        board[c][1] = {"type":"Nurse","camp":"Blanc"}
        board[c][6] = {"type":"Nurse","camp":"Noir"}
    board[0][1] = {"type":"Garde","camp":"Blanc"}
    board[6][1] = {"type":"Soldat","camp":"Blanc"}
    board[0][6] = {"type":"Garde","camp":"Noir"}
    board[6][6] = {"type":"Soldat","camp":"Noir"}
    board[3][0] = {"type":"Héritier","camp":"Blanc"}
    board[3][1] = {"type":"Nurse","camp":"Blanc"}
    board[3][2] = {"type":"Chevalier","camp":"Blanc"}
    board[3][7] = {"type":"Héritier","camp":"Noir"}
    board[3][6] = {"type":"Nurse","camp":"Noir"}
    board[3][5] = {"type":"Chevalier","camp":"Noir"}
    return board


def to_json_board(board):
    return [[(None if p is None else {"type":p["type"],"camp":p["camp"]})
             for p in col] for col in board]
