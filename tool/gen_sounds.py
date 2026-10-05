#!/usr/bin/env python3
"""Prépare les quatre instruments de La Fuga à partir d'ENREGISTREMENTS.

Ce fichier synthétisait les notes : piano à cordes multiples, guitare de
Karplus-Strong, orgue à tirettes, cloche à partiels inharmoniques. Le modèle
était juste, et le résultat sonnait quand même comme un synthétiseur. Nino :
« ça ne ressemble pas du tout à l'instrument que ça imite ». C'est une limite
de méthode : on peut affiner un modèle indéfiniment sans qu'il devienne un
piano. Ce qui ressemble à un piano, c'est un piano.

On part donc des enregistrements de `tool/sons_source/` (voir
`tool/fetch_sons.py` pour leur provenance et leur licence), et ce fichier ne
fait plus que les mettre au format du jeu :

  1. somme en mono, car le jeu mixe en mono ;
  2. on retire le silence de tête — un MP3 en porte toujours quelques
     dizaines de millisecondes, et un glissando cadencé à 100 ms ne supporte
     pas que ses notes arrivent en retard ;
  3. on coupe à la longueur de l'instrument, et on pose l'étouffoir ;
  4. un SEUL gain par instrument, pour garder l'équilibre naturel entre les
     notes — les normaliser une à une l'effacerait.

Chaque note est vérifiée : sa hauteur réelle doit être celle de son nom, à un
demi-ton près. Une erreur d'octave dans le mappage passerait sinon inaperçue.

Usage : python3 tool/gen_sounds.py [dossier_assets]
"""
import os
import sys
import wave

import numpy as np
import soundfile as sf

RATE = 44100
NOTES = ['do', 're', 'mi', 'fa', 'sol', 'la', 'si']
SEMITONES = {'do': 0, 're': 2, 'mi': 4, 'fa': 5, 'sol': 7, 'la': 9, 'si': 11}
OCTAVES = [2, 3, 4, 5]
INSTRUMENTS = ['piano', 'guitare', 'orgue', 'cloche',
               'xylophone', 'harpe', 'choeur']

SOURCE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                      'sons_source')

# Longueur d'une note, en secondes.
#
# L'orgue est court exprès : chaque note est un coup joué, pas une touche
# qu'on tient, et un glissando de quatre notes empilerait sinon un accord.
# La cloche a besoin de temps — c'est ce qui la distingue d'un « cling ».
# Chaque durée est choisie sur la MESURE de l'enregistrement, pas au jugé :
#   le xylophone meurt de lui-même en moins d'une seconde ;
#   la trompette bouchée ne décroît JAMAIS (-0 dB encore à 1,7 s), comme
#   l'orgue : il lui faut une note courte et une soupape qui se ferme.
NOTE_SECONDS = {
    # Amorties (voir AMORTI), elles n'ont plus besoin de tenir si longtemps.
    'piano': 1.00,
    'guitare': 1.00,
    'orgue': 0.42,
    'cloche': 2.40,
    'xylophone': 0.80,
    'harpe': 1.70,
    # Le choeur ne decroit pas, comme l'orgue : note courte et soupape.
    # Il enfle aussi — il est a mi-volume en 197 ms — et c'est voulu : une
    # entree franche existait, Nino a choisi la naturelle.
    'choeur': 1.00,
}

# Niveau crête visé, par instrument.
PEAK = {
    'piano': 0.70,
    'guitare': 0.82,
    'orgue': 0.82,
    'cloche': 0.82,
    # Le xylophone est sec et perçant : un peu moins fort que les autres.
    'xylophone': 0.75,
    'harpe': 0.82,
    'choeur': 0.82,
}

# L'étouffoir, à la fin : la durée pendant laquelle le son se retire.
# L'orgue a la plus longue : il ne décroît pas tout seul, on le coupe donc
# en plein son, et c'est la soupape qui doit se fermer proprement. Avec
# 60 ms, la mesure disait que ça claquait encore à -10 dB.
# Amortissement SUPPLÉMENTAIRE, en secondes. Absent : la note garde son
# extinction naturelle.
#
# « J'aimerai que piano et guitare résonnent moins » — quatre doses lui ont
# été proposées à l'écoute, il a pris la moyenne pour les deux. Un do3 de
# piano était encore à -6 dB après six dixièmes de seconde ; avec cet
# amortissement il tombe à -13, et la note est éteinte avant le coup suivant.
AMORTI = {'piano': 0.70, 'guitare': 0.70}

TAIL = {
    'piano': 0.14,
    'guitare': 0.12,
    'orgue': 0.15,
    'cloche': 0.22,
    'xylophone': 0.05,
    'harpe': 0.14,
    # Comme l'orgue : on le coupe en plein son, la soupape doit se fermer
    # proprement.
    'choeur': 0.18,
}


def freq_of(note, octave):
    """Fréquence d'une note nommée à la Kivy. `do2` = do3 scientifique."""
    midi = 12 * (octave + 2) + SEMITONES[note]
    return 440.0 * 2 ** ((midi - 69) / 12)


def lire_mono(path):
    """Enregistrement en mono, à notre fréquence d'échantillonnage."""
    data, rate = sf.read(path, always_2d=True, dtype='float64')
    mono = data.mean(axis=1)
    if rate != RATE:
        n = int(round(len(mono) * RATE / rate))
        mono = np.interp(np.linspace(0, len(mono) - 1, n),
                         np.arange(len(mono)), mono)
    return mono


def debut_reel(x, seuil_db=-50.0):
    """Où le son COMMENCE vraiment.

    Un MP3 porte un silence de tête, et l'enregistrement lui-même en a
    souvent un. Sans le retirer, chaque note arriverait en retard — et un
    glissando cadencé à 100 ms deviendrait flou.
    """
    if not len(x):
        return 0
    pic = np.abs(x).max()
    if pic <= 0:
        return 0
    seuil = pic * 10 ** (seuil_db / 20)
    au_dessus = np.nonzero(np.abs(x) >= seuil)[0]
    if not len(au_dessus):
        return 0
    # Une milliseconde avant, pour ne pas manger le tout début de l'attaque.
    return max(0, int(au_dessus[0]) - int(0.001 * RATE))


def amortit(x, tau):
    """Fait mourir la note plus vite, sans la trancher.

    Nino : « j'aimerai que piano et guitare résonnent moins ». Un piano
    enregistré tient longtemps — son do3 est encore à -6 dB après six
    dixièmes de seconde. Dans un glissando de trois notes suivi du coup
    d'après, tout s'empile.

    On pose donc une décroissance SUPPLÉMENTAIRE par-dessus la naturelle :
    c'est le geste d'un feutre qu'on laisse contre la corde. Raccourcir le
    fichier à la place aurait coupé la note en plein son.

    [tau] est la constante de temps, en secondes. 0 ou None : on ne touche
    à rien.
    """
    if not tau:
        return x
    t = np.arange(len(x)) / RATE
    return x * np.exp(-t / tau)


def etouffoir(x, seconds, douceur=0.35):
    """La fin d'une note : l'étouffoir qui retombe, pas un fondu.

    Un fondu en cosinus baisse le volume sans rien changer d'autre : on
    entend une main sur le bouton. Un vrai étouffoir est un feutre qui se
    pose — il absorbe l'aigu AVANT le grave, et le son s'assombrit en
    mourant.
    """
    n = len(x)
    f = min(n, int(seconds * RATE))
    if f < 8:
        return x
    x = x.copy()
    k = np.arange(f) / f
    x[n - f:] *= np.exp(-4.0 * k)
    # Et le feutre mange l'aigu : le filtre se referme à mesure.
    prev = x[n - f - 1] if n - f > 0 else 0.0
    for i in range(f):
        a = 1.0 - douceur * k[i]
        prev = prev + a * (x[n - f + i] - prev)
        x[n - f + i] = prev
    return x


def fade_in(x, seconds=0.0015):
    """Départ à zéro : un fichier qui commence sur une valeur non nulle claque."""
    f = min(len(x), int(seconds * RATE))
    if f < 2:
        return x
    x = x.copy()
    x[:f] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(f) / f)
    return x


# La cloche est INHARMONIQUE : sa hauteur perçue — le « son de frappe » — ne
# correspond à aucun de ses partiels, c'est une fondamentale absente que
# l'oreille reconstruit. Aucune mesure de périodicité ne la retrouve, et c'est
# justement ce qui fait une cloche. On mesure quand même, pour l'afficher,
# mais on ne refuse pas le fichier là-dessus.
HARMONIQUES = ['piano', 'guitare', 'orgue',
               'xylophone', 'harpe', 'choeur']


def presence_hauteur(x, attendue):
    """La note contient-elle bien la hauteur qu'annonce son nom ?

    Première version : chercher la périodicité dominante. Mauvaise question.
    Sur un orgue à tirettes, le pic le plus fort d'un `si5` est à 495 Hz,
    soit DEUX OCTAVES sous la hauteur écrite — ce sont les jeux de 16 et 8
    pieds, qui écrasent tout dans l'aigu. La mesure criait à la fausse note
    sur des notes parfaitement justes.

    La bonne question est plus modeste et plus sûre : l'énergie est-elle
    présente à la hauteur attendue ? Une note mal mappée — un `mi` qui irait
    chercher un ré, un décalage d'un demi-ton — n'aurait quasiment rien là.

    Renvoie cette énergie en pourcentage du pic le plus fort.
    """
    debut = int(0.08 * RATE)
    seg = x[debut:debut + 16384]
    if len(seg) < 4096:
        return 0.0
    X = np.abs(np.fft.rfft(seg * np.hanning(len(seg))))
    f = np.fft.rfftfreq(len(seg), 1.0 / RATE)
    if X.max() <= 0:
        return 0.0
    # Un demi-ton de part et d'autre : assez large pour le vibrato et le
    # tempérament, assez etroit pour refuser la note voisine.
    bande = X[(f >= attendue * 2 ** (-0.5 / 12)) &
              (f <= attendue * 2 ** (0.5 / 12))]
    return 100.0 * (bande.max() / X.max()) if len(bande) else 0.0


def rapport_du_pic(x, attendue):
    """Le pic dominant, en multiple de la hauteur annoncée.

    Pour la cloche, qui n'a pas de fondamentale à montrer : ses partiels
    restent des multiples simples du son de frappe. Un `do4` dont le pic
    tombe à 4,02 fois la hauteur annoncée est juste ; un demi-ton d'erreur
    donnerait 4,26, et se verrait.
    """
    debut = int(0.08 * RATE)
    seg = x[debut:debut + 16384]
    if len(seg) < 4096:
        return 0.0
    X = np.abs(np.fft.rfft(seg * np.hanning(len(seg))))
    f = np.fft.rfftfreq(len(seg), 1.0 / RATE)
    return float(f[int(np.argmax(X))]) / attendue if attendue else 0.0


def ecrire_wav(path, x):
    y = np.clip(np.round(x * 32767), -32768, 32767).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(y.tobytes())


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else 'assets/sounds'
    if not os.path.isdir(SOURCE):
        print('Enregistrements absents : lancez d abord tool/fetch_sons.py')
        return 1

    ecarts = []
    rapports = []
    for instrument in INSTRUMENTS:
        dossier = os.path.join(root, instrument)
        os.makedirs(dossier, exist_ok=True)
        longueur = int(round(NOTE_SECONDS[instrument] * RATE))
        queue = TAIL[instrument]

        preparees = {}
        for note in NOTES:
            for octave in OCTAVES:
                nom = '%s%d' % (note, octave)
                src = os.path.join(SOURCE, instrument, nom + '.mp3')
                x = lire_mono(src)
                x = x[debut_reel(x):]
                if len(x) < longueur:
                    x = np.concatenate([x, np.zeros(longueur - len(x))])
                x = x[:longueur]
                x = fade_in(x)
                x = amortit(x, AMORTI.get(instrument))
                x = etouffoir(x, queue)

                attendue = freq_of(note, octave)
                ecarts.append((instrument, nom,
                               presence_hauteur(x, attendue)))
                if instrument not in HARMONIQUES:
                    r = rapport_du_pic(x, attendue)
                    rapports.append((instrument, nom, r))
                preparees[nom] = x

        # UN seul gain pour tout l'instrument : les notes gardent entre elles
        # l'équilibre qu'elles ont sur l'instrument. Les normaliser une à une
        # mettrait une basse et un aigu au même niveau, ce qu'aucun
        # instrument ne fait.
        pic = max(float(np.abs(v).max()) for v in preparees.values())
        gain = (PEAK[instrument] / pic) if pic > 0 else 1.0
        for nom, x in preparees.items():
            ecrire_wav(os.path.join(dossier, nom + '.wav'), x * gain)
        print('%s : 28 notes préparées (gain ×%.2f)' % (instrument, gain))

    # Une note mal mappée n'aurait presque rien à la hauteur qu'elle
    # annonce. On refuse en dessous de 8 % du pic le plus fort — la cloche
    # exceptée, dont la hauteur perçue est une fondamentale ABSENTE que
    # l'oreille reconstruit, et qu'aucune mesure ne trouvera dans le
    # spectre. C'est précisément ce qui fait une cloche.
    faux = [(i, n, p) for i, n, p in ecarts if i in HARMONIQUES and p < 8.0]
    print('\nhauteur vérifiée sur %d notes' % len(ecarts))
    for i in INSTRUMENTS:
        vals = [p for j, _, p in ecarts if j == i]
        print('  %-8s énergie à la hauteur annoncée : %2.0f à %2.0f %%%s'
              % (i, min(vals), max(vals),
                 '   (inharmonique, non jugée)' if i not in HARMONIQUES
                 else ''))
    # Et pour la cloche, l'autre preuve : ses partiels doivent rester des
    # multiples SIMPLES de la hauteur annoncée.
    tordus = []
    for i, n, r in rapports:
        if r <= 0:
            tordus.append((i, n, r))
            continue
        ecart = abs(r - round(r)) / round(r) if round(r) else 1.0
        # 4 % de tolérance, et c'est la physique qui le demande : les modes
        # d'un tube ne sont PAS des harmoniques exactes — le troisième tombe
        # à ×2,92 et non ×3. Un demi-ton d'erreur, lui, ferait 5,9 % : la
        # marge sépare encore les deux.
        if round(r) < 1 or ecart > 0.04:
            tordus.append((i, n, r))
    if rapports:
        print('  cloche   pic dominant : ×%.2f à ×%.2f de la hauteur annoncée'
              % (min(r for _, _, r in rapports),
                 max(r for _, _, r in rapports)))
    if faux or tordus:
        print('NOTES MAL MAPPÉES :')
        for i, n, p in faux[:20]:
            print('  %s %s : %.1f %% seulement' % (i, n, p))
        for i, n, r in tordus[:20]:
            print('  %s %s : pic à ×%.3f, ce n est pas un multiple simple'
                  % (i, n, r))
        return 1
    print('aucune note mal mappée')
    return 0


if __name__ == '__main__':
    sys.exit(main())
