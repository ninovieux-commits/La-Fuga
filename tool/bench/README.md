# Mesures du moteur

Trois programmes, à lancer depuis la racine du projet.

```
dart run tool/bench/engine_bench.dart          # points chauds, meilleur de 5
dart run tool/bench/scores.dart  <fichier>     # 8 108 scores de position
dart run tool/bench/choices.dart <fichier>     # coups choisis par Deep Grey
```

`engine_bench` mesure ; les deux autres **figent un comportement**. Avant
d'optimiser le moteur, on écrit le fichier de référence ; après, on le réécrit
et on `diff`. Une seule ligne différente veut dire que Deep Grey ne joue plus
pareil — ce qui n'est jamais le but d'une optimisation.

Le hasard y est semé à graine fixe, et les poids appris sont donnés en dur :
deux exécutions de la même version donnent le même fichier.

## Références

Mesures prises sur la même machine, meilleur de 5 passes, position de milieu
de partie (49 coups légaux).

| | avant | après |
|---|---|---|
| `evaluate` (froid) | 55,0 us | 3,9 us |
| `positionalStrategy` | 3,5 us | 1,6 us |
| clé de position (froide) | 1,77 us | 0,37 us |
| `chooseMove` profondeur 2 | 15,6 ms | 2,5 ms |
| Deep Grey mode profond | 567 ms | 57 ms |

Les coups choisis, eux, sont restés identiques — c'est ce que vérifie
`choices.dart`.
