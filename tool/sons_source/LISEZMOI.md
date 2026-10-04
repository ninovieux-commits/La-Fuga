# Les enregistrements d'origine

Ce dossier contient les 112 notes dont `tool/gen_sounds.py` tire les sons du
jeu : quatre instruments, vingt-huit notes chacun.

## Pourquoi des enregistrements

Les instruments étaient **synthétisés** — piano à cordes multiples et partiels
inharmoniques, guitare de Karplus-Strong, orgue à tirettes, cloche à partiels
de bronze. Les modèles étaient justes, et le résultat sonnait quand même comme
un synthétiseur. Nino, après deux passes : « ça ne ressemble pas du tout à
l'instrument que ça imite ».

C'est une limite de méthode, pas de réglage. On peut affiner un modèle
indéfiniment sans qu'il devienne un piano. Ce qui ressemble à un piano, c'est
un piano.

## Provenance et licence

**FluidR3_GM**, rendu note par note par le projet
[MIDI.js Soundfonts](https://github.com/gleitz/midi-js-soundfonts).

Licence **Creative Commons Attribution 3.0**. Le crédit est porté dans
l'application, sous le choix de l'instrument (`kCreditSons`).

| instrument du jeu | programme General MIDI |
|---|---|
| piano | `acoustic_grand_piano` |
| guitare | `acoustic_guitar_nylon` |
| orgue | `drawbar_organ` |
| cloche | `tubular_bells` |

L'orgue est à **tirettes** et non d'église : c'est ce que la synthèse
d'origine imitait, et surtout le seul qui parle assez vite. Mesuré sur un
do3, l'orgue d'église met 1186 ms à atteindre son plein son, celui-ci 20 ms.
Dans une note de 420 ms, le premier arriverait mou et en retard.

## Pourquoi les garder ici

Pour que la fabrication se refasse sans réseau, et pour que la provenance se
lise dans le dépôt. `tool/fetch_sons.py` ne retélécharge que ce qui manque.
