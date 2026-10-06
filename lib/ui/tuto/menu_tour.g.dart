/// Visite guidée du menu — produit à l'origine par `tool/gen_menu_tour.py`
/// depuis `MenuTourOverlay._build_stops` (main.py).
///
/// **Deux étapes ont DIVERGÉ de Kivy, à la main et volontairement** : celles
/// de la correspondance et du mode Random. La correspondance ne dépend plus de
/// l'interrupteur du menu — elle choisit sa position de départ au moment du
/// défi, standard, Random ou composée — et l'ancien texte serait devenu faux.
///
/// Relancer le générateur les écraserait. Il n'y a rien à en régénérer : le
/// portage Kivy n'est plus la référence sur ce point, ce fichier l'est.
library;

/// Les étapes, au format JSON du client Kivy.
const String kMenuTourJson = r'''
[
 {
  "targets": [
   "cad"
  ],
  "scroll": "cad",
  "text": "Avant une partie, choisis ta CADENCE : le temps de réflexion accordé à chaque joueur, en minutes."
 },
 {
  "targets": [
   "local",
   "online"
  ],
  "scroll": "local",
  "text": "Puis lance : « Jouer en local » (à deux sur le même appareil) ou « Jouer en ligne ». En ligne, le matchmaking te trouve un adversaire de ton niveau ; c'est le SEUL mode qui fait bouger ton MÉLO, ton classement (~1500 au départ), qui monte quand tu gagnes et baisse quand tu perds."
 },
 {
  "targets": [
   "ai"
  ],
  "scroll": "ai",
  "text": "« deep grey » est l'intelligence artificielle du jeu : affronte-la pour t'entraîner quand tu veux."
 },
 {
  "targets": [
   "search",
   "fav"
  ],
  "scroll": "search",
  "text": "Cherche un joueur par son nom pour le défier directement ; l'étoile gère tes favoris."
 },
 {
  "targets": [
   "corr"
  ],
  "scroll": "corr",
  "text": "Fais glisser l'écran vers le BAS pour la CORRESPONDANCE : des parties sans limite de temps, contre des joueurs enregistrés. Pour en lancer une, clique sur un plateau vide, choisis ton adversaire parmi tes favoris, puis la position de départ : standard, Random, ou une position que tu composes toi-même."
 },
 {
  "targets": [
   "compte"
  ],
  "scroll": "obj",
  "text": "« Compte » : crée ton compte ici. Il est OBLIGATOIRE pour jouer en ligne et en correspondance."
 },
 {
  "targets": [
   "random"
  ],
  "scroll": "obj",
  "text": "« Random » active la variante Random Fuga pour tes parties locales et en ligne : la position de départ est tirée au hasard parmi 1750 positions x 2 types de symétrie, soit 3500 débuts possibles. Il se réinitialise à chaque lancement. En correspondance, la position se choisit au moment du défi."
 },
 {
  "targets": [
   "plus"
  ],
  "scroll": "plus",
  "text": "« Plus » donne accès à ce tuto, à l'historique de tes parties, à l'analyse, aux réglages, et à SOUTENIR LES DÉVELOPPEURS (un petit don pour aider le jeu)."
 },
 {
  "targets": [],
  "scroll": "obj",
  "text": "Et voilà, tu sais tout ! Le reste (thèmes, réglages, historique, analyse), tu le découvriras toi-même. Bonne fugue !"
 }
]
''';
