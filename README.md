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
| Géométrie | orientation, ralliements, aller-retour pixel ↔ case |
| Réseau | chemins et clés de chaque route, réconciliation du thème |
| Langues | 415 clés × 9 langues, complétude et repli |
| Interaction | poussée dir. par dir., multisaut, manœuvre, fins de partie |
| Chrono | décompte, drapeau, synchro réseau |
| Sons | note par case, glissandos, ordre dans le temps |
| Réglages | valeurs par défaut, persistance, axes de thème |
| Écrans | démarrage, menu, réglages, lancement d'une partie |
| Notation inverse | tout coup produit se relit en le même coup |
| Partie en ligne | coups, horloges, nulle, abandon, chat, match |
| Correspondance | lecture des parties, rejeu, atomicité du coup final |
| Images de thème | fichiers existants, dix pièces par thème, pubspec à jour |
| Tuto | les 22 étapes, phases guidées, multisaut, manœuvre, poussée |
| Matchs | score, alternance des couleurs, règle de l'ultime partie |
| Défis | envoi, annulation, refus, réception, raisons d'échec |
| Compte et messagerie | profil, notifications, favoris, blocages, conversations |

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
- [x] Couche réseau (HTTP + Socket.IO)
- [x] 10 langues (415 clés), 17 thèmes
- [x] Interaction incrémentale de Kivy + chrono
- [x] Sons (4 instruments, note par case, glissandos)
- [x] Menu, réglages, persistance de la configuration
- [x] Thèmes à images (médiéval, fleurs, dragon, insectes, deepgrey)
- [x] Rosace du logo au centre du plateau
- [x] Historique (compte + appareil) et lecteur de parties
- [x] Archivage des parties finies (serveur si connecté, sinon `.nmc` local)
- [x] Deep Grey apprend : poids affinés et livre d'ouvertures
- [x] Compte : profil, photo, description, e-mail, notifications, favoris, blocages
- [x] Messagerie : conversations, messages, non-lus
- [x] Tuto : les 22 étapes, dont 9 interactives
- [x] Défis en direct, recherche de joueur, favoris
- [x] Analyse, Random Fuga hors ligne, lecteur `.nmc`, soutien aux devs
- [x] Matchs en plusieurs points hors ligne, abandon, nulle par accord
- [x] Composeur de thèmes (les cinq axes séparément)
- [x] Mode en ligne branché : salon, connexion, partie, chat, nulle, abandon
- [x] Correspondance : défis, parties, nulle, abandon, rejeu de l'historique

### Écarts connus, à combler

- **Notifications push.** Firebase est volontairement absent de `pubspec.yaml`
  tant que `google-services.json` n'est pas fourni : le déclarer sans ce
  fichier ferait échouer la compilation. Le reste est prêt côté client — la
  route `/set_fcm_token` est déjà implémentée et les préférences de
  notification (`mail`, `turn`, `msg`, `defi_corr`, `defi_direct`) se règlent
  dans l'écran de compte. Il manque le fichier, puis l'abonnement au jeton.
- **Visite guidée du menu.** En Kivy, la dernière étape du tuto entoure les
  touches du vrai menu une par une. Le menu Flutter n'a pas la même
  disposition (pas de rangée cadence/objectif ni d'emplacements de
  correspondance sur le menu) : la visite demande d'être repensée plutôt que
  recopiée.
- **Taille de l'APK.** Les images des thèmes pèsent 32 Mo à elles seules
  (jusqu'à 3 Mo par fichier). Une recompression sans perte les allégerait
  beaucoup, mais elle modifierait des fichiers repris tels quels du dépôt
  Kivy : à décider.
