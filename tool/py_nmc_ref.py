"""Couche `.nmc` de Kivy, extraite telle quelle de main.py.

Recopié sans retouche : `cell_to_notation`, `notation_to_cell`,
`parse_cells_concat`, `format_nmc_moves`, `make_nmc_content`,
`parse_nmc_content`, `_parse_moves_text` et `_ai_notation`. C'est la
référence : si le Dart s'en écarte, c'est le Dart qui a tort.
"""
import re

COLS, ROWS = 7, 8

NOTES = ["Do", "Ré", "Mi", "Fa", "Sol", "La", "Si"]


def cell_to_notation(c, r):
    if not (0 <= c < COLS and 0 <= r < ROWS): return None
    return f"{NOTES[c]}{r + 1}"


def notation_to_cell(notation):
    if not notation: return None
    for i, note in enumerate(NOTES):
        if notation.startswith(note):
            rest = notation[len(note):]
            try:
                num = int(rest)
                if 1 <= num <= 8:
                    return (i, num - 1)
            except ValueError:
                pass
            return None
    return None


def parse_cells_concat(s):
    cells = []
    i = 0
    while i < len(s):
        matched = False
        for note in NOTES:
            if s[i:i+len(note)] == note:
                j = i + len(note)
                k = j
                while k < len(s) and s[k].isdigit():
                    k += 1
                if k > j:
                    cell = notation_to_cell(s[i:k])
                    if cell is None: return None
                    cells.append(cell)
                    i = k
                    matched = True
                    break
        if not matched: return None
    return cells


def format_nmc_moves(history):
    parts = []
    i = 0
    turn_num = 1
    while i < len(history):
        blanc = history[i][0] if i < len(history) else ""
        noir  = history[i+1][0] if i + 1 < len(history) else ""
        s = f"{turn_num}.{blanc}"
        if noir:
            s += f"/{noir}"
        parts.append(s)
        i += 2
        turn_num += 1
    return "  ".join(parts)


def make_nmc_content(meta, history):
    header = (
        f"[Date \"{meta['date']}\"]\n" +
        f"[Joueur1 \"{meta['player1']}\"]\n" +
        f"[Joueur2 \"{meta['player2']}\"]\n" +
        f"[Blanc \"{meta.get('blanc', meta['player1'])}\"]\n" +
        f"[Objectif \"{meta['objectif']}\"]\n" +
        f"[Cadence \"{meta['cadence']}\"]\n" +
        f"[Resultat \"{meta['result']}\"]\n" +
        f"[Methode \"{meta['method']}\"]\n" +
        f"[Points \"{meta['points']}\"]\n"
    )
    if meta.get("random"):
        header += f"[Random \"{meta['random']}\"]\n"
    header += "\n"
    return header + format_nmc_moves(history)


def parse_nmc_content(content):
    meta = {}
    lines = content.split("\n")
    move_lines = []
    in_header = True
    for line in lines:
        line = line.rstrip()
        if in_header and line.startswith("[") and line.endswith("]"):
            m = re.match(r'\[(\w+)\s+"(.*)"\]', line)
            if m:
                meta[m.group(1).lower()] = m.group(2)
        elif line.strip() == "":
            if in_header:
                in_header = False
        else:
            in_header = False
            move_lines.append(line)
    moves_text = " ".join(move_lines).strip()
    return meta, moves_text


def parse_moves_text(text):
    moves = []
    tokens = re.split(r'\s+', text.strip())
    for token in tokens:
        if not token: continue
        m = re.match(r'^(\d+)\.(.*)$', token)
        if m:
            rest = m.group(2)
        else:
            rest = token
        if "/" in rest:
            blanc, noir = rest.split("/", 1)
        else:
            blanc, noir = rest, ""
        if blanc:
            moves.append(blanc)
        if noir:
            moves.append(noir)
    return moves


def ai_compute_push_targets(move):
    """Version `push_dirs_used` de `_ai_compute_push_targets` (le repli par
    comparaison de plateaux ne sert que si la clé manque, ce qui n'arrive pas
    avec le générateur)."""
    if move["kind"] != "square":
        return []
    dirs_used = move.get("push_dirs_used")
    if dirs_used is None:
        return []
    end_c, end_r = move["moved_cells"][0]
    targets = []
    for dc, dr in dirs_used:
        tc, tr = end_c + dc, end_r + dr
        if 0 <= tc < COLS and 0 <= tr < ROWS:
            targets.append((tc, tr))
    return targets


def ai_notation(move, push_targets=None):
    frm = move["from"]
    start_str = cell_to_notation(*frm)
    kind = move["kind"]
    if move["fugue"]:
        return f"{start_str}*"
    if kind == "maneuver":
        from_cells = move.get("from_cells", [move["from"]])
        ordered = [move["from"]] + [c for c in from_cells if c != move["from"]]
        cells_str = "".join(cell_to_notation(c[0], c[1]) for c in ordered)
        dest = move["moved_cells"][0]
        return f"({cells_str})-{cell_to_notation(*dest)}"
    dest = move["moved_cells"][0]
    dest_str = cell_to_notation(*dest)
    base = f"{start_str}-{dest_str}"
    if kind == "square" and push_targets:
        base += ">"
        cells_str = "".join(cell_to_notation(c[0], c[1]) for c in push_targets
                            if 0 <= c[0] < COLS and 0 <= c[1] < ROWS
                            and cell_to_notation(c[0], c[1]) is not None)
        base += cells_str
    return base


def build_move_notation(start, end_cell, is_maneuver=False, maneuver_pieces=(),
                        is_push=False, push_targets=(), pushable_dirs=()):
    """`_build_move_notation` : le chemin HUMAIN, qui écrit `Do1-Do2>` tout
    court quand toutes les directions disponibles ont été poussées."""
    if start is None: return ""
    start_str = cell_to_notation(*start)
    if end_cell is None or not (0 <= end_cell[0] < COLS and 0 <= end_cell[1] < ROWS):
        return f"{start_str}*"
    end_str = cell_to_notation(*end_cell)
    if is_maneuver:
        pieces_str = "".join(cell_to_notation(*c) for c in maneuver_pieces)
        return f"({pieces_str})-{end_str}"
    if is_push:
        base = f"{start_str}-{end_str}>"
        pushed = set(push_targets)
        all_dirs = set(pushable_dirs)
        if pushed == all_dirs and all_dirs:
            return base
        targets_str = "".join(cell_to_notation(*c) for c in push_targets
                              if cell_to_notation(*c) is not None)
        return base + targets_str
    return f"{start_str}-{end_str}"
