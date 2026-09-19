# La Fuga — version Flutter

Portage Flutter de l'application mobile **La Fuga**, écrite à l'origine en Kivy
(dépôt [`lafuga`](https://github.com/ninovieux-commits/lafuga)).

Le dépôt Kivy reste **intact** : il fait foi pour les règles et pour le
comportement attendu. Ce dépôt-ci ne contient que le client Flutter.

## Ce qui ne change pas

- **`server.py`**, la base de données et Firebase : inchangés.
- Le client Flutter parle **exactement le même protocole** que le client Kivy —
  mêmes routes HTTP, mêmes événements Socket.IO. Voir
  [`docs/SPEC.md`](docs/SPEC.md) § 5 et § 10.
- Les **images et les sons** sont repris tels quels du dépôt Kivy
  (`assets/`, 195 fichiers).

## Priorité : la fluidité

Deux décisions structurantes :

1. **L'IA « Deep Grey » tourne dans un `Isolate`.** En Kivy, elle calculait sur
   le thread de l'interface : le chrono gelait pendant sa réflexion. Tout
   `lib/engine/` est du Dart pur, sans le moindre import Flutter, précisément
   pour pouvoir s'exécuter dans un isolate.
2. **Rendu GPU.** Le plateau est dessiné dans un `CustomPainter` avec des
   couches séparées (fond statique / pièces / animation), de sorte qu'une
   animation ne force pas la reconstruction du plateau entier.

## Fidélité vérifiée, pas supposée

Le moteur de règles Dart est comparé automatiquement au moteur Python d'origine.
`tool/gen_vectors.py` extrait le moteur de `main.py` et produit des vecteurs de
test ; les tests Dart rejouent les mêmes positions et comparent coup par coup.

| Vérification | Couverture |
|---|---|
| Générateur de coups | 149 positions, **6 983 coups** identiques au moteur Python |
| Random Fuga | les **3 500** positions identiques à `rf_build_board` |
| Notation `.nmc` | aller-retour sur les 56 cases + toutes les formes de coups |
| Deep Grey | choix de coup, poids appris, et isolate non bloquant |

```bash
flutter test
```

## Structure

```
lib/
  engine/        Dart pur — règles, coups, notation, IA. Utilisable en isolate.
  net/           Client HTTP + Socket.IO (même protocole que le client Kivy)
  state/         État applicatif
  ui/            Écrans et widgets
  theme/         Les 17 thèmes, composables sur 5 axes
  i18n/          10 langues, 415 clés
docs/SPEC.md     Spécification de portage (source de vérité de la traduction)
tool/            Extraction depuis main.py + génération des vecteurs de test
test/            Tests, dont les tests de fidélité au moteur Python
```

## Compilation

L'APK est compilé par GitHub Actions
([`.github/workflows/build-apk.yml`](.github/workflows/build-apk.yml)) :
analyse statique et tests d'abord, APK ensuite. L'APK est publié en artefact.

Compilation en mode release : onglet *Actions* → *Compiler l'APK Android* →
*Run workflow* → cocher **release**.

## État d'avancement

- [x] Spécification complète extraite de `main.py` et `server.py`
- [x] Moteur de règles (plateau, pièces, coups, poussées, manœuvres, fins de partie)
- [x] Notation `.nmc`
- [x] Random Fuga
- [x] Assets repris du dépôt Kivy
- [x] CI de compilation APK
- [x] IA Deep Grey sur isolate
- [x] Plateforme Android (manifeste, permissions, minSdk 24, portrait)
- [x] Rendu GPU du plateau et des pièces, écran de jeu contre Deep Grey
- [ ] Couche réseau
- [ ] Écrans complets (chrono, chat, en ligne, correspondance, thèmes à images)

### Écarts connus, à combler

- L'interaction est pour l'instant « choisir une pièce, choisir une arrivée ».
  Kivy propose une interaction **incrémentale** : on pousse direction par
  direction, on compose un groupe pour une manœuvre, on enchaîne les sauts et
  on valide en recliquant la pièce. À porter avec l'écran de jeu complet.
- Les thèmes à images (médiéval, fleurs, dragon, insectes, deepgrey) ne sont
  pas encore branchés : le rendu géométrique sert de repli universel.
- Le logo central du plateau (rosace à 8 segments) n'est pas dessiné.
- Firebase est volontairement absent de `pubspec.yaml` tant que
  `google-services.json` n'est pas fourni : le déclarer sans ce fichier ferait
  échouer la compilation pour une fonctionnalité pas encore écrite.
