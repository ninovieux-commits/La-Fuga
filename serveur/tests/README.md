# Tests du serveur

Tout se lance en local, sans toucher à la production. Deux serveurs côte à côte :
**A = l'original**, **B = la version corrigée**, chacun avec sa propre base.

```bash
cd /chemin/vers/serveur
mkdir -p /tmp/A /tmp/B
cp tests/run_seeded.py /tmp/A/ && cp server.py.avant /tmp/A/server.py   # l'original
cp tests/run_seeded.py /tmp/B/ && cp server.py         /tmp/B/server.py   # le corrigé
( cd /tmp/A && PORT=5101 python3 run_seeded.py & )
( cd /tmp/B && PORT=5102 python3 run_seeded.py & )
```

`run_seeded.py` fixe le tirage aléatoire des deux côtés (sinon les couleurs
tirées au hasard diffèrent et la comparaison n'a aucun sens).

## Non-régression

```bash
python3 tests/parite_sio.py 5101 5102   # 32 événements Socket.IO comparés
python3 tests/parite.py     5101 5102   # 81 appels HTTP comparés, cas d'erreur inclus
```

Les deux doivent afficher « IDENTIQUES » / « 0 differents ». À lancer dans cet
ordre (le scénario Socket.IO consomme du hasard avant celui HTTP).

## Coût réel des routes sondées en boucle

```bash
# serveurs instrumentés : comptent les connexions et les requêtes SQLite
( cd /tmp/A && PORT=5111 python3 ../../tests/count_wrap.py 5121 & )
( cd /tmp/B && PORT=5112 python3 ../../tests/count_wrap.py 5122 & )
python3 tests/compte_requetes.py 5111 5121 10   # corr_list, 10 parties
python3 tests/compte_requetes.py 5112 5122 10
python3 tests/compte_convs.py    5111 5121 15   # list_conversations, 15 conversations
python3 tests/compte_convs.py    5112 5122 15
```

## Latence

```bash
python3 tests/bench.py 5101 <pid_de_A> 10
python3 tests/bench.py 5102 <pid_de_B> 10
```

## La fuite de descripteurs (LE test)

Compte les descripteurs qui pointent sur `lafuga.db` pendant l'usage que fait
l'appli (sondage de `corr_list`). C'est ce chiffre qui montait jusqu'à 1024 en
production.

```bash
python3 tests/test_fuite_fd.py 5101 <pid_de_A> 10 6    # original : monte a ~93
python3 tests/test_fuite_fd.py 5102 <pid_de_B> 10 6    # corrige  : reste a 0
```

## Robustesse

```bash
python3 tests/test_robustesse.py 5102     # 28 événements malformés
```

## Ménage (avec des délais raccourcis)

```bash
mkdir -p /tmp/M && cp server.py /tmp/M/
( cd /tmp/M && PORT=5131 LAFUGA_JANITOR_PERIOD=3 LAFUGA_DEFI_TTL=2 \
    LAFUGA_GAME_IDLE_TTL=5 python3 server.py & )
python3 tests/test_menage.py         5131 /tmp/M/lafuga.db
python3 tests/test_partie_vivante.py 5131   # le test le plus important
```

## Charge

```bash
python3 tests/stress.py 5102 <pid_de_B> 30 420   # 30 clients, 7 minutes
python3 tests/churn4.py  5102 <pid_de_B> 1500    # 1500 reconnexions d'affilée
```

## Variables d'environnement du serveur corrigé

| Variable | Défaut | Rôle |
|---|---|---|
| `PORT` | 5000 | port d'écoute |
| `LAFUGA_LOG` | `lafuga.log` à côté de server.py | fichier journal |
| `LAFUGA_LOG_MAX` | 5242880 | taille max d'un fichier journal |
| `LAFUGA_LOG_BACKUPS` | 3 | nombre de fichiers gardés |
| `LAFUGA_MAX_CONCURRENT` | 400 | connexions traitées en parallèle |
| `LAFUGA_JANITOR_PERIOD` | 300 | période du ménage (s) |
| `LAFUGA_DEFI_TTL` | 300 | expiration d'un défi direct non résolu (s) |
| `LAFUGA_GAME_IDLE_TTL` | 43200 | oubli d'une partie sans aucun événement (s) |
| `LAFUGA_FCM_POOL` | 20 | envois de notifications en parallèle |
| `LAFUGA_DB_PARTAGE` | 1 | 1 = une connexion partagée par requête ; 0 = une vraie connexion par appel (comme avant), fermée à coup sûr en fin de requête |
