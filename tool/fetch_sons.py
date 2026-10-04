#!/usr/bin/env python3
"""Récupère les enregistrements d'origine des quatre instruments.

Pourquoi des enregistrements et plus une synthèse : Nino, après deux
tentatives de synthèse physique, « ça ne ressemble pas du tout à
l'instrument que ça imite ». C'est une limite de méthode, pas de réglage —
un modèle écrit à la main produit un son de synthétiseur, et aucun
paramètre ne l'en fera sortir. Ce qui ressemble à un piano, c'est un piano.

Source : FluidR3_GM, rendu note par note par le projet MIDI.js Soundfonts.
Licence Creative Commons Attribution 3.0 — le crédit est porté dans les
réglages de l'application (voir `kCreditSons`).

Les fichiers atterrissent dans `tool/sons_source/`, et y RESTENT : la
fabrication doit pouvoir se refaire sans réseau, et la provenance doit se
lire dans le dépôt.

Usage : python3 tool/fetch_sons.py
"""
import os
import sys
import urllib.request

BASE = ('https://raw.githubusercontent.com/gleitz/midi-js-soundfonts/'
        'gh-pages/FluidR3_GM')

# Nos quatre instruments, et le programme General MIDI qui leur répond.
SOURCES = {
    'piano': 'acoustic_grand_piano',
    'guitare': 'acoustic_guitar_nylon',
    # Orgue À TIRETTES, et non orgue d'église : c'est ce que la synthèse
    # d'origine imitait (« jeux de tirettes 16', 8', 5⅓'… »), et surtout
    # c'est le seul qui parle assez vite. Mesuré sur un do3 : l'orgue
    # d'église met 1186 ms à atteindre son plein son, celui-ci 20 ms. Dans
    # une note de 420 ms, le premier arriverait mou et en retard — et dans
    # un glissando cadencé à 100 ms, il n'arriverait pas du tout.
    'orgue': 'drawbar_organ',
    'cloche': 'tubular_bells',
}

NOTES = ['do', 're', 'mi', 'fa', 'sol', 'la', 'si']
# Nos noms vers la notation scientifique des fichiers d'origine.
LETTRES = {'do': 'C', 're': 'D', 'mi': 'E', 'fa': 'F',
           'sol': 'G', 'la': 'A', 'si': 'B'}
OCTAVES = [2, 3, 4, 5]
# `do2` chez Kivy est le do3 scientifique : une octave d'écart dans le nom.
DECALAGE = 1

DEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'sons_source')


def main():
    total = 0
    for inst, programme in SOURCES.items():
        dossier = os.path.join(DEST, inst)
        os.makedirs(dossier, exist_ok=True)
        for note in NOTES:
            for octave in OCTAVES:
                nom = '%s%d' % (note, octave)
                cible = os.path.join(dossier, nom + '.mp3')
                if os.path.exists(cible):
                    continue
                url = '%s/%s-mp3/%s%d.mp3' % (
                    BASE, programme, LETTRES[note], octave + DECALAGE)
                try:
                    with urllib.request.urlopen(url, timeout=60) as r:
                        data = r.read()
                except Exception as e:
                    print('ÉCHEC %s %s : %s' % (inst, nom, e))
                    return 1
                if len(data) < 1000:
                    print('ÉCHEC %s %s : fichier vide' % (inst, nom))
                    return 1
                with open(cible, 'wb') as f:
                    f.write(data)
                total += 1
        print('%s : %d notes depuis %s' % (inst, len(NOTES) * len(OCTAVES),
                                           programme))
    print('%d fichiers téléchargés dans %s' % (total, DEST))
    return 0


if __name__ == '__main__':
    sys.exit(main())
