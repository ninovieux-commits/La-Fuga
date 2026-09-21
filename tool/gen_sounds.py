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
    """Tuyaux : jeux de tirettes, souffle d'attaque, léger battement.

    Court. Un orgue d'église tient tant qu'on garde le doigt sur la touche,
    mais ici chaque note est un coup joué : une note qui dure une seconde
    empile un accord de cinq notes pendant un glissando, et tout devient une
    bouillie. On garde donc l'attaque et le timbre, pas la tenue.
    """
    buf = silence(n)
    # Tirettes, de 0 à 8, dans l'ordre 16' 8' 5⅓' 4' 2⅔' 2' 1⅗' 1⅓' 1'.
    drawbars = [(0.5, 6), (1.0, 8), (1.5, 4), (2.0, 6),
                (3.0, 3), (4.0, 3), (5.0, 2), (6.0, 1), (8.0, 2)]
    attack = 0.014
    hold = 0.10
    release = 0.16
    a_len = int(attack * RATE)
    h_end = int((attack + hold) * RATE)
    r_len = max(1, int(release * RATE))
    for ratio, level in drawbars:
        f = freq * ratio
        if f >= RATE / 2:
            continue
        amp = (level / 8.0) ** 1.6
        # Chaque tuyau est un peu faux : c'est ce qui fait respirer l'orgue.
        f *= 1 + rng.uniform(-0.0015, 0.0015)
        w = 2 * math.pi * f / RATE
        ph = rng.uniform(0, 2 * math.pi)
        for i in range(n):
            if i < a_len:
                env = 0.5 - 0.5 * math.cos(math.pi * i / a_len)
            elif i < h_end:
                env = 1.0
            else:
                k = (i - h_end) / r_len
                if k >= 1:
                    break
                env = 0.5 + 0.5 * math.cos(math.pi * k)
            buf[i] += amp * env * math.sin(w * i + ph)
    # Le « chiff » : l'air qui attaque le biseau avant que le tuyau ne parle.
    add_noise_burst(buf, 0.16, 0.022, cutoff=0.30, rng=rng)
    return buf


def cloche(freq, n, rng):
    """Cloche : partiels inharmoniques, chacun avec sa propre extinction.

    Ce qui fait qu'on reconnaît une cloche, ce n'est pas son fondamental :
    c'est (1) une frappe brillante et bruitée qui meurt en un dixième de
    seconde, (2) des partiels NON harmoniques — dont la fameuse tierce
    MINEURE, qui donne à toute cloche sa couleur un peu triste — et (3) des
    vitesses d'extinction très différentes d'un partiel à l'autre : l'aigu
    disparaît presque aussitôt, le bourdon reste. C'est ce grand écart qui
    manquait.
    """
    buf = silence(n)
    # (rapport, amplitude, extinction en secondes). Les rapports sont ceux
    # d'une cloche accordée ; au-delà de la nominale, ils s'écartent de plus
    # en plus de l'harmonique pur.
    partials = [
        (0.500, 0.42, 1.60),   # bourdon : il reste après tout le monde
        (1.000, 0.85, 1.05),   # prime : la note entendue
        (1.183, 0.62, 0.62),   # tierce mineure
        (1.506, 0.45, 0.45),   # quinte
        (2.000, 1.00, 0.38),   # nominale : le coup de marteau
        (2.514, 0.34, 0.24),
        (2.664, 0.30, 0.20),
        (3.011, 0.40, 0.17),
        (3.472, 0.24, 0.13),
        (4.166, 0.30, 0.10),
        (4.943, 0.20, 0.080),
        (5.433, 0.16, 0.065),
        (6.314, 0.18, 0.050),
        (7.522, 0.12, 0.040),
        (8.937, 0.10, 0.030),
    ]
    tau_scale = (262.0 / freq) ** 0.30
    for ratio, amp, tau in partials:
        f = freq * ratio
        if f >= RATE / 2:
            continue
        decay = tau * tau_scale
        # Deux partiels jumeaux très proches : la cloche bat. Plus le partiel
        # est haut, plus le battement est rapide.
        spread = 0.0004 * ratio
        add_partial(buf, f * (1 - spread), amp * 0.5, decay,
                    phase=rng.uniform(0, 2 * math.pi), attack=0.0008)
        add_partial(buf, f * (1 + spread), amp * 0.5, decay,
                    phase=rng.uniform(0, 2 * math.pi), attack=0.0008)
    # Le battant sur le bronze : bref, brillant, bruité.
    add_noise_burst(buf, 0.55, 0.018, cutoff=0.92, rng=rng)
    return buf


SYNTHS = {'piano': piano, 'guitare': guitare, 'orgue': orgue, 'cloche': cloche}


# ── Fabrication des fichiers ────────────────────────────────────────────────

def stable_seed(instrument, name):
    """Graine reproductible : `hash()` change d'un lancement à l'autre."""
    return zlib.crc32(f'{instrument}/{name}'.encode()) & 0xFFFF


# Durée d'une note, en secondes, et niveau crête — par instrument.
#
# L'orgue est court exprès : chaque note est un coup joué, pas une touche
# qu'on tient, et un glissando de quatre notes empilerait sinon un accord.
NOTE_SECONDS = {'piano': 1.00, 'guitare': 1.20, 'orgue': 0.42, 'cloche': 1.00}
PEAK = {'piano': 0.50, 'guitare': 0.82, 'orgue': 0.82, 'cloche': 0.82}


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
        n = int(round(NOTE_SECONDS[instrument] * RATE))
        peak = PEAK[instrument]
        for note in NOTES:
            for octave in OCTAVES:
                name = f'{note}{octave}'
                path = os.path.join(folder, f'{name}.wav')
                seed = stable_seed(instrument, name)
                buf = build_note(instrument, freq_of(note, octave), n, seed)
                write_wav(path, normalise(buf, peak))
        print(f'{instrument} : 28 notes refaites')


if __name__ == '__main__':
    main()
