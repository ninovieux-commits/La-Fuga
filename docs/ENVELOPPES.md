# Les enveloppes

Une image qui passe d'un joueur à l'autre **sans rester nulle part**. Ce
n'est pas un hébergeur d'images, c'est un sas : l'image y entre, elle en sort
ou elle meurt en 48 heures.

Tout ce qui suit vient de Nino, et ses mots sont cités là où ils décident.

---

## Pourquoi ça ne coûte rien

> « Je voudrais qu'on puisse envoyer des images mais je ne veux pas que ça me
> coûte cher sur le serveur. »

Une photo 720p compressée pèse 150 à 300 Ko. Le plan borne lui-même le
stockage : **deux enveloppes en attente par expéditeur et par paire**, donc
quatre par paire de correspondants, soit 1,2 Mo. Cinquante paires actives en
même temps tiennent dans 60 Mo, et ce n'est pas cumulatif — au bout de 48 h,
tout est rendu. Mesuré sur le VPS : 67 Go libres, 114 Mo occupés.

Quatre règles tiennent ce prix :

1. **le redimensionnement se fait sur le téléphone**, jamais sur le serveur,
   qui ne décode aucune image — il reçoit des octets, les pose dans un
   fichier, les rend ;
2. **les images vont sur le disque, pas dans SQLite** : la base est le
   fichier que tout le reste du serveur ouvre et copie ;
3. **un plafond dur à l'envoi, refusé par le serveur** (900 Ko) : la limite
   des 720p est une politesse du client, et un client bricolé ne la respecte
   pas ;
4. **le ménage des 48 h est fait par le serveur**, pas seulement par l'appli :
   un destinataire qui ne revient jamais ne doit rien laisser derrière lui.

## Ce que « disparaît » veut dire

> « L'idée est que l'image ne reste stockée ni dans le serveur ni dans l'app,
> mais que la personne puisse la stocker dans son smartphone. Comme ça on peut
> faire tourner autant d'images qu'on veut, le tout en restant légers. »

Le popup dit donc « elle disparaît de la conversation », et non « à jamais » :
le destinataire garde le droit de télécharger ce qu'il a reçu.

---

## Le serveur

`serveur/patch_enveloppes.py`, inséré en un seul point, juste avant
`_send_push`. Quatre routes, aucune route existante touchée.

| route | ce qu'elle fait |
|---|---|
| `/env_envoyer` | dépose une enveloppe (image en base64) chez un correspondant |
| `/env_liste` | les enveloppes en attente avec ce correspondant, **dans les deux sens** |
| `/env_ouvrir` | rend l'image ; **effacée si c'est le destinataire qui ouvre** |
| `/env_supprimer` | jette une enveloppe sans l'ouvrir ; les deux côtés en ont le droit |

**Ouvrir n'est pas vérifier.** L'expéditeur peut rouvrir la sienne sans la
consommer :

> « On peut voir les enveloppes en attente chez le correspondant, les ouvrir
> pour vérifier et les supprimer avant qu'il ne les ai ouvertes. »

Une table `enveloppes` et un dossier `enveloppes/` à côté de `server.py`,
créés au démarrage s'ils manquent. Un greenlet de ménage toutes les dix
minutes, bâti comme le janitor existant : il ne garde aucune connexion entre
deux passages.

---

## Le jeton, dans la conversation

- **Le dessin nu**, sans touche sous lui : « il ne doit pas être sur un bouton
  pour les reçus et envoyés, mais doit être sur un bouton pour les envoyer. »
- **Le chrono au pied**, au format dicté : `48h00` → `47h59`. La minute
  entamée ne compte pas — « je ne veux pas que ça arrondisse à la minute ».
- **La couleur est celle de la bulle du même côté** : la mienne en `clair`,
  la sienne en `fonce`, « exactement comme les bulles de conversation en
  fait ».
- **Seules celles qu'on peut ouvrir oscillent.** Trois degrés et demi, un
  aller-retour toutes les 1,4 s. La sienne se tient droite : on ne peut que
  la vérifier ou la reprendre, elle n'appelle personne.

## Les gestes

**Envoyer.** La touche enveloppe-plus, en haut à droite de la conversation.
Elle demande d'abord **[appareil photo]** ou **[photos]**, avec les icônes
habituelles. La photo choisie, elle demande **[envoyer]** ou **[modifier]**.

**L'éditeur** : dessin, texte, emojis — et un bouton **[tampon]**.

> « Un bouton tampon qui crée un texte automatique comprenant la date et les
> noms des deux joueurs. On doit pouvoir déplacer et changer la taille de ce
> tampon. Il doit y avoir un rond blanc à côté d'un des noms et un rond noir à
> côté de l'autre, avec un petit bouton pour inverser ces deux ronds. »

Les deux ronds disent qui tient les Blancs et qui tient les Noirs ; le petit
bouton les échange.

**Ouvrir.** Un popup :

> **Ouvrir l'enveloppe pour visionner l'image ?**
> Une fois ouverte, elle disparaît de la conversation.
> **[Ouvrir]  [Annuler]  [Supprimer]**

L'image ouverte offre **[Télécharger]** et **[Modifier et renvoyer]** — on
peut retoucher ce qu'on a reçu avant de le renvoyer. **Elle n'est retirée de
la conversation qu'à la fermeture de la visionneuse**, pas au moment où on
l'ouvre.

**En partie**, l'image ne s'affiche pas comme un message rapide : seule
l'enveloppe passe, comme un émoticône.
