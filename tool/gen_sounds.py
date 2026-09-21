#!/usr/bin/env python3
"""Resynthétise les quatre instruments de La Fuga.

Les fichiers d'origine étaient une synthèse additive simple : des sinusoïdes
harmoniques sous une enveloppe exponentielle. On garde EXACTEMENT leurs noms,
leurs hauteurs, leurs durées (au nombre d'échantillons près) et leur niveau
crête ; on remplace la façon de fabriquer le son par un modèle physique de
chaque instrument.

- piano   : cordes multiples légèrement désaccordées, partiels inharmoniques
            (raideur de la corde), décroissance plus rapide dans l'aigu, et
            bruit de marteau à l'attaque.
- guitare : corde pincée de Karplus-Strong (ligne à retard rebouclée sur un
            filtre passe-bas), position de pincement, et résonance de caisse.
- orgue   : jeux de tirettes (16', 8', 5⅓', 4', 2⅔', 2', 1⅗', 1⅓', 1'),
            souffle d'attaque, léger battement entre tuyaux.
- cloche  : partiels INHARMONIQUES de cloche (bourdon, prime, tierce
            mineure, quinte, nominale…), chacun avec sa propre extinction, et
            battements entre partiels jumeaux.

Hauteurs : tempérament égal, la3 = la 440. Le chiffre du nom est l'octave de
Kivy — `do2` est le do3 scientifique (130,81 Hz).

Usage : python3 tool/gen_sounds.py [dossier_assets]
"""

import math
import os
import random
import struct
import sys
import wave
import zlib

RATE = 44100
NOTES = ['do', 're', 'mi', 'fa', 'sol', 'la', 'si']
SEMITONES = {'do': 0, 're': 2, 'mi': 4, 'fa': 5, 'sol': 7, 'la': 9, 'si': 11}
OCTAVES = [2, 3, 4, 5]
INSTRUMENTS = ['piano', 'guitare', 'orgue', 'cloche']



def freq_of(note, octave):
    """Fréquence d'une note nommée à la Kivy. `do2` = do3 scientifique."""
    semi = SEMITONES[note]
    midi = 12 * (octave + 2) + semi  # do2 -> midi 48 (do3)
    return 440.0 * 2 ** ((midi - 69) / 12)


# ── Briques communes ────────────────────────────────────────────────────────

def silence(n):
    return [0.0] * n


def add_partial(buf, freq, amp, decay, start=0, phase=0.0, attack=0.002):
    """Ajoute une sinusoïde amortie, avec une attaque douce (anti-clic)."""
    n = len(buf)
    if freq <= 0 or freq >= RATE / 2:
        return
    w = 2 * math.pi * freq / RATE
    a_len = max(1, int(attack * RATE))
    for i in range(start, n):
        t = (i - start) / RATE
        env = math.exp(-t / decay)
        if env < 1e-4:
            break
        k = i - start
        if k < a_len:
            env *= 0.5 - 0.5 * math.cos(math.pi * k / a_len)
        buf[i] += amp * env * math.sin(w * k + phase)


def add_noise_burst(buf, amp, length, start=0, cutoff=0.35, rng=None):
    """Souffle court et sourd : le bruit du marteau, du plectre, de l'air."""
    rng = rng or random
    n = min(len(buf), start + int(length * RATE))
    prev = 0.0
    total = max(1, n - start)
    for i in range(start, n):
        white = rng.uniform(-1, 1)
        prev = prev + cutoff * (white - prev)  # passe-bas à un pôle
        k = (i - start) / total
        buf[i] += amp * prev * (1 - k) ** 2


def fade_in(buf, seconds=0.002):
    """Départ à zéro : un fichier qui commence sur une valeur non nulle claque."""
    f = min(len(buf), int(seconds * RATE))
    for i in range(f):
        buf[i] *= 0.5 - 0.5 * math.cos(math.pi * i / f)


def block_dc(buf):
    """Retire la composante continue : elle ne s'entend pas, mange la réserve
    de niveau et fait souffrir les haut-parleurs."""
    prev_in = prev_out = 0.0
    for i, v in enumerate(buf):
        out = v - prev_in + 0.9995 * prev_out
        prev_in = v
        prev_out = out
        buf[i] = out


def fade_out(buf, seconds=0.025):
    """Extinction finale : un fichier ne doit jamais se couper net."""
    n = len(buf)
    f = min(n, int(seconds * RATE))
    for i in range(f):
        buf[n - f + i] *= 0.5 + 0.5 * math.cos(math.pi * i / f)


def normalise(buf, peak):
    top = max((abs(v) for v in buf), default=0.0)
    if top <= 0:
        return buf
    g = peak / top
    return [v * g for v in buf]


# ── Les quatre instruments ──────────────────────────────────────────────────

def piano(freq, n, rng):
    """Corde frappée : partiels inharmoniques, trois cordes désaccordées."""
    buf = silence(n)
    # Raideur de la corde : les partiels s'écartent de l'harmonique pur, et
    # d'autant plus haut qu'on monte. C'est ce qui donne son grain au piano.
    stiffness = 0.00035 * (freq / 262.0) ** 1.2
    tau0 = 0.38 * (262.0 / freq) ** 0.35     # l'aigu s'éteint plus vite
    strings = [(-0.00022, 0.5), (0.0, 1.0), (0.00025, 0.45)]
    for k in range(1, 26):
        inharm = math.sqrt(1 + stiffness * k * k)
        # Point de frappe au huitième de la corde : le 8e partiel s'annule.
        hammer = abs(math.sin(k * math.pi / 8.0)) ** 0.5
        amp = hammer / k ** 1.30
        if amp < 0.0008:
            continue
        decay = tau0 / (1 + 0.62 * (k - 1))
        for detune, weight in strings:
            f = freq * k * inharm * (1 + detune)
            add_partial(buf, f, amp * weight, decay,
                        phase=rng.uniform(0, 2 * math.pi), attack=0.0015)
    add_noise_burst(buf, 0.22, 0.007, cutoff=0.55, rng=rng)
    return buf


def guitare(freq, n, rng):
    """Corde pincée de Karplus-Strong, avec caisse."""
    buf = silence(n)
    # Le filtre de boucle (moyenne de deux échantillons) retarde d'un demi
    # échantillon : sans le retrancher, les aigus sonneraient faux.
    delay = RATE / freq - 0.5
    length = int(delay)
    frac = delay - length
    if length < 2:
        return buf

    # Excitation : la corde est tirée en un point, d'où un profil triangulaire
    # dont le sommet est au point de pincement, sali d'un peu de bruit.
    line = [0.0] * (length + 2)
    pluck = 0.22            # pincé au cinquième de la corde
    prev = 0.0
    for i in range(length + 1):
        white = rng.uniform(-1, 1)
        prev = prev + 0.45 * (white - prev)
        u = i / length
        shape = u / pluck if u < pluck else (1 - u) / (1 - pluck)
        line[i] = shape * (0.82 + 0.18 * prev)

    # La corde est tirée d'un seul côté : sa moyenne n'est pas nulle, et le
    # filtre de boucle la garderait indéfiniment. On la retire d'emblée.
    mean = sum(line[:length + 1]) / (length + 1)
    for i in range(length + 1):
        line[i] -= mean

    # Boucle : moyenne de deux échantillons (l'aigu se perd plus vite) et
    # amortissement réglé sur un temps d'extinction plausible — une basse
    # tient plus longtemps qu'un aigu.
    #
    # La lecture se fait entre l'échantillon d'il y a `length` et celui d'il y
    # a `length + 1` : mélanger vers le PLUS ANCIEN allonge le retard de
    # `frac`. Mélanger dans l'autre sens raccourcirait la corde, et la note
    # serait fausse dans l'aigu.
    decay_time = min(2.8, max(0.9, 2.5 * (200.0 / freq) ** 0.35))
    rho = math.exp(math.log(0.001) / (freq * decay_time))
    size = length + 2
    line = line[:size] + [0.0] * max(0, size - len(line))
    write = 0
    last = 0.0
    for i in range(n):
        r = (write - length) % size
        older = (write - length - 1) % size
        cur = line[r] + frac * (line[older] - line[r])
        buf[i] = cur
        line[write] = rho * 0.5 * (cur + last)
        last = cur
        write = (write + 1) % size

    # Caisse : deux résonances basses, à gain unitaire pour ne pas gonfler.
    for f_body, q, amp in ((99.0, 0.996, 0.18), (196.0, 0.994, 0.10)):
        w = 2 * math.pi * f_body / RATE
        c1 = 2 * q * math.cos(w)
        c2 = -q * q
        gain = amp * (1 - q)
        y1 = y2 = 0.0
        for i in range(n):
            y = buf[i] + c1 * y1 + c2 * y2
            y2, y1 = y1, y
            buf[i] += y * gain
    block_dc(buf)
    return buf


def orgue(freq, n, rng):
    """Tuyaux : neuf tirettes, souffle d'attaque, léger battement."""
    buf = silence(n)
    # Tirettes, de 0 à 8, dans l'ordre 16' 8' 5⅓' 4' 2⅔' 2' 1⅗' 1⅓' 1'.
    drawbars = [(0.5, 7), (1.0, 8), (1.5, 5), (2.0, 6),
                (3.0, 4), (4.0, 3), (5.0, 2), (6.0, 2), (8.0, 3)]
    attack = 0.020
    release = 0.045
    a_len = int(attack * RATE)
    r_len = int(release * RATE)
    for ratio, level in drawbars:
        f = freq * ratio
        if f >= RATE / 2:
            continue
        amp = (level / 8.0) ** 1.6
        # Chaque tuyau est un peu faux : c'est ce qui fait respirer l'orgue.
        f *= 1 + rng.uniform(-0.0012, 0.0012)
        w = 2 * math.pi * f / RATE
        ph = rng.uniform(0, 2 * math.pi)
        for i in range(n):
            env = 1.0
            if i < a_len:
                env = 0.5 - 0.5 * math.cos(math.pi * i / a_len)
            elif i > n - r_len:
                env = 0.5 - 0.5 * math.cos(math.pi * (n - i) / r_len)
            buf[i] += amp * env * math.sin(w * i + ph)
    add_noise_burst(buf, 0.12, 0.030, cutoff=0.25, rng=rng)
    return buf


def cloche(freq, n, rng):
    """Cloche : partiels inharmoniques, chacun avec son extinction.

    Les rapports sont ceux d'une cloche accordée — bourdon à l'octave
    inférieure, prime, tierce MINEURE, quinte, nominale à l'octave… C'est la
    tierce mineure qui donne à toute cloche sa couleur un peu triste.
    """
    buf = silence(n)
    partials = [
        (0.50, 0.55, 1.35),   # bourdon
        (1.00, 1.00, 1.10),   # prime (la note entendue)
        (1.19, 0.52, 0.80),   # tierce mineure
        (1.50, 0.38, 0.65),   # quinte
        (2.00, 0.75, 0.55),   # nominale
        (2.53, 0.22, 0.35),
        (2.66, 0.18, 0.30),
        (3.01, 0.20, 0.25),
        (4.07, 0.14, 0.16),
        (5.33, 0.09, 0.11),
        (6.40, 0.06, 0.08),
    ]
    # Une vraie cloche sonne bien plus d'une seconde ; le fichier, lui, en
    # dure une. On raccourcit donc les extinctions pour qu'elle ait fini de
    # parler avant la fin, au lieu d'être coupée en plein vol.
    tau_scale = 0.60 * (262.0 / freq) ** 0.25
    for ratio, amp, tau in partials:
        f = freq * ratio
        if f >= RATE / 2:
            continue
        decay = tau * tau_scale
        # Deux partiels jumeaux très proches : la cloche bat.
        add_partial(buf, f * 0.9994, amp * 0.5, decay,
                    phase=rng.uniform(0, 2 * math.pi), attack=0.001)
        add_partial(buf, f * 1.0006, amp * 0.5, decay,
                    phase=rng.uniform(0, 2 * math.pi), attack=0.001)
    add_noise_burst(buf, 0.18, 0.006, cutoff=0.7, rng=rng)
    return buf


SYNTHS = {'piano': piano, 'guitare': guitare, 'orgue': orgue, 'cloche': cloche}


# ── Fabrication des fichiers ────────────────────────────────────────────────

def stable_seed(instrument, name):
    """Graine reproductible : `hash()` change d'un lancement à l'autre."""
    return zlib.crc32(f'{instrument}/{name}'.encode()) & 0xFFFF


def read_shape(path):
    """Nombre d'échantillons et niveau crête du fichier d'origine."""
    with wave.open(path) as w:
        n = w.getnframes()
        raw = w.readframes(n)
        ch = w.getnchannels()
    vals = struct.unpack('<%dh' % (len(raw) // 2), raw)
    if ch == 2:
        vals = vals[0::2]
    peak = max(abs(v) for v in vals) / 32768.0
    return n, peak


def write_wav(path, buf):
    data = b''.join(
        struct.pack('<h', max(-32768, min(32767, int(round(v * 32767)))))
        for v in buf
    )
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)


# Extinction finale par instrument : pour le piano c'est l'étouffoir qui
# retombe, pour l'orgue la soupape qui se ferme.
TAIL = {'piano': 0.12, 'guitare': 0.10, 'orgue': 0.045, 'cloche': 0.18}


def build_note(instrument, freq, n, seed):
    rng = random.Random(seed)
    buf = SYNTHS[instrument](freq, n, rng)
    fade_in(buf)
    fade_out(buf, TAIL[instrument])
    return buf


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else 'assets/sounds'
    for instrument in INSTRUMENTS:
        folder = os.path.join(root, instrument)
        for note in NOTES:
            for octave in OCTAVES:
                name = f'{note}{octave}'
                path = os.path.join(folder, f'{name}.wav')
                n, peak = read_shape(path)
                seed = stable_seed(instrument, name)
                buf = build_note(instrument, freq_of(note, octave), n, seed)
                write_wav(path, normalise(buf, peak))
        print(f'{instrument} : 28 notes refaites')


if __name__ == '__main__':
    main()
