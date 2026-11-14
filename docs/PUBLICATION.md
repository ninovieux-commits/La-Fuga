# Publier La Fuga sur le Play Store

Ce qui suit est l'état réel du chantier : ce qui est prêt, ce qui manque, et
qui fait quoi. Il se met à jour au fur et à mesure.

## Ce qui est prêt

| | |
|---|---|
| Nom affiché | « La Fuga » (`android:label`) |
| Identifiant | `org.lafuga.lafuga` — celui de la version Kivy, donc une mise à jour et non une nouvelle application |
| Icône | la sienne, 192 px, déjà en place dans `mipmap-*` |
| Serveur | `https://fuga-online.fr`, déjà en HTTPS : rien à faire du côté du trafic en clair |
| Permissions | internet, réseau, notifications, et l'écriture en galerie plafonnée à Android 9 — aucune permission à justifier devant Google |
| Signature | `android/app/build.gradle.kts` signe avec la clé de `android/key.properties` quand ce fichier existe, et avec la clé de debug sinon |
| Bundle | l'atelier « Préparer la publication (AAB signé) », à lancer à la main |

## La clé de signature

Elle appartient à Nino, et à lui seul : le dépôt est public, et une clé
publiée ne se remplace pas — perdue, l'application ne peut plus jamais être
mise à jour.

    bash outils/cle_de_signature.sh

Le script demande un mot de passe sans l'afficher, fabrique la clé, et
imprime le pavé base64 à coller dans les secrets GitHub :

| Secret | Contenu |
|---|---|
| `CLE_SIGNATURE_BASE64` | le pavé imprimé par le script |
| `CLE_SIGNATURE_MDP` | le mot de passe, tapé directement dans GitHub |
| `CLE_SIGNATURE_ALIAS` | `upload` |

Le mot de passe ne passe ni par le dépôt ni par une conversation.

**Signature par Play.** Google garde la clé qui signe vraiment l'application
et ne nous laisse qu'une clé de dépôt. C'est obligatoire pour une nouvelle
application, et c'est une bonne nouvelle : une clé de dépôt perdue se
remplace, Google la réinitialise.

## Ce qui manque encore

### 1. La suppression de compte — obligatoire

Google l'exige dès qu'une application permet de créer un compte, et il en
faut **deux** : un chemin dans l'application, et une page web accessible sans
installer quoi que ce soit. La Fuga n'a ni l'un ni l'autre, et le serveur n'a
aucune route pour cela. À faire :

- une route serveur qui efface le compte et ce qui s'y rattache (parties,
  messages, enveloppes, jetons, favoris, blocages) ;
- une touche dans l'écran Compte, avec une confirmation qui ne se touche pas
  par accident ;
- une page web qui fait la même demande.

### 2. La politique de confidentialité — obligatoire

Une page web publique, à déclarer dans la fiche. Elle doit dire ce qui est
collecté — pseudo, mot de passe haché, parties, messages, photos envoyées en
enveloppe, jeton de notification — et combien de temps c'est gardé.

### 3. La fiche

Deux textes (80 et 4000 signes), une icône 512×512, une bannière 1024×500, et
au moins deux captures par format d'écran. Les captures se fabriquent avec les
outils d'aperçu du dépôt : ce sont de vraies images de l'application.

### 4. Le questionnaire « Sécurité des données »

À remplir dans la console. Il doit dire la vérité sur les messages, les
photos et le jeton de notification.

## Le délai qu'on ne rattrape pas

Un compte développeur **personnel** créé après novembre 2023 doit faire
tourner un **test fermé de 14 jours avec au moins 12 testeurs** avant de
pouvoir demander la publication. L'horloge ne démarre qu'une fois les
testeurs inscrits : c'est la première chose à lancer, avant tout le reste.

Un compte **organisation** (entreprise, association) en est dispensé, mais
demande un numéro D-U-N-S et sa propre vérification.
