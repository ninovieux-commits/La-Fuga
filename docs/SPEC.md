# La Fuga — spécification de portage Kivy → Flutter

Source de vérité : `main.py` (16 410 lignes, Kivy) du dépôt `ninovieux-commits/lafuga`.
Le backend (`server.py`, base de données, Firebase) **ne change pas**. Le client Flutter
doit parler exactement le même protocole.

---

## 1. Plateau et pièces

- Grille interne **7 colonnes × 8 rangées** (`COLS=7`, `ROWS=8`).
- Deux **zones de ralliement** hors plateau : rangée `8` (fugue des Blancs) et rangée `-1`
  (fugue des Noirs). Elles n'existent que sur les colonnes `RALLY = {2, 3, 4}`.
  Hauteur d'affichage totale : `EXT_ROWS = 10` rangées.
- Colonnes nommées par notes : `do ré mi fa sol la si` (index 0→6).
  Notation d'une case : `Fa5` = colonne 3, rangée 4 (`row + 1`).
- Camps : `"Blanc"` et `"Noir"`. Une pièce est `{"type": ..., "camp": ...}`.

### Types de pièces

| Type | Famille | Déplacement | Poussée |
|---|---|---|---|
| `Héritier` | ronde | 1 case (8 dirs) + saut / multisaut | — |
| `Nurse` | ronde | 1 case (8 dirs) + saut / multisaut | — |
| `Soldat` | carrée | 1 case (8 dirs) | activée par déplacement **orthogonal**, pousse en **diagonales** |
| `Garde` | carrée | 1 case (8 dirs) | activée par déplacement **diagonal**, pousse en **orthogonales** |
| `Chevalier` | ni ronde ni carrée | 1 case (8 dirs), case vide | ne pousse pas, **immortel**, **bloque** toute ligne de poussée |

### Position de départ (`_setup_pieces`)

Rangée 0 (Blanc) : `Soldat Garde Soldat Héritier Garde Soldat Garde`
→ attention : `layout = [Soldat, Garde, Soldat, Chevalier, Garde, Soldat, Garde]` est posé
d'abord, puis la **variante colonne fa** écrase la colonne 3 :
- `fa1` (3,0) = **Héritier** Blanc
- `fa2` (3,1) = **Nurse** Blanc
- `fa3` (3,2) = **Chevalier** Blanc

Rangée 1 (Blanc) : Nurses en colonnes 1, 2, 4, 5 ; `do2` (0,1) = **Garde** ; `si2` (6,1) = **Soldat**.

Les Noirs sont le **miroir exact** : rangée 7 = layout, rangée 6 = nurses + `do7` Garde +
`si7` Soldat, et colonne fa : `fa8` (3,7) = Héritier, `fa7` (3,6) = Nurse, `fa6` (3,5) = Chevalier.

---

## 2. Règles du mouvement

### Immobilisation (règle centrale)
- Une **ronde** (Nurse / Héritier) ne peut bouger que si elle **touche une autre ronde**
  (8 voisines, n'importe quel camp) → `has_round_nbr`.
- Une **carrée** (Soldat / Garde) ne peut bouger que si elle **touche une autre carrée**
  (8 voisines, n'importe quel camp) → `has_square_nbr`. Le Chevalier **ne compte pas**
  comme carrée.
- Le **Chevalier** bouge toujours (aucune condition de voisinage).
- Une pièce immobilisée est dessinée avec un **contour rouge** (`COL_IMMOBILE`).
- `_has_allied_knight_nbr` existe (le Chevalier remobiliserait les alliés adjacents) mais
  **n'est pas appliqué** dans `has_round_nbr` / `has_square_nbr` : à conserver tel quel.

### Rondes : déplacement et sauts
- Déplacement simple : 1 case dans les 8 directions, vers une case **vide**.
- **Saut** : par-dessus une case adjacente contenant une **ronde** (n'importe quel camp),
  arrivée 2 cases plus loin, case vide. Les carrées et le Chevalier ne se sautent pas.
- **Multisaut** : on peut enchaîner les sauts. Règle **anti-aller-retour** : interdit de
  re-sauter *immédiatement* par-dessus la **même** ronde qu'au saut précédent
  (`_last_jumped_nurse`) ; on peut la re-sauter plus tard.
- Tant qu'on est en multisaut (`jumping=True`), on peut continuer ; on valide en
  **recliquant la pièce** (`_with_sel` avec `col==oc and row==or_` → `_end_turn`).

### Carrées : déplacement, poussée, manœuvre
- Déplacement simple : 1 case, 8 directions, case vide.
- **Poussée activée** (`push_activated`) :
  - `Soldat` : si `|dc| + |dr| == 1` (déplacement orthogonal)
  - `Garde` : si `|dc| == |dr| == 1` (déplacement diagonal)
- **Directions de poussée valides** (`push_valid`, après activation) :
  - `Soldat` : les 4 **diagonales**
  - `Garde` : les 4 **orthogonales**
- La poussée déplace **toute la ligne contiguë** de pièces dans la direction choisie,
  d'une case. La ligne s'arrête à la première case vide.
  **Un `Chevalier` dans la ligne annule complètement la poussée** (`line = None` / `return`).
- Le joueur peut pousser dans **plusieurs directions** au même tour (une par clic), puis
  valider en recliquant la pièce.
- **Manœuvre de groupe** : sélection d'un groupe connexe de carrées **du même camp**
  (`_group_of`, connexité 8 directions), déplacé **d'une case** en bloc. Toutes les cases
  cibles doivent être libres ou appartenir au groupe.

### Éjection
Une pièce poussée hors du plateau est **éjectée** (capturée, ajoutée à `captured[camp]`).
Exception : le `Chevalier` est immortel — mais il bloque la poussée en amont, donc il ne
sort jamais.

---

## 3. Conditions de fin de partie

| Méthode | Déclencheur | Résultat |
|---|---|---|
| `fugue` | l'Héritier atteint sa zone de ralliement | victoire (voir règle auto ci-dessous) |
| `mat` | l'Héritier est **éjecté** hors du plateau | le camp de l'Héritier éjecté **perd** |
| `papatte` | le joueur au trait n'a **aucun coup légal** | il **perd** (comme un mat) |
| `nulle_pat` (Trêve) | **plus aucune carrée** du plateau ne peut bouger (tous camps) | nulle |
| `nulle_accord` | les deux joueurs activent le bouton ½ | nulle |
| `nulle` | règle auto de fugue (ci-dessous) ou accord en ligne/corr | nulle |
| `repetition` | la même position (board + trait) survient **4 fois** | nulle |
| `temps` | le chrono d'un joueur tombe à 0 | il perd |
| `abandon` | abandon explicite | il perd |

### Fugue — zone de ralliement
- L'Héritier **Blanc** fugue en rangée `8`, colonnes `{2,3,4}`.
- L'Héritier **Noir** fugue en rangée `-1`, colonnes `{2,3,4}`.
- La fugue peut se faire par **déplacement**, par **saut**, ou en étant **poussé**
  dans sa propre zone (`_dg_apply_pushes` → `fugue_by`).

### Règle auto de rattrapage (essentielle)
Quand un camp fugue **son propre** Héritier, on ne donne **pas** un tour de rattrapage :
on teste immédiatement `_camp_can_fugue(adversaire)` (l'adversaire peut-il fuguer en **un**
coup, déplacement/saut/poussée confondus, via `dg_generate_moves`) :
- **oui** → **nulle**
- **non** → le fugueur **gagne**

Si un camp pousse l'Héritier **adverse** dans la zone de ralliement adverse pendant son
propre tour, l'adversaire **gagne immédiatement**, sans rattrapage.

---

## 4. Notation `.nmc`

- Case : `Do1` … `Si8`.
- Déplacement simple / multisaut : `Fa2-Fa3`
- Manœuvre de groupe : `(Maître+Autres)-Dest`, ex. `(Do1Ré1)-Do2`
  (cases **initiales** concaténées entre parenthèses, maître en premier, puis `-` + case
  d'arrivée du maître)
- Poussée : `Départ-Arrivée>` si **toutes** les directions disponibles ont été poussées,
  sinon `Départ-Arrivée>Cible1Cible2…` avec les cases explicitement poussées.
- Fugue : `Départ*`
- Suffixe `#` : fin de partie (mat).

---

## 5. Protocole serveur (à ne pas modifier)

Base : `SERVER_URL_DEFAULT = "https://fuga-online.fr"`, surchargeable par `config.txt`
clé `server_url`. Toutes les routes sont **POST JSON**, réponse `{"ok": bool, ...}` ou
`{"error": "..."}`.

### Routes HTTP

| Route | Payload | Réponse |
|---|---|---|
| `/register` | `pseudo, password, email` | `ok, token, pseudo, melo, melo_random, theme` |
| `/login` | `pseudo, password` | idem + `photo` |
| `/ping` | `token` | idem (reconnexion auto par token) |
| `/search_user` | `token, pseudo` | profil |
| `/add_favorite` / `/remove_favorite` | `token, pseudo` | `ok` |
| `/list_favorites` | `token` | `favorites[]` |
| `/block_user` / `/unblock_user` | `token, pseudo` | `ok` |
| `/list_blocked` | `token` | `blocked[]` |
| `/list_followers` | `token` | `followers[]` |
| `/get_profile` | `token, pseudo` (vide = moi) | profil + `photo`, `description` |
| `/set_photo` | `token, photo` (`"theme\|Pièce"`) | `ok` |
| `/set_description` | `token, description` | `ok` |
| `/set_theme` | `token, theme` | `ok` |
| `/set_email` | `token, email` | `ok` |
| `/account_info` | `token` | `pseudo, melo, email, notif` |
| `/set_notif_prefs` | `token` + booléens `mail, turn, msg, defi_corr, defi_direct` | `ok` |
| `/set_fcm_token` | `token, fcm_token` | `ok` |
| `/save_game` | `token, game_uid, nmc_text, joueur1, joueur2, resultat, methode, cadence, objectif` | `ok` |
| `/list_games` | `token, pseudo` | `games[]` |
| `/get_game` | `token, game_uid` | `nmc_text` |
| `/send_message` | `token, pseudo, text` | `ok` |
| `/list_conversation` | `token, pseudo` | `messages[]` |
| `/list_conversations` | `token` | `conversations[], total_unread` |
| `/mark_read` | `token, pseudo` | `ok` |
| `/corr_list` | `token` | `games[]` |
| `/corr_defier` | `token, pseudo, objectif, random` | `ok, game_id` |
| `/corr_repondre` | `token, game_id, accepte` | `ok` |
| `/corr_jouer` | `token, game_id, notation, methode?` | `ok` |
| `/corr_abandon` | `token, game_id` | `ok` |
| `/corr_close` | `token, game_id` | `ok` |
| `/corr_proposer_nulle` | `token, game_id` | `ok` |
| `/corr_repondre_nulle` | `token, game_id, accepte` | `ok, nulle` |

### Socket.IO

**Émis par le client :**
`auth {token}` (à **chaque** (re)connexion — obligatoire),
`chercher_partie {objectif, cadence, random}`, `annuler_recherche {}`,
`defier {pseudo_cible, objectif, cadence, random}`, `annuler_defi {defi_id}`,
`repondre_defi {defi_id, accepte}`,
`jouer_coup {game_id, notation, clock_blanc, clock_noir}`,
`proposer_nulle {game_id}`, `fin_partie {...}`,
`pret_partie_suivante {...}`, `abandonner_match {...}`.

**Reçus du serveur :**
`auth_ok`, `auth_erreur`, `recherche_en_cours`, `partie_trouvee`, `recherche_timeout`,
`coup_adverse`, `partie_terminee`, `adversaire_deconnecte`, `adversaire_revenu`,
`reprise_partie`, `etat_partie`, `chat_recu`, `message_recu`, `nulle_proposee`,
`melo_maj`, `adversaire_pret`, `match_continue`, `match_over`, `match_abandonne`,
`defi_recu`, `defi_envoye`, `defi_echec`, `defi_refuse`, `defi_annule`.

Reconnexion automatique infinie ; `auth` est ré-émis sur chaque `connect`.

---

## 6. Modes de jeu

- **Local** (deux joueurs sur le même appareil)
- **Contre l'IA** (`vs_ai`, `ai_camp`, mode normal profondeur 2 / mode profond top-5 puis
  profondeur 3)
- **En ligne temps réel** (`online_mode`, Socket.IO, chrono synchronisé, chat en partie)
- **Correspondance** (`corr_mode`, HTTP asynchrone, un coup à la fois, notifications push)
- **Analyse** (`analysis_mode` — rejouer depuis une position, l'historique est clippé)
- **Replay / lecteur** (`replay_mode`, fichiers `.nmc`)
- **Random Fuga** (`RANDOM_MODE`) : position de départ générée depuis un **code**
  (`rf_parse_code`, `rf_random_code`, `rf_build_board`), partagé entre les deux joueurs.

### Objectif et score
`target` = `"partie"` (1 point) ou un nombre de points ; `target_max()` renvoie `"1"` pour
`"partie"`. Le match continue jusqu'à ce qu'un joueur atteigne l'objectif
(`_decide_next`, `_popup_continue`, `match_continue` / `match_over` en ligne).

### Chrono
`_tick` décrémente **chaque seconde** le camp au trait, **même en pause** (anti-triche).
`None` = illimité (`∞`). En ligne, on ne déclare la perte au temps que pour **sa propre**
horloge ; l'horloge adverse à 0 attend le signal du serveur.

---

## 7. IA « Deep Grey »

### Génération de coups
`dg_generate_moves(board, camp)` → liste de dicts
`{board, kind, fugue, fugue_by, mat_on, ej_ally, ej_opp, ejected, total_pushed,
  push_dirs_used, moved_cells, from, from_cells}`.
`kind` ∈ `move | jump | fugue | square | maneuver | knight`.
Pour les carrées, **toutes les combinaisons** de directions de poussée sont générées
(masque binaire sur les directions disponibles), plus le déplacement sans poussée.

### Évaluation
- `dg_positional_strategy` : table de valeurs du concepteur (unité ×10), symétrique,
  un seul balayage du plateau.
- Catégories pondérées apprises (`dg_weights.json`) :
  `heir_adv, heir_edge, heir_immo, heir_contact, nurse_adv, nurse_edge, nurse_mat,
   nurse_immo, nurse_groups, square_mat, square_immo, square_push`.
  Multiplicateur par défaut `1.0`, borné à **[0.60, 1.40]**, bougeant d'au plus
  **0.03 par partie** (`dg_learn_weights` après chaque partie, d'après la position finale).
- Heuristiques : `dg_count_isolated`, `dg_round_clusters`, `dg_advance_score`
  (Héritier ×1.5 + bonus centrage), `dg_square_advance_score`, `_dg_nurse_groups`,
  `_dg_heir_touches_nurse`, `_dg_square_ahead_of_rounds`, `_dg_is_immobile`,
  `_dg_square_can_push_forward`.

### Recherche
- `dg_choose_move(board, camp, depth=2, seen_positions, move_number)` — mode normal.
- `dg_choose_move_topn(..., top_n=5)` — mode profond : top 5 à profondeur 2, puis
  profondeur 3 sur ces 5.
- `dg_choose_move_deep(..., top_k=5)`, `_dg_score_move`.
- Cache d'évaluation `_DG_EVAL_CACHE`, vidé avant chaque réflexion.
- **Anti-répétition** : `_dg_own_pieces_key` compte les configurations de *nos* pièces
  (`_ai_pos_counts`), pénalité sur les positions déjà vues.
- **Anti allers-retours de groupe** : une 3ᵉ manœuvre consécutive est interdite
  (`_ai_consecutive_maneuvers >= 2` → on rejoue le meilleur coup non-manœuvre).
- **Livre d'ouvertures** (`dg_openings.json`) : `dg_lookup_opening`,
  `dg_record_winning_line`, `dg_save_openings`, clé `_dg_opening_key`.
  Garde-fou : on refuse un coup du livre qui donnerait la fugue à l'adversaire ou
  éjecterait nos pièces sans gagner.

> **Portage Flutter : l'IA doit tourner dans un `Isolate`.** En Kivy elle bloquait le
> thread principal ; c'est la cause de gel du chrono à corriger.

---

## 8. Règles immuables de robustesse (à reproduire)

Le code Kivy protège systématiquement les règles contre l'échec d'une animation :
- `animate_slide` **garantit** que `on_done` est appelé **exactement une fois**
  (drapeau `done_holder` + filet `Clock.schedule_once` à `durée + 0.5 s`).
- La **fugue** et le **mat** de l'IA ont chacun un drapeau anti-double-appel
  (`_ai_fugue_done`, `_ai_mat_done`) **et** un filet à 1 s.
- Conclusion : *la logique de jeu ne doit jamais dépendre du succès d'une animation.*

## 9. Correspondance — atomicité
Si un coup **clôt** la partie, il est envoyé **en une seule requête** avec sa méthode
(`corr_jouer(game_id, notation, methode)`), jamais en deux appels : cela évite les
doubles envois et les courses. `_corr_pending_method` est posé par `_end_turn` **avant**
`_record_move`.

---

## 10. Détails confirmés par `server.py` (2 692 lignes, Flask + Socket.IO + SQLite)

### Contraintes de compte
- `TOKEN_TTL` = **30 jours**.
- Pseudo : **3 à 20** caractères, `^[A-Za-z0-9_-]+$`.
- Délais : `MATCH_TIMEOUT` 60 s (message « essayez une autre cadence », le joueur
  **reste** en file), `DISCONNECT_GRACE` 60 s, `NEXT_GAME_GRACE` 60 s.

### Mélo (Elo)
- `K = 16` pour `mat` et `papatte`, `K = 32` sinon.
- Colonne DB `melo` en standard, **`melo_random`** quand `game["random"]` est vrai.
- Formule attendue standard : `1 / (1 + 10^((rb-ra)/400))`.

### Points de match
| Méthode | Points au gagnant |
|---|---|
| `mat`, `papatte` | **1** |
| `fugue`, `temps`, `abandon` | **2** |
| nulle | **0** |

Le même barème alimente le score head-to-head direct (`_add_direct_score`).

### Continuation de match (`_match_should_continue`)
- `objectif == "partie"` (ou `None`, ou `"flash"`) → **partie unique**, jamais de suivante.
- Objectif numérique `N` → on continue tant que le meneur n'a pas atteint `N`.
  Quand il l'atteint, l'adversaire a droit à une **dernière partie** s'il a joué Blanc
  **une fois de moins** (`blanc_count`), sauf si `last_chance` est déjà posé.

### Payloads Socket.IO exacts (serveur → client)

```
partie_trouvee  {game_id, couleur, adversaire, adversaire_melo, objectif, cadence, random_code}
coup_adverse    {game_id, notation, clock_adverse}
partie_terminee {game_id, methode, loser_color}
melo_maj        {game_id, mon_melo, delta}
match_continue  {game_id, score_blanc, score_noir, objectif}
match_over      {game_id, score_blanc, score_noir, objectif}
auth_ok         {pseudo, melo, melo_random, theme}
auth_erreur     {error}
adversaire_deconnecte {delai}
adversaire_revenu     {game_id}
nulle_proposee  {game_id}
chat_recu       {game_id, texte}
message_recu    {de, texte, ...}
defi_recu       {defi_id, de, objectif, cadence, ...}
defi_envoye     {defi_id, ...}
defi_echec      {raison}          # "hors_ligne" | "soi_meme" | "bloque"
defi_refuse     {defi_id, ...}
defi_annule     {defi_id}
etat_partie     {game_id, moves_text, ...}   # relais brut de "envoyer_etat"
reprise_partie  {game_id, ...}
```

### ⚠️ Bug d'horloge existant (client Kivy)
Le client émet `jouer_coup {game_id, notation, clock_blanc, clock_noir}` mais le serveur
lit **`clock_me`** (`data.get("clock_me")`) et relaie `coup_adverse {clock_adverse}`.
La synchronisation d'horloge est donc **inopérante aujourd'hui** : `clock_adverse` vaut
toujours `null`.

**Décision de portage :** le client Flutter émet `clock_me` **en plus** de `clock_blanc`
et `clock_noir`. Aucune modification du serveur n'est nécessaire, la compatibilité
descendante est totale, et la synchro d'horloge se met à fonctionner.

### Événements socket supplémentaires côté serveur
- `chat` → relayé en `chat_recu` (le client Kivy émet bien `chat`).
- `envoyer_etat` → relayé en `etat_partie` (reprise après déconnexion).

### Routes HTTP non utilisées par le client Kivy
- `/corr_chat_send` `{token, game_id, text}`
- `/corr_chat_list` `{token, game_id}`

→ Le chat de correspondance **existe côté serveur** mais n'est pas branché dans l'app
Kivy. À implémenter dans Flutter (gain de fonctionnalité sans toucher au serveur).

---

## 11. Thèmes

17 thèmes : `original, deepgrey, foret, ocean, volcan, hemo, spatial, imperial, royal,
terre, bonbon, arcenciel, etoile, medieval, fleur, insectes, dragon`.

Chaque thème définit 7 couleurs RGBA : `clair`, `fonce`, `clair_dim`, `fonce_dim`,
`board`, `menu`, `grid`. Extraites exactement dans `tool/extracted/THEMES.json`.

### Composition à 5 axes
Un thème courant est un texte composite `general|pieces|logo|menu|board` :

| Axe | Rôle |
|---|---|
| `general` | couleurs d'interface : touches, bandeaux, accents, grille |
| `pieces` | rendu des pièces (couleurs + formes) |
| `logo` | logo du menu |
| `menu` | fond du menu |
| `board` | plateau (couleur ou image) |

Rétro-compatible : un nom seul sans `|` ⇒ les 5 axes identiques.

> **Piège serveur :** le serveur **tronque** le thème stocké (historiquement à 40
> caractères), ce qui casse les composites longs. `_reconcile_theme` compare le thème
> local complet à sa version tronquée : si elles correspondent, on **garde le local**.
> À reproduire tel quel dans Flutter.

### Ressources par thème
- Thèmes à images : `themefleurs/`, `themedragon/`, `themebataille/` (médiéval),
  `themeinsectes/`, `theme_deepgrey/`.
- Fichiers attendus : `fond.png` (fond de menu), `plateau.png` (plateau),
  et les pièces `heritier/nurse/soldat/garde/chevalier` × `blanc/noir`.
  Attention : la convention de nommage **diffère** entre thèmes
  (`chevalierblanc.png` vs `chevalier_blanc.png`).
- `logos/logo_<theme>.png` — 16 logos.
- `themeinsectes` a `carreeblanc.png` / `carreenoir.png` au lieu de soldat/garde séparés.

---

## 12. Langues

10 langues : `fr` (source), `en, de, es, it, zh, ja, ko, ru, pt`.
**415 clés** de traduction extraites dans `tool/extracted/TRANSLATIONS.json`
(le français est la clé, pas une valeur).
Police CJK embarquée : `polices/NotoSansCJKsc-Regular.otf` (16,4 Mo).
`STORY_I18N` : l'histoire du jeu dans 9 langues + le français en dur.

---

## 13. Échelle d'affichage

Calibrage sur **Samsung Galaxy A06, 720 px de large** (`REF_WIDTH = 720.0`).
- `S(value)` = `value * largeur_écran / 720`
- `SF(taille)` = `taille * largeur_écran / 720 * FONT_BOOST`, avec `FONT_BOOST = 1.70`,
  en **pixels purs** (surtout pas de `sp`/`dp` : le texte doit occuper la même
  proportion de l'écran quelle que soit la densité).
- `SLIDE_SPEED = 0.18` s (animation de glissement, réglable, 0 = instantané).
- MSAA désactivé (`multisamples = 0`) pour la fluidité GPU mobile.

En Flutter : reproduire avec un facteur d'échelle basé sur `MediaQuery.size.width / 720`
et **ignorer** `textScaleFactor` du système (équivalent du refus de `sp`).

---

## 14. Random Fuga

Code de position `[symbole][Position]-[Disposition]`, ex. `.03-09` ou `/18-54` :
- symbole `.` = rotation 180° (colonnes inversées do↔si, ré↔la, mi↔sol, fa↔fa)
- symbole `/` = réflexion horizontale (colonnes gardées, Héritiers face à face)
- `Position` 1..25 = (Héritier × Chevalier) sur `[ré, mi, fa, sol, la]`
- `Disposition` 1..70 = la D-ième combinaison de **4 Gardes parmi 8 carrées**,
  lues en U : `do2, do1, [ré/mi/fa/sol/la sauf Héritier], si1, si2`
- Total : 2 × 25 × 70 = **3 500** positions.

Le code est généré par le serveur (`random_code` dans `partie_trouvee`) et partagé
par les deux joueurs. Mélo séparé (`melo_random`).

---

## 15. Stockage local

`config.txt`, format `clé=valeur` une par ligne. Clés connues :
`theme, volume, lang, server_url, online_token, online_pseudo, online_melo,
online_melo_random`, plus des clés libres.
Parties locales : dossier `parties/`, fichiers `.nmc`.
IA : `dg_weights.json` (poids appris), `dg_openings.json` (livre d'ouvertures).

En Flutter : `SharedPreferences` pour la config, `path_provider` +
`getApplicationDocumentsDirectory()` pour `parties/`, `dg_weights.json`,
`dg_openings.json`.
