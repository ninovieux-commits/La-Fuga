#!/usr/bin/env python3
"""Mesure ce que valent les sons, instrument par instrument.

Je ne peux pas les écouter. Je peux en revanche mesurer ce qui distingue un
vrai instrument d'une sinusoïde habillée, et c'est ce que fait ce fichier.

Pour chaque note :
  duree_utile   à partir de quand le signal est sous -60 dB de son crête.
                Si elle égale la durée du fichier, la note est COUPÉE : le
                fondu de fin ampute un son encore vivant, et ça s'entend
                comme une porte qui se ferme.
  t60           temps de décroissance de 60 dB, extrapolé sur la pente.
  attaque       temps pour atteindre 90 % du crête.
  centroide     centre de gravité du spectre, en Hz : la « brillance ».
  chute_centro  de combien la brillance tombe entre le début et la fin. Un
                instrument réel s'assombrit en s'éteignant — les partiels
                aigus meurent les premiers. Proche de 1, le son est figé.
  crete / rms   facteur de crête : un son percussif est élevé, un son tenu bas.

Usage : python3 tool/analyse_sons.py [dossier_assets] [--notes do2,do5]
"""
import cmath
import math
import os
import sys
import wave

RATE = 44100
INSTRUMENTS = ['piano', 'guitare', 'orgue', 'cloche']


def lire(path):
    with wave.open(path, 'rb') as w:
        n = w.getnframes()
        raw = w.readframes(n)
    return [int.from_bytes(raw[i:i + 2], 'little', signed=True) / 32768.0
            for i in range(0, len(raw), 2)]


def enveloppe(buf, fenetre=441):
    """Énergie par tranche de 10 ms."""
    out = []
    for i in range(0, len(buf) - fenetre, fenetre):
        bloc = buf[i:i + fenetre]
        out.append(math.sqrt(sum(v * v for v in bloc) / fenetre))
    return out


def duree_utile(env, seuil_db=-60.0):
    if not env:
        return 0.0
    top = max(env)
    if top <= 0:
        return 0.0
    seuil = top * 10 ** (seuil_db / 20)
    dernier = 0
    for i, v in enumerate(env):
        if v >= seuil:
            dernier = i
    return (dernier + 1) * 0.01


def t60(env):
    """Pente de décroissance, en secondes pour 60 dB."""
    top = max(env) if env else 0
    if top <= 0:
        return 0.0
    pic = env.index(top)
    pts = [(i, 20 * math.log10(v / top))
           for i, v in enumerate(env[pic:], pic) if v > top * 1e-4]
    if len(pts) < 5:
        return 0.0
    # Régression sur la portion -5 dB à -35 dB : le début et la queue mentent.
    util = [(i, d) for i, d in pts if -35 <= d <= -5]
    if len(util) < 3:
        util = pts
    n = len(util)
    sx = sum(i for i, _ in util)
    sy = sum(d for _, d in util)
    sxy = sum(i * d for i, d in util)
    sxx = sum(i * i for i, _ in util)
    den = n * sxx - sx * sx
    if den == 0:
        return 0.0
    pente = (n * sxy - sx * sy) / den      # dB par tranche de 10 ms
    if pente >= 0:
        return 0.0
    return -60.0 / pente * 0.01


def attaque(env):
    top = max(env) if env else 0
    if top <= 0:
        return 0.0
    for i, v in enumerate(env):
        if v >= 0.9 * top:
            return (i + 1) * 0.01
    return 0.0


def dft_centroide(bloc):
    """Centre de gravité spectral, par DFT sur 2048 points."""
    n = 2048
    if len(bloc) < n:
        bloc = bloc + [0.0] * (n - len(bloc))
    bloc = bloc[:n]
    # Fenêtre de Hann.
    w = [0.5 - 0.5 * math.cos(2 * math.pi * i / n) for i in range(n)]
    x = [bloc[i] * w[i] for i in range(n)]
    # FFT itérative (radix-2).
    j = 0
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j |= bit
        if i < j:
            x[i], x[j] = x[j], x[i]
    X = [complex(v, 0.0) for v in x]
    pas = 2
    while pas <= n:
        ang = -2j * math.pi / pas
        wp = cmath.exp(ang)
        for k in range(0, n, pas):
            w_ = 1 + 0j
            for m in range(pas // 2):
                u = X[k + m]
                t = w_ * X[k + m + pas // 2]
                X[k + m] = u + t
                X[k + m + pas // 2] = u - t
                w_ *= wp
        pas <<= 1
    mags = [abs(X[i]) for i in range(n // 2)]
    tot = sum(mags)
    if tot <= 0:
        return 0.0
    return sum(mags[i] * (i * RATE / n) for i in range(n // 2)) / tot


def mesure(path):
    buf = lire(path)
    env = enveloppe(buf)
    crete = max((abs(v) for v in buf), default=0.0)
    rms = math.sqrt(sum(v * v for v in buf) / max(1, len(buf)))
    tot = len(buf) / RATE
    util = duree_utile(env)
    # Brillance au début, puis à mi-parcours de la partie utile.
    # La fenetre partait a 20 ms, c'est-a-dire APRES l'attaque : le chiff de
    # l'orgue et le marteau du piano tombaient dedans sans etre vus. On lit
    # desormais des les premieres millisecondes.
    debut = dft_centroide(buf[int(0.003 * RATE):int(0.003 * RATE) + 2048])
    pos = int(max(0.1, util * 0.6) * RATE)
    fin = dft_centroide(buf[pos:pos + 2048]) if pos + 2048 <= len(buf) else 0.0
    # Niveau au moment ou l'etouffoir se pose, par rapport au crete de la
    # note. C'est LE critere : a -5 dB c'est une porte qui claque, a -30 dB
    # c'est une touche qu'on relache.
    if len(env) >= 8:
        top_env = max(env)
        fin_env = max(env[-4:])
        niveau_fin = (20 * math.log10(fin_env / top_env)
                      if top_env > 0 and fin_env > 0 else -120.0)
    else:
        niveau_fin = 0.0
    return {
        'niveau_fin': niveau_fin,
        'duree': tot,
        'utile': util,
        'coupee': util >= tot - 0.02,
        't60': t60(env),
        'attaque': attaque(env),
        'centroide': debut,
        'chute_centro': (fin / debut) if debut > 0 else 0.0,
        'crete': crete,
        'rms': rms,
        'facteur_crete': (crete / rms) if rms > 0 else 0.0,
    }


def main():
    root = 'assets/sounds'
    notes = ['do2', 'do3', 'do4', 'do5']
    args = sys.argv[1:]
    if args and not args[0].startswith('--'):
        root = args[0]
        args = args[1:]
    for a in args:
        if a.startswith('--notes'):
            notes = a.split('=', 1)[1].split(',')

    for inst in INSTRUMENTS:
        print('\n=== %s ===' % inst)
        print('%-6s %7s %7s %7s %8s %9s %7s %7s %9s' %
              ('note', 'duree', 'utile', 't60', 'attaque',
               'centroide', 'chute', 'crete/rms', 'fin'))
        coupees = 0
        for name in notes:
            path = os.path.join(root, inst, name + '.wav')
            if not os.path.isfile(path):
                continue
            m = mesure(path)
            if m['coupee']:
                coupees += 1
            print('%-6s %6.2fs %6.2fs %6.2fs %7.0fms %8.0fHz %6.2f %8.1f %6.0fdB %s'
                  % (name, m['duree'], m['utile'], m['t60'],
                     m['attaque'] * 1000, m['centroide'], m['chute_centro'],
                     m['facteur_crete'], m['niveau_fin'],
                     '← claque' if m['niveau_fin'] > -22 else ''))
        if coupees:
            print('  → %d note(s) encore vivantes quand le fichier s arrête'
                  % coupees)


if __name__ == '__main__':
    main()
