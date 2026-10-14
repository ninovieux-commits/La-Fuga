# Le serveur qui plante : la cause, la preuve, le correctif

**La cause est identifiée avec certitude**, elle était écrite dans le journal de
ton serveur :

```
OSError: [Errno 24] Too many open files
<WSGIServer at ... address=0.0.0.0:5000> failed with OSError
```

Et l'état du processus au moment de la panne :

```
1024 descripteurs de fichiers ouverts   ← limite : exactement 1024
1014 → /home/ubuntu/lafuga/lafuga.db
   2 connexions réseau établies
```

**1014 connexions SQLite jamais fermées.** Le serveur n'avait plus un seul
descripteur pour accepter une connexion. Il ne mourait pas pour autant : systemd
le voyait `active (running)`, donc `Restart=always` ne se déclenchait jamais.
Vivant mais muet — d'où le redémarrage à la main.

---

## 1. Pourquoi ça fuit, exactement

Le code interroge la base partout sous cette forme :

```python
row = get_db().execute("SELECT ...", (...)).fetchone()
```

Cette connexion **n'est jamais fermée par le comptage de références** : une
connexion `sqlite3` et son curseur forment un **cycle de références**. Seul le
ramasse-miettes *cyclique* peut les libérer. Et lui ne passe que quand il y a eu
assez d'allocations mémoire.

Vérifié, chiffres à l'appui :

```
ramasse-miettes cyclique ACTIF     : 300 connexions non fermées →  64 descripteurs
ramasse-miettes cyclique DÉSACTIVÉ : 300 connexions non fermées → 304 descripteurs
puis gc.collect() explicite        →   4 descripteurs
un seul gc.collect() libère 11 objets pour UNE connexion non fermée
                                     → c'est bien un cycle
```

D'où le paradoxe que tu décrivais sans le savoir : **c'est précisément parce que
vous êtes peu nombreux que ça plante.** Peu de joueurs = peu d'allocations = le
ramasse-miettes passe rarement = les connexions s'empilent sans jamais être
libérées. Sous forte charge, il tourne en permanence et masque le problème —
c'est exactement pour ça que mes premiers tests de charge ne l'ont pas vu, et que
je t'avais écrit à tort qu'il n'y avait pas de fuite de descripteurs. Ton journal
de production avait raison, pas mes tests.

Et le débit collait : **1014 descripteurs en 5 h 34**, soit ≈ 3 par minute.

Deux aggravants, tous deux mesurés :

- **`corr_list` ouvrait la base 32 fois par appel** (avec 10 parties de
  correspondance) parce que `_corr_game_dict` faisait 3 requêtes par partie, sur
  3 connexions. Et l'appli sonde `corr_list` toutes les 3 secondes.
- **La limite était à 1024**, le défaut de systemd. Pour un serveur à sockets,
  c'est très bas.

---

## 2. Le correctif

Le principe : **ne plus jamais dépendre du ramasse-miettes.** Une seule connexion
par requête, fermée de force à la fin — fin de requête HTTP (`teardown_request`),
fin d'événement Socket.IO (le garde-fou), fin de tâche de fond (ménage,
notifications, minuteurs). Les 65 appels à `get_db()` et les 51 `conn.close()`
existants n'ont pas eu à être touchés : `close()` devient une fermeture différée,
et la vraie fermeture est garantie ailleurs.

### La preuve

Descripteurs pointant sur `lafuga.db`, pendant 300 sondages de `corr_list` avec
10 parties de correspondance — c'est-à-dire exactement l'usage qui te faisait
tomber :

| | original | corrigé |
|---|---|---|
| au repos, avant tout | **46** | **0** |
| pendant les 300 appels | 36 → 93 | **0** |
| pic observé | **93** | **0** |
| au repos, après | 42 | **0** |

Le serveur d'origine traînait 46 connexions ouvertes **sans rien faire**. Le
corrigé en garde **zéro**, en permanence.

Et une soupape : `LAFUGA_DB_PARTAGE=0` revient à une vraie connexion par appel
(comportement d'origine) tout en garantissant leur fermeture. Testé aussi :
zéro descripteur qui traîne, et parité complète.

### Les 23 corrections

| | Correction | Effet mesuré |
|---|---|---|
| 1 | **Une connexion par requête, fermée de force** | **93 → 0** descripteurs qui traînent. C'est LE correctif. |
| 2 | `corr_list` : préchargement groupé | **32 → 3** ouvertures, **32 → 5** requêtes, **8,34 → 2,18 ms** |
| 3 | `list_conversations` : idem | 15 conversations : **47 → 19** requêtes |
| 4 | 5 index manquants (`messages`, `corr_games`, `tokens`) | les routes ne ralentissent plus avec la taille de la base |
| 5 | `PRAGMA journal_mode = WAL` | lecteurs et écrivain avancent ensemble : plus de gel sur verrou |
| 6 | `busy_timeout = 30 s`, `synchronous = NORMAL` | plus de « database is locked », plus de `fsync` par écriture |
| 7 | `cache_size` à 1 Mo par connexion | mémoire par requête en vol divisée par deux |
| 8 | Journal plafonné (4 × 5 Mo, rotation), horodaté | le journal ne peut plus dépasser 20 Mo |
| 9 | Notifications Firebase en tâche de fond, réserve de 20, délai max 20 s | le joueur n'attend plus Google ; un Firebase en panne ne noie pas le serveur |
| 10 | `_apply_melo` sorti du `with LOCK` (2 endroits) | plus aucune écriture SQLite verrou global tenu |
| 11 | Garde-fou sur tous les gestionnaires et toutes les routes | une erreur est attrapée, **comptée**, journalisée ; jamais de page HTML de trace renvoyée à l'appli |
| 12 | Ménage périodique (5 min) | purge défis expirés, parties muettes, `sid` fantômes, jetons périmés |
| 13 | Concurrence bornée à 400 | plus de rafale incontrôlée |
| 14 | Arrêt propre sur SIGTERM | base fermée sans verrou, requêtes en cours terminées |
| 15 | Route `/health` avec le compteur `descripteurs_base` | tu vois la fuite AVANT qu'elle ne te tombe dessus |
| 16 | `list_games` : ordre stable | deux parties enregistrées dans la même seconde s'affichaient dans un ordre arbitraire — vérifié : l'ordre changeait d'un appel à l'autre sur le serveur d'origine |

(Les 23 entrées sont listées par `patch_serveur.py` à l'exécution ; ci-dessus les
16 corrections distinctes.) Détail ligne par ligne dans `serveur.diff`.

### Latence, sur la version finale

| | original | corrigé |
|---|---|---|
| `corr_list` (10 parties) | 8,34 ms | **2,18 ms** |
| `list_conversations` | 1,85 ms | 1,77 ms |
| connexions SQLite ouvertes simultanément | **87** | **3** |

---

## 3. Vérifications de non-régression

Rien ici n'est affirmé sans avoir été exécuté. Tous ces tests sont dans `tests/`,
tu peux les relancer (`tests/README.md`).

**L'original et le corrigé lancés côte à côte**, même tirage aléatoire, même
scénario, réponses comparées champ par champ :

- **81 appels HTTP** couvrant les 36 routes — inscription, connexion, profils,
  favoris, blocages, messagerie, historique, correspondance complète
  (défi / réponse / coups / nulle / abandon / chat / fermeture) — **cas d'erreur
  inclus** : **81 identiques sur 81**.
- **32 événements Socket.IO** sur un scénario temps réel complet — matchmaking,
  coups, chat, état, nulle, fin de partie, mélo, partie suivante, abandon de
  match, défi direct accepté puis refusé, annulation de recherche, déconnexion
  brutale : **32 identiques sur 32**.
- Les deux suites repassent aussi en mode `LAFUGA_DB_PARTAGE=0` : **identiques**.

**Migration d'une base existante.** Base créée par le serveur d'origine
(5 comptes, 5 parties, 11 index, journal `delete`) : au premier démarrage elle
passe en `wal`, les 5 index manquants sont créés (11 → 16), **données intactes**,
un compte existant se connecte normalement (thème et mélo retrouvés). Aucune
intervention manuelle.

**Le ménage n'oublie jamais une partie en cours.** Tout événement portant un
`game_id` réhorodate la partie. Délai d'oubli réglé à 5 s, partie maintenue par
des coups pendant 26 s → toujours là ; la partie muette, elle, disparaît.

**Le ménage n'éjecte pas les joueurs connectés.** Piège rencontré en écrivant ce
code : le `sid` Socket.IO n'est pas le `sid` engine.io. Ma première version
éjectait **tous** les joueurs connectés à chaque passage — le test l'a attrapé
(`connectes` retombait à 0 au bout de 3 s, le joueur recevait `auth_erreur`).
Corrigé : on interroge Socket.IO lui-même et on ne purge que sur un « non »
franc. Retesté : 3 joueurs, 12 s de ménage, toujours 3, et ils peuvent jouer.

**Robustesse.** 28 événements Socket.IO volontairement malformés : le serveur
reste debout, la session reste utilisable, les 20 erreurs sont attrapées,
comptées par événement, visibles dans `/health`.

**Arrêt propre.** `kill -TERM` → `signal 15 : arret propre` puis `arrete` dans le
journal, aucun fichier `-wal`/`-shm` laissé derrière.

**Charge soutenue** (30 clients, 7 minutes, cinq routes en boucle) : +15 % de
requêtes traitées, médiane 89 → 78 ms, p95 131 → 108 ms, mémoire finale
81,6 → 69,2 Mo. Zéro erreur des deux côtés.

---

## 4. Déploiement

```bash
cd /home/ubuntu/lafuga

# 1. Sauvegarde
cp server.py server.py.avant
sqlite3 lafuga.db ".backup lafuga.db.avant"
#    (sans la commande sqlite3 :
#     python3 -c "import sqlite3; a=sqlite3.connect('lafuga.db'); b=sqlite3.connect('lafuga.db.avant'); a.backup(b)")

# 2. Applique les corrections
python3 patch_serveur.py server.py --inplace
#    -> server.py corrigé, server.py.bak conservé.
#    Si un seul motif manque, il s'arrête SANS rien modifier — y compris si tu le
#    relances par erreur sur un fichier déjà corrigé (vérifié).

# 3. Redémarre
sudo systemctl restart lafuga

# 4. Vérifie
curl -s http://127.0.0.1:5000/health | python3 -m json.tool
```

Dans la réponse, trois choses :

- `"journal": "wal"` → les réglages de base sont actifs
- `"descripteurs_base": 3` → une seule connexion ouverte, celle de cette
  requête. **C'est le chiffre qui montait à 1014.** En WAL, une connexion = 3
  descripteurs (la base, le `-wal`, le `-shm`), donc 3 est la valeur normale.
- `"ok": true`

Le premier démarrage bascule la base en WAL : deux fichiers `lafuga.db-wal` et
`lafuga.db-shm` apparaissent à côté, c'est normal. **Pour sauvegarder la base,
utilise désormais `sqlite3 lafuga.db ".backup sauvegarde.db"`** — un simple `cp`
du seul fichier `.db` peut manquer les dernières transactions.

### La preuve, sur ton serveur

Une heure après le redémarrage, puis le lendemain :

```bash
curl -s http://127.0.0.1:5000/health | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['uptime_s'],'s ->',d['db']['descripteurs_base'],'descripteurs')"
```

Le nombre doit rester à 3, quel que soit le temps de fonctionnement. S'il grimpe,
envoie-moi la sortie complète de `/health`.

### Le filet de sécurité

La limite de descripteurs, tu l'as déjà relevée :

```bash
# /etc/systemd/system/lafuga.service.d/limites.conf
[Service]
LimitNOFILE=65535
```

Garde-la : même sans fuite, 1024 est trop bas pour un serveur à sockets.

`lafuga.service` (fourni) ajoute `MemoryMax`, l'arrêt propre et
`StartLimitIntervalSec=0` — utile si tu veux repartir d'une unité complète.

`lafuga-sante.timer` interroge `/health` toutes les 2 minutes et redémarre si ça
ne répond pas deux fois de suite. C'est ce qui aurait couvert ta panne : systemd
relance un processus **mort**, pas un processus **vivant qui ne répond plus**.
C'est exactement ce que tu as vécu.

---

## 5. Ce que je n'ai pas fait

- **Aucun changement de protocole**, aucun changement du format des
  notifications, aucun changement de Firebase.
- **Aucun changement de schéma de base** : uniquement des index ajoutés, et le
  `DELETE` des jetons périmés que `TOKEN_TTL` prévoyait déjà.
- **Je n'ai pas déplacé SQLite hors du fil principal.** Avec WAL et les requêtes
  groupées, chaque requête dure quelques dizaines de microsecondes. Si tu montes
  à des centaines de joueurs simultanés, c'est l'étape suivante — et il faudra
  probablement passer à PostgreSQL.
- **`sio.emit()` en tenant `LOCK`** (5 endroits) : vérifié, ce n'est pas un
  problème. `emit` empile le paquet dans une file, il n'attend jamais le réseau.
- **Deux LECTURES en base restent dans un `with LOCK`** (`_get_user_melo` dans
  `on_pret_partie_suivante`, `_is_blocked_pair` dans `_try_match`) : des `SELECT`
  sur index, et en WAL une lecture n'attend plus jamais un écrivain. Les déplacer
  voudrait dire réorganiser la logique du matchmaking pour un gain nul. Tu sais
  qu'elles sont là.
- **Les 14 copies `server_backup*.py`** dans `/home/ubuntu/lafuga/` : je n'y ai
  pas touché. Elles ne gênent rien, mais tu gagnerais en clarté à les ranger
  ailleurs.

---

## 6. La correspondance en direct — `patch_direct.py`

Aucune route de correspondance n'émettait le moindre événement Socket.IO.
Jouer un coup, proposer une nulle, abandonner, accepter un défi : tout cela
partait en notification push, et **rien** n'allait à une application ouverte.
Elle ne pouvait donc qu'une chose, redemander la liste toutes les quatre
secondes — quinze requêtes par minute et par écran, pour un coup qui mettait
quand même jusqu'à quatre secondes à apparaître.

Un seul point d'insertion suffit. Chaque mutation appelle déjà `_notify_user`
avec un dictionnaire qui porte son type et son `game_id` : on prévient en
direct au même endroit, sous l'événement **`maj_directe`**, avec la même
charge utile. Les deux chemins disent la même chose, et toute notification
ajoutée plus tard sera temps réel sans y penser.

L'émission est placée **avant** le filtre des préférences, et c'est voulu :
ces préférences disent ce qu'on veut recevoir sur son téléphone quand
l'application est fermée. Ici elle est ouverte et affiche la partie — elle
doit se mettre à jour même si les push sont coupées.

Seconde correction : l'acceptation d'un défi ne prévenait que le joueur des
Blancs. Le défieur n'apprenait jamais que sa partie avait démarré. Il est
maintenant prévenu en direct, sans push — « à vous de jouer » serait faux
s'il a les Noirs.

```bash
python3 patch_direct.py /home/ubuntu/lafuga/server.py
sudo systemctl restart lafuga
```

### La preuve

```bash
python3 tests/test_direct.py <port>
```

| | avant | après |
|---|---|---|
| défi en correspondance | — | **20 ms** |
| acceptation du défi | — | **20 ms** |
| coup joué | — | **20 ms** |
| message du chat de partie | — | **20 ms** |
| proposition de nulle | — | **20 ms** |
| message privé | — | **20 ms** |
| total | **1/9** | **9/9** |

Non-régression, sur deux serveurs neufs et dans cet ordre :

```bash
python3 tests/parite_sio.py <A> <B>   # 32 événements — IDENTIQUES
python3 tests/parite.py     <A> <B>   # 81 appels — 81 identiques, 0 différents
```

## 7. Le pré-coup en correspondance — `patch_premove.py`

En correspondance, l'attente se compte en heures. Quand on sait déjà quoi
répondre à ce que l'adversaire va jouer, on le prépare : s'il joue le coup
prévu, la réponse part toute seule.

**Toute la valeur de la chose est là : la réponse doit partir même application
fermée.** Un pré-coup qui ne se déclencherait qu'à l'ouverture de
l'application ne servirait à rien — à ce moment-là, on pourrait jouer. C'est
donc le serveur qui joue le coup préjoué, à l'instant où le coup de
l'adversaire arrive. `tests/test_premove.py` ne fait jamais semblant d'être le
client qui a préjoué : il enregistre un plan, puis n'ouvre plus aucune socket.

Une **variante** est une suite de demi-coups qui part de la position où
l'adversaire a le trait :

    indice 0 : son coup   indice 1 : le nôtre   indice 2 : son coup   …

Les indices **pairs** sont à lui, les **impairs** à nous. Une variante
s'arrête toujours sur un des nôtres : s'arrêter sur le sien ne préparerait
rien. Six variantes au plus, six demi-coups au plus, et **aucune ne doit
contredire une autre** — deux variantes qui partagent le même début ne peuvent
pas y répondre de deux façons différentes. Le serveur revérifie la règle :
c'est lui qui joue vraiment, il ne fait pas confiance à ce qu'on lui envoie.

**Le serveur ne connaît pas les règles du jeu** — il n'a jamais validé un coup
de correspondance, il empile des notations. Ce n'est pas un problème, et c'est
même le cœur de l'affaire : une variante décrit une ligne complète depuis une
position connue. Si l'adversaire joue le coup prévu, la position est exactement
celle que l'application avait sous les yeux en composant, donc la réponse y est
légale par construction. Pour la même raison, c'est l'application qui dit si
notre coup termine la partie (`methode`, `gagnant`) : elle seule a compté.

Ce qui est ajouté :

| | |
|---|---|
| `import json` | le serveur n'avait jamais rien eu à sérialiser lui-même |
| table `corr_premoves` | un plan par (partie, joueur) |
| colonne `premove_pour` | à qui l'on doit le popup « il avait préjoué » |
| `POST /corr_premove` | enregistrer ou effacer son plan |
| `POST /corr_premove_vu` | le popup a été vu, on l'éteint |
| `corr_jouer` | joue la réponse préjouée, s'il y en a une |
| `_corr_game_dict` | `premove`, `premove_adverse`, `premove_par` |

Ces trois clés ne sont posées **que** quand il y a quelque chose à dire : pour
qui ne préjoue pas, l'aperçu des parties garde exactement les octets qu'il
avait, et le banc de parité le vérifie.

`_premove_terminer` est le **jumeau volontaire** du bloc `if methode:` de
`corr_jouer` : les deux clôturent une partie, l'un sur un coup préjoué, l'autre
sur un coup joué à la main. Ils sont séparés pour que le chemin d'origine ne
bouge pas d'une ligne. Un test compare les deux parties obtenues : si l'un
dérive de l'autre, il le dit.

```bash
python3 patch_premove.py /home/ubuntu/lafuga/server.py
sudo systemctl restart lafuga
```

**Déployé le 6 octobre 2026 à 12 h 39.** `server.py` est passé de
`e118ed5c0415…` à `fef047f4944d…` — l'empreinte exacte du fichier éprouvé.
Sauvegardes posées avant : `server.py.avant-premove-20261006-123844` et
`lafuga.db.avant-premove`. Vérifié après redémarrage, sans rien écrire dans la
base : table `corr_premoves` présente, colonne `premove_pour` présente, les
deux routes répondent « Token invalide » (une route absente rendrait une page
404).

### La preuve

```bash
python3 tests/test_premove.py <port>
```

| | serveur actuel | avec le patch |
|---|---|---|
| la réponse préjouée est jouée par le serveur | ECHEC | **OK** |
| c'est aussitôt de nouveau à celui qui a joué | ECHEC | **OK** |
| le popup est dû, et nomme l'adversaire | ECHEC | **OK** |
| la bonne variante répond parmi plusieurs | ECHEC | **OK** |
| une variante de six demi-coups se déroule | ECHEC | **OK** |
| un coup imprévu ne déclenche rien, le plan meurt | OK | **OK** |
| un mat préjoué clôt la partie comme un mat joué | ECHEC | **OK** |
| la méthode ne vaut que pour le dernier coup | ECHEC | **OK** |
| les neuf refus de la règle (contradiction, doublon, 7 variantes, 8 demi-coups…) | — | **OK** |
| préjouer quand on a soi-même le trait : refusé | — | **OK** |
| un tiers ne préjoue pas chez les autres | — | **OK** |
| total | **25/40** | **40/40** |

Non-régression, sur deux serveurs neufs et dans cet ordre :

```bash
python3 tests/parite_sio.py <A> <B>   # 32 événements — IDENTIQUES
python3 tests/parite.py     <A> <B>   # 81 appels — 81 identiques, 0 différents
```

## 8. La position personnalisée — `patch_position.py`

Une partie de correspondance pouvait partir de deux endroits : la position de
toujours, ou une des positions tirées au sort (un code Random Fuga). Elle peut
maintenant partir d'une position **composée**, décrite au format `.fug` sur une
seule ligne :

    B/sgshgsg/gnnnnns/---c---/-------/-------/---C---/GNNNNNS/SGSHGSG

La première lettre dit qui a le trait (`B` ou `N`), puis huit rangées de sept
caractères, de do1 à si1 d'abord. Minuscule pour les Blancs, majuscule pour les
Noirs ; `h` Héritier, `n` Nurse, `c` Chevalier, `g` Garde, `s` Soldat, `-` case
vide. Le mode ne vit qu'en correspondance — il n'y a pas de mélo en
correspondance, et le score, lui, compte.

**Le trait vient de la position.** Une partie démarrait toujours aux Blancs ;
une position composée peut vouloir que les Noirs commencent. Le `turn` de la
partie est donc lu dans la première lettre du `.fug` — un chemin que le serveur
n'avait jamais pris, et que le banc d'essai parcourt jusqu'au bout : les Noirs
jouent le premier coup, les Blancs ne peuvent pas jouer avant eux.

**Le serveur vérifie la position, il ne la croit pas.** L'application la vérifie
déjà, mais c'est le serveur qui garde la partie : une position mal formée s'y
installerait pour de bon, et chaque client la relirait de travers. Les deux
règles de Nino sont donc appliquées ici aussi — un Héritier par camp, et des
carrées qui peuvent bouger des deux côtés. Elles ne demandent pas de connaître
les règles du jeu : compter des lettres et regarder les voisines d'une case
suffit.

**La couleur aléatoire se tire à l'acceptation.** « Aucun des deux joueurs ne
doit savoir qui va avoir les blancs tant que la partie n'a pas démarré. » Un
serveur ne peut pas cacher ce qu'il a écrit : il envoie `ma_couleur` avec chaque
défi, et le masquer demanderait un garde à chaque endroit qui le lit. Il ne
l'écrit donc qu'une fois la partie partie. La répartition posée à la création
reste provisoire et ne veut rien dire — elle est refaite au moment où le défi
est accepté.

Ce tirage ne concerne **que** les défis venus d'une application corrigée
(celles-là envoient un `mode`). Le client Kivy oriente en effet l'aperçu d'un
défi selon la couleur reçue (`main.py:3932`) : la lui changer à l'acceptation
retournerait son plateau sous ses yeux. Une colonne `mode` vide est la marque
d'un défi d'avant, et il garde l'ancien comportement exactement.

Ce qui est ajouté :

| | |
|---|---|
| colonnes `mode`, `position`, `couleur` | d'où part la partie, et la couleur **demandée** (`''` = aléatoire) |
| `_fug_lire`, `_fug_refus` | lire une position, et dire pourquoi elle ne peut pas servir |
| `/corr_defier` | lit les trois champs, en tire le trait, refuse une position injouable |
| `/corr_repondre` | tire la couleur à l'acceptation, quand elle est aléatoire |
| `_corr_game_dict` | `mode`, `position`, `couleur` |
| `_archive_corr_game` | écrit `[Position "…"]` dans l'en-tête du `.nmc` |

Cette dernière ligne est ce qui fait qu'une partie composée se **rejoue** : sans
elle, l'historique la relirait depuis la position standard, c'est-à-dire
n'importe quoi. Le code Random tient en six caractères, une position en
soixante-trois : c'est la même idée, en plus long.

```bash
python3 patch_position.py /home/ubuntu/lafuga/server.py
sudo systemctl restart lafuga
```

**Déployé le 6 octobre 2026 à 22 h 10.** `server.py` est passé de
`fef047f4944d…` à `0983dc8662ba…` — l'empreinte exacte du fichier éprouvé.
Sauvegarde posée avant : `server.py.avant-position-20261006-221045`. Vérifié
après redémarrage, sans rien écrire dans la base : les trois colonnes sont
présentes et les deux parties en cours sont intactes.

### La preuve

```bash
python3 tests/test_position.py <port>
```

| | serveur actuel | avec le patch |
|---|---|---|
| la position est rendue telle quelle, aux deux joueurs | ECHEC | **OK** |
| une position composée n'a pas de code Random | OK | **OK** |
| le trait est aux Noirs quand le `.fug` dit `N` | ECHEC | **OK** |
| les Noirs jouent le premier coup, les Blancs ne peuvent pas | ECHEC | **OK** |
| cinq positions mal formées refusées | ECHEC | **OK** |
| un camp sans Héritier, deux Héritiers : refusés | ECHEC | **OK** |
| des carrées qui ne peuvent pas bouger : refusé | ECHEC | **OK** |
| aucune partie créée par ces refus | ECHEC | **OK** |
| la couleur demandée est respectée, et ne change pas | ECHEC | **OK** |
| la couleur aléatoire change entre le défi et le départ | ECHEC | **OK** |
| sans `mode`, elle ne change **jamais** | OK | **OK** |
| l'en-tête du `.nmc` porte `[Position "…"]` | ECHEC | **OK** |
| une partie standard n'a pas de ligne `Position` | OK | **OK** |
| total | **15/41** | **41/41** |

Les deux lignes de couleur ne se prouvent pas sur une partie : il faut en lancer
assez pour voir la couleur **changer**. Vingt-quatre parties de chaque sorte —
**10 changements sur 24** pour le tirage à l'acceptation, **0 sur 24** pour un
défi sans `mode`. Zéro dans le premier cas voudrait dire que le tirage a lieu à
la création.

Non-régression, sur deux serveurs neufs et dans cet ordre :

```bash
python3 tests/parite_sio.py <A> <B>   # 32 événements — IDENTIQUES
python3 tests/parite.py     <A> <B>   # 81 appels — 75 identiques, 6 différents
```

Les six différences sont toutes sur `corr_list`, et toutes dues aux trois clés
ajoutées. En les retirant **des deux côtés** avant de comparer, il ne reste
rien : **81 identiques, 0 différents**. C'est la preuve que le patch ajoute
trois champs et ne touche à rien d'autre.

## 9. L'instrument dans le compte — `patch_instrument.py`

Le choix de l'instrument vivait sur l'appareil. Changer de téléphone, ou se
reconnecter après une réinstallation, et l'on retrouvait le piano. Il s'enregistre
maintenant dans le compte, exactement comme le thème.

**Le vide compte.** Un compte qui n'a jamais choisi rend `''`, et non `'piano'`.
C'est ce qui distingue « ce compte veut le piano » de « ce compte n'a jamais rien
dit » : dans le second cas, c'est l'application qui envoie l'instrument de
l'appareil, au lieu d'en adopter un. Les confondre remettrait le piano à
quelqu'un qui venait de choisir la harpe.

**Aucune liste d'instruments côté serveur.** Il nettoie la valeur — lettres
minuscules, vingt caractères au plus — mais ne tient pas la liste de ce qui
existe. Sinon, ajouter une flûte à l'application demanderait de redéployer le
serveur pour qu'il daigne l'enregistrer. L'application, elle, se garde déjà d'un
nom inconnu : elle retombe sur le premier instrument plutôt que de rester muette.

| | |
|---|---|
| colonne `users.instrument` | `''` quand le compte n'a jamais rien dit |
| `POST /set_instrument` | le jumeau de `/set_theme` |
| `/register`, `/login`, `/ping` | rendent `instrument` avec le reste |

**Déployé le 6 octobre 2026 à 23 h 35**, avec le patch suivant.

### La preuve

```bash
python3 tests/test_instrument.py <port>
```

| | serveur actuel | avec le patch |
|---|---|---|
| un compte tout juste créé rend un instrument VIDE | ECHEC | **OK** |
| le choix revient à la connexion suivante, et au ping | ECHEC | **OK** |
| on peut changer d'avis, et effacer | ECHEC | **OK** |
| espaces, majuscules et ponctuation sont nettoyés | ECHEC | **OK** |
| un nom trop long est coupé à vingt | ECHEC | **OK** |
| un instrument inconnu du serveur est accepté | ECHEC | **OK** |
| sans jeton, rien, et le choix ne bouge pas | OK | **OK** |
| total | **4/17** | **17/17** |

Non-régression : 32 événements Socket.IO **identiques**, et 81 appels HTTP dont 5
diffèrent — `register`, `login`, `ping` — uniquement par la clé ajoutée. En la
retirant des deux côtés avant de comparer : **81 identiques, 0 différents**.

## 10. Deux règles de plus pour une position — `patch_regles.py`

Après « un Héritier par camp » et « des carrées qui peuvent bouger des deux
côtés », une position composée doit aussi :

- **laisser au moins trois cases libres.** Un plateau presque plein ne laisse
  nulle part où aller : rien ne peut avancer, et la partie serait nulle d'entrée
  comme avec des carrées bloquées.
- **n'avoir qu'un Chevalier au plus par camp.** Zéro est permis, deux ne l'est
  pas. Le composeur ne sait pas en poser un second — il déplace celui qui est là
  — mais un code `.fug` écrit à la main peut en contenir dix. C'est le lecteur
  `.fug` qui a rendu la règle nécessaire : il doit refuser un tel code, donc la
  règle doit exister quelque part de vérifiable.

`_fug_refus` rend donc aussi `'vides'` et `'chevalier'`, et `/corr_defier`
refuse avec `position_vides` et `position_chevalier`. La fonction n'est appelée
que dans la branche `mode == "personnalise"` : tout le reste du serveur ne voit
pas la différence, et les parties en cours ne sont pas relues.

**Déployé le 6 octobre 2026 à 23 h 35.** `server.py` est passé de
`0983dc8662ba…` à `e9be24f9bc29…` — l'empreinte exacte du fichier éprouvé, les
deux patchs appliqués. Ils **commutent** : dans un ordre ou dans l'autre, le
fichier final est identique au bit près. Sauvegardes posées avant :
`server.py.avant-instrument-20261006-233504` et
`server.py.avant-regles-20261006-233504`.

### La preuve

```bash
python3 tests/test_position.py <port>
```

| | sans ces règles | avec le patch |
|---|---|---|
| refus : deux Chevaliers du même camp | ECHEC | **OK** |
| un seul Chevalier passe, et zéro aussi | OK | **OK** |
| refus : moins de trois cases libres | ECHEC | **OK** |
| mais trois cases libres suffisent | OK | **OK** |
| aucune partie créée par ces refus | ECHEC | **OK** |
| total (tout le banc des positions) | **42/45** | **45/45** |

## 11. La vitesse de glissée dans le compte — `patch_glissee.py`

Même histoire que l'instrument, avec un piège de plus.

**Zéro est un CHOIX.** La glissée instantanée est un réglage que des joueurs
veulent, pas une absence de réglage. Le marqueur « ce compte n'a jamais rien
dit » ne peut donc pas être zéro — sinon leur choix serait remplacé par celui de
l'appareil à chaque connexion. C'est **-1**, une valeur qu'une durée ne peut pas
prendre.

Le naturel `user.get("glissee") or -1` fait exactement cette faute : `or` prend
un zéro pour une absence. D'où `_glissee_de`, et deux assertions qui tombent si
on l'écrit autrement — vérifié en l'écrivant mal exprès.

| | |
|---|---|
| colonne `users.glissee` | `-1` quand le compte n'a jamais rien dit |
| `POST /set_glissee` | borne à [0, 10] s, refuse ce qui n'est pas un nombre |
| `/register`, `/login`, `/ping` | rendent `glissee` avec le reste |

Les bornes sont larges exprès : de quoi tenir toute échelle que l'application
voudra offrir, sans redéployer le serveur quand elle change son curseur.

**Déployé le 6 octobre 2026 à 23 h 57.** `server.py` est passé de
`e9be24f9bc29…` à `fc5f961a5f0f…`. Sauvegarde posée avant :
`server.py.avant-glissee-20261006-235725`.

### La preuve

```bash
python3 tests/test_glissee.py <port>
```

| | serveur actuel | avec le patch |
|---|---|---|
| un compte neuf rend `-1`, et non zéro | ECHEC | **OK** |
| le choix revient à la connexion suivante, et au ping | ECHEC | **OK** |
| **zéro revient comme zéro**, et non comme `-1` | ECHEC | **OK** |
| une valeur négative est ramenée à zéro, une énorme coupée à dix | ECHEC | **OK** |
| un texte, ou rien, est refusé | OK | **OK** |
| sans jeton, rien, et le compte ne bouge pas | OK | **OK** |
| total | **4/16** | **16/16** |

En écrivant `user.get("glissee") or -1` à la place de `_glissee_de` : **14/16**
— les deux assertions du zéro, et elles seules.

Les deux autres bancs sur le serveur corrigé : **45/45** et **17/17**,
inchangés. Non-régression : 32 événements Socket.IO **identiques**, et 81 appels
HTTP dont 5 diffèrent par la seule clé ajoutée — en la retirant des deux côtés,
**81 identiques, 0 différents**.

## 12. Le thème dans le profil — `patch_profil_theme.py`

La boîte de messages s'habille du décor de l'interlocuteur : son fond de menu
derrière la conversation, et les bulles aux couleurs du thème de celui qui lit.
Le serveur gardait déjà ce thème — c'est `/set_theme` qui l'enregistre — mais
`/get_profile` ne le rendait pas. L'application ne pouvait donc connaître que
le sien.

**Une seule ligne**, et rien d'autre : `/get_profile` rend `theme`. Le thème
n'est pas une donnée privée — il s'affiche déjà sur chaque écran de celui qui
l'a choisi, et il ne dit rien de plus que ses goûts. Une application pas encore
corrigée ignore la clé et montre la conversation avec son propre décor, comme
avant.

Le client lit l'axe **menu** du thème, pas le nom entier : un thème composite
`general|pieces|logo|menu|board` donne le fond du menu, et un nom seul (ancien
format) s'applique aux cinq axes. Les deux formes passent — vérifié sur les
deux comptes réels au déploiement.

**Déployé le 11 octobre 2026 à 20 h 46.** `server.py` est passé de
`fc5f961a5f0f…` à `8a3f3e592894…`. Sauvegarde posée avant :
`server.py.avant-profil-theme-20261011-204635`. 4 145 → 4 149 lignes, insertion
à la ligne 1033.

### La preuve

```bash
python3 tests/test_profil_theme.py <port>
```

| | serveur actuel | avec le patch |
|---|---|---|
| son profil, vu par moi, rend `theme` | ECHEC | **OK** |
| et c'est bien LE SIEN | ECHEC | **OK** |
| un thème composite passe entier, sans troncature | ECHEC | **OK** |
| un compte qui n'a rien choisi rend `original`, pas `null` | ECHEC | **OK** |
| mon propre profil le porte aussi | ECHEC | **OK** |
| les huit autres clés sont toujours là | OK | **OK** |
| un joueur inconnu reste introuvable, sans jeton rien | OK | **OK** |
| total | **15/20** | **20/20** |

Non-régression : 32 événements Socket.IO **identiques**, et 81 appels HTTP dont
3 diffèrent par la seule clé ajoutée (les trois `/get_profile`) — en la
neutralisant des deux côtés, **81 identiques, 0 différents**. Les autres bancs
sur le serveur corrigé : **45/45**, **17/17**, **16/16**, **40/40**, inchangés.

**Une réserve sur cette preuve, à la différence des précédentes.** Mon
exemplaire local de `server.py` était un instantané ancien — il avait le direct,
pas les cinq correctifs suivants — et le reconstituer en appliquant les patches
dans l'ordre donne `55e030c7…`, pas le `fc5f961a…` déployé. Les chiffres
ci-dessus viennent donc d'une **réplique** qui porte toutes les routes
concernées, pas du fichier de production à l'octet. Ce qui a été vérifié sur la
production, c'est : le motif présent exactement une fois, le diff à quatre
lignes, la syntaxe, puis en direct deux vrais comptes rendant
`imperial|imperial|imperial|deepgrey|imperial` et `medieval`.

### Au déploiement suivant

Récupère le `server.py` de production avant de préparer un correctif : sans
lui, les tableaux « serveur actuel / avec le patch » portent sur une réplique
et il faut le dire.

## 13. Le plafond d'une boîte — `patch_plafond_messages.py`

Nino : « une fois qu'une boîte contient 200 messages, les plus anciens doivent
être effacés. »

C'est une suppression, pas un affichage : elle se fait donc sur le serveur, là
où les messages vivent. Les effacer côté application ne ferait que les cacher —
ils reviendraient à la lecture suivante — et la base continuerait de grossir
sans fin. **Rien à changer dans l'application** : elle demande la conversation
entière et en reçoit au plus 200.

**La boîte, c'est la PAIRE.** Les deux sens comptent : une boîte contient ce que
chacun a écrit, et c'est ce qu'on lit à l'écran. Le plafond ne s'applique donc
pas par expéditeur.

Le ménage se fait dans la MÊME transaction que l'écriture : le message de trop
chasse un ancien, et il n'existe aucun instant où la boîte dépasse son plafond.

| | |
|---|---|
| `PLAFOND_MESSAGES` | 200 |
| `_plafonner_boite(conn, a, b)` | efface au-delà, les deux sens confondus |
| `/send_message` | l'appelle après l'insertion, avant le `commit` |

`LIMIT -1 OFFSET 200` est la façon SQLite de dire « tout sauf les 200
premiers » : la sous-requête rend exactement les messages de trop.

**Déployé le 13 octobre 2026 à 14 h 11.** `server.py` est passé de
`8a3f3e592894…` à `5641b5197d3b…`, 4 149 → 4 181 lignes. Sauvegardes posées
avant : `server.py.avant-plafond-20261013-141117` et, pour la base,
`lafuga.db.avant-plafond`.

**Le déploiement n'efface rien.** Le plafond n'agit qu'à l'ENVOI d'un message :
au redémarrage, la base comptait toujours ses 409 messages, dont une boîte de
341. Celle-là se coupera à 200 au prochain message qui y sera écrit — 142
disparaîtront alors d'un coup. C'est vérifié sur la production : total et
boîtes inchangés après le redémarrage.

Ce qui est vérifié SUR LA PRODUCTION se limite à cela : le motif unique, le
diff, la syntaxe, le service en bonne santé et la base intacte. Le
comportement du plafond, lui, est prouvé sur la réplique — le banc d'essai
écrit des comptes de sonde et ne tourne jamais en production.

Le compte des non-lus suit : un message effacé n'est plus à lire, et la pastille
retombe d'autant. On ne peut pas réclamer la lecture d'un message qui n'existe
plus.

### La preuve

```bash
python3 tests/test_plafond.py <port>
```

| | serveur actuel | avec le patch |
|---|---|---|
| sous le plafond, rien ne disparaît | OK | **OK** |
| à 200 pile, rien ne disparaît non plus | OK | **OK** |
| le 201ᵉ chasse le premier | ECHEC | **OK** |
| la boîte reste à 200 | ECHEC | **OK** |
| les deux sens partagent le plafond | ECHEC | **OK** |
| l'autre voit la même boîte | OK | **OK** |
| une boîte avec un tiers n'est pas touchée | OK | **OK** |
| total | **11/17** | **17/17** |

Non-régression : 32 événements Socket.IO **identiques**, et 81 appels HTTP dont
3 diffèrent — les trois `/get_profile`, c'est-à-dire la seule clé `theme` de la
correction précédente ; en la neutralisant des deux côtés, **81 identiques, 0
différents**. Le plafond ne change donc rien en dehors de `/send_message`. Les
autres bancs sur le serveur corrigé : **45/45**, **17/17**, **16/16**,
**40/40**, **20/20**, inchangés.

Mêmes réserves qu'à la section 12 : ces chiffres viennent d'une **réplique**,
mon exemplaire local de `server.py` étant un instantané ancien.

**Un piège du protocole, rencontré ici.** Lancer le scénario HTTP deux fois sur
la même paire de bases donne des chiffres différents de la première passe : les
comptes créés au premier tour changent l'état. Une passe par paire neuve, comme
le dit `tests/README.md`, et pas deux.

## 14. Le favori et le blocage dans le profil — `patch_profil_favori.py`

**L'application posait déjà la question, le serveur n'a jamais répondu.** Elle
lit `is_favorite` et `is_blocked` dans `/get_profile` ; ces deux clés n'ont
jamais été envoyées. La touche « Favori » ne devenait donc jamais « Retirer »,
ni « Bloquer » jamais « Débloquer » : les deux lisaient une clé absente,
c'est-à-dire toujours faux.

Nino : « le bouton favori doit devenir retirer quand le joueur est favori […]
il doit y avoir une étoile dans les infos de joueur s'il est favori ».

**Les deux relations sont à SENS UNIQUE**, du point de vue de celui qui
regarde. `is_favorite` : je l'ai mis dans MES favoris — qu'il m'ait ou non dans
les siens ne me regarde pas. `is_blocked` : c'est MOI qui l'ai bloqué ; le
blocage est bilatéral dans ses EFFETS, mais seul celui que j'ai posé se défait
depuis mon écran, et afficher « Débloquer » pour un blocage posé par l'autre
promettrait une action impossible.

Sur MON propre profil, les deux clés sont absentes : se mettre en favori ou se
bloquer soi-même n'a pas de sens, et l'écran ne propose pas ces touches.

**Déployé le 14 octobre 2026 à 10 h 28.** `server.py` est passé de
`5641b5197d3b…` à `327540eb71e2…`, 4 181 → 4 195 lignes. Sauvegarde posée
avant : `server.py.avant-favori-20261014-102805`. Ce correctif ne touche à
aucune donnée : il lit deux tables de plus pour répondre.

Vérifié en direct sur la production, avec un vrai compte : `is_favorite` vrai
pour les quatre favoris de `nino` et pour eux seuls, `is_blocked` faux partout,
et les deux clés absentes de son propre profil. C'est la première fois qu'un
déploiement se vérifie contre une liste connue d'avance — les favoris avaient
été lus dans la base avant d'appliquer le correctif.

### La preuve

```bash
python3 tests/test_favori.py <port>
```

| | serveur actuel | avec le patch |
|---|---|---|
| le profil rend `is_favorite` et `is_blocked` | ECHEC | **OK** |
| ajouté aux favoris, le profil le dit | ECHEC | **OK** |
| retiré, il le dit aussi | ECHEC | **OK** |
| ses favoris à LUI ne sont pas les miens | ECHEC | **OK** |
| le blocage que J'AI posé, et lui seul | ECHEC | **OK** |
| mon propre profil n'a ni l'une ni l'autre | OK | **OK** |
| les neuf autres clés sont toujours là | OK | **OK** |
| total | **13/23** | **23/23** |

Non-régression : 32 événements Socket.IO **identiques**, et 81 appels HTTP dont
2 diffèrent — les deux `/get_profile` d'un AUTRE joueur, par les seules clés
ajoutées ; mon propre profil est inchangé, ce que la comparaison montre bien.
En retirant les deux clés des deux côtés, **81 identiques, 0 différents**. Les
six autres bancs sur le serveur corrigé : **45/45**, **17/17**, **16/16**,
**40/40**, **20/20**, **17/17**, inchangés.

### La leçon

J'avais livré la veille la bascule « Favori / Retirer » en la croyant
vérifiée : mes tests d'application simulaient un serveur qui renvoyait
`is_favorite`. **Je testais contre une fiction.** Le banc d'essai ci-dessus
interroge un vrai serveur, et c'est lui qui a montré que la clé n'existait pas.

Depuis, les tests de l'application couvrent aussi le cas « serveur muet sur la
clé » : ce que fait l'écran quand la réponse manque, au lieu de supposer
qu'elle est là.

## 15. Les fichiers

| Fichier | Rôle |
|---|---|
| `patch_serveur.py` | applique les 23 corrections à ton `server.py` ; s'arrête sans rien écrire si un motif manque |
| `server_original.py` | ton `server.py` tel que tu me l'as envoyé (référence) |
| `server_patched.py` | le résultat, corrections déjà appliquées |
| `serveur.diff` | le diff complet, ligne par ligne |
| `lafuga.service` | unité systemd complète |
| `lafuga-sante.service` + `.timer` | surveillance de `/health` |
| `patch_direct.py` | la correspondance prévient en direct (`maj_directe`) |
| `patch_premove.py` | le pré-coup : le serveur joue la réponse préparée |
| `patch_position.py` | la position personnalisée : `.fug`, trait, couleur tirée à l'acceptation |
| `patch_instrument.py` | l'instrument enregistré dans le compte, comme le thème |
| `patch_regles.py` | deux règles de plus : trois cases libres, un Chevalier au plus par camp |
| `patch_glissee.py` | la vitesse de glissée dans le compte ; zéro est un choix, pas une absence |
| `patch_profil_theme.py` | `/get_profile` rend `theme` : la conversation s'habille du décor de l'interlocuteur |
| `patch_plafond_messages.py` | une boîte garde ses 200 derniers messages ; les plus anciens sont effacés |
| `patch_profil_favori.py` | `/get_profile` rend `is_favorite` et `is_blocked` : la touche sait quoi dire |
| `tests/` | tous les tests de cette page (`tests/README.md`) |
