/// Étapes du tuto — **fichier généré**, ne pas modifier à la main.
///
/// Produit par `tool/gen_tuto_steps.py` depuis `_build_tuto_steps` (main.py).
library;

/// Les étapes, au format JSON du client Kivy.
const String kTutoStepsJson = r'''
[
 {
  "title": "Le but du jeu",
  "pieces": [
   [
    "do",
    1,
    "Soldat",
    "Blanc"
   ],
   [
    "do",
    2,
    "Garde",
    "Blanc"
   ],
   [
    "do",
    8,
    "Soldat",
    "Noir"
   ],
   [
    "do",
    7,
    "Garde",
    "Noir"
   ],
   [
    "ré",
    1,
    "Garde",
    "Blanc"
   ],
   [
    "ré",
    2,
    "Nurse",
    "Blanc"
   ],
   [
    "ré",
    8,
    "Garde",
    "Noir"
   ],
   [
    "ré",
    7,
    "Nurse",
    "Noir"
   ],
   [
    "mi",
    1,
    "Soldat",
    "Blanc"
   ],
   [
    "mi",
    2,
    "Nurse",
    "Blanc"
   ],
   [
    "mi",
    8,
    "Soldat",
    "Noir"
   ],
   [
    "mi",
    7,
    "Nurse",
    "Noir"
   ],
   [
    "fa",
    1,
    "Héritier",
    "Blanc"
   ],
   [
    "fa",
    2,
    "Nurse",
    "Blanc"
   ],
   [
    "fa",
    8,
    "Héritier",
    "Noir"
   ],
   [
    "fa",
    7,
    "Nurse",
    "Noir"
   ],
   [
    "sol",
    1,
    "Garde",
    "Blanc"
   ],
   [
    "sol",
    2,
    "Nurse",
    "Blanc"
   ],
   [
    "sol",
    8,
    "Garde",
    "Noir"
   ],
   [
    "sol",
    7,
    "Nurse",
    "Noir"
   ],
   [
    "la",
    1,
    "Soldat",
    "Blanc"
   ],
   [
    "la",
    2,
    "Nurse",
    "Blanc"
   ],
   [
    "la",
    8,
    "Soldat",
    "Noir"
   ],
   [
    "la",
    7,
    "Nurse",
    "Noir"
   ],
   [
    "si",
    1,
    "Garde",
    "Blanc"
   ],
   [
    "si",
    2,
    "Soldat",
    "Blanc"
   ],
   [
    "si",
    8,
    "Garde",
    "Noir"
   ],
   [
    "si",
    7,
    "Soldat",
    "Noir"
   ],
   [
    "fa",
    3,
    "Chevalier",
    "Blanc"
   ],
   [
    "fa",
    6,
    "Chevalier",
    "Noir"
   ]
  ],
  "framed": [
   [
    "fa",
    1
   ]
  ],
  "arrows": [
   [
    [
     "fa",
     1
    ],
    [
     "fa",
     "out"
    ]
   ]
  ],
  "text": "Bienvenue. À La Fuga, le but du jeu est d'emmener l'Héritier (pièce encadrée) jusqu'à sa zone de ralliement, à l'autre bout du plateau. Bien sûr, vous devrez aussi empêcher votre adversaire d'y parvenir. Il peut y parvenir par lui-même ou en étant poussé."
 },
 {
  "title": "Le déplacement",
  "pieces": [
   [
    "fa",
    4,
    "Héritier",
    "Blanc"
   ]
  ],
  "interactive": true,
  "move": [
   "fa",
   4
  ],
  "dests": [
   [
    "mi",
    3
   ],
   [
    "fa",
    3
   ],
   [
    "sol",
    3
   ],
   [
    "mi",
    4
   ],
   [
    "sol",
    4
   ],
   [
    "mi",
    5
   ],
   [
    "fa",
    5
   ],
   [
    "sol",
    5
   ]
  ],
  "arrows": [
   [
    [
     "fa",
     4
    ],
    [
     "mi",
     3
    ]
   ],
   [
    [
     "fa",
     4
    ],
    [
     "fa",
     3
    ]
   ],
   [
    [
     "fa",
     4
    ],
    [
     "sol",
     3
    ]
   ],
   [
    [
     "fa",
     4
    ],
    [
     "mi",
     4
    ]
   ],
   [
    [
     "fa",
     4
    ],
    [
     "sol",
     4
    ]
   ],
   [
    [
     "fa",
     4
    ],
    [
     "mi",
     5
    ]
   ],
   [
    [
     "fa",
     4
    ],
    [
     "fa",
     5
    ]
   ],
   [
    [
     "fa",
     4
    ],
    [
     "sol",
     5
    ]
   ]
  ],
  "text_select": "Clique sur l'Héritier pour le sélectionner.",
  "text_move": "Toutes les pièces peuvent se déplacer d'une case dans n'importe quelle direction. Déplace l'Héritier sur une case voisine.",
  "text_validate": "Pour valider ton coup, clique à nouveau sur la pièce, sur sa nouvelle case.",
  "text_done": "Parfait ! Clique sur « Suivant » pour continuer."
 },
 {
  "title": "La règle de contact",
  "pieces": [
   [
    "mi",
    6,
    "Nurse",
    "Blanc"
   ],
   [
    "mi",
    7,
    "Nurse",
    "Noir"
   ],
   [
    "do",
    2,
    "Soldat",
    "Blanc"
   ],
   [
    "ré",
    2,
    "Garde",
    "Noir"
   ],
   [
    "sol",
    4,
    "Nurse",
    "Blanc"
   ],
   [
    "sol",
    5,
    "Soldat",
    "Blanc"
   ]
  ],
  "framed_ok": [
   [
    "mi",
    6
   ],
   [
    "mi",
    7
   ],
   [
    "do",
    2
   ],
   [
    "ré",
    2
   ]
  ],
  "framed": [
   [
    "sol",
    4
   ],
   [
    "sol",
    5
   ]
  ],
  "text": "Pour se déplacer, une pièce RONDE doit toucher une autre ronde (alliée ou adverse), et une pièce CARRÉE doit toucher une autre carrée. En vert : les pièces qui peuvent bouger. En rouge : les pièces bloquées (aucune pièce de leur forme à côté)."
 },
 {
  "title": "Le multisaut",
  "pieces": [
   [
    "do",
    1,
    "Nurse",
    "Blanc"
   ],
   [
    "ré",
    2,
    "Nurse",
    "Blanc"
   ],
   [
    "fa",
    3,
    "Nurse",
    "Noir"
   ],
   [
    "fa",
    4,
    "Nurse",
    "Blanc"
   ],
   [
    "mi",
    6,
    "Nurse",
    "Noir"
   ]
  ],
  "interactive": true,
  "move": [
   "do",
   1
  ],
  "sequence": [
   {
    "dest": [
     "mi",
     3
    ],
    "text": "Saut en DIAGONALE par-dessus ré2, jusqu'en mi3."
   },
   {
    "dest": [
     "sol",
     3
    ],
    "text": "Saut tout DROIT par-dessus fa3, jusqu'en sol3."
   },
   {
    "dest": [
     "mi",
     5
    ],
    "text": "De nouveau en DIAGONALE par-dessus fa4, jusqu'en mi5."
   },
   {
    "dest": [
     "mi",
     7
    ],
    "text": "Et tout DROIT par-dessus mi6, jusqu'en mi7."
   }
  ],
  "text_select": "Une pièce ronde saute par-dessus une autre ronde (alliée ou adverse), en ligne DROITE ou en DIAGONALE, et peut enchaîner les sauts ! Clique sur la Nurse.",
  "text_validate": "Clique à nouveau sur la Nurse pour valider ton multisaut.",
  "text_done": "Bravo ! Sauts droits et diagonaux : tu maîtrises le multisaut."
 },
 {
  "title": "Fuguer en sautant",
  "pieces": [
   [
    "mi",
    3,
    "Héritier",
    "Blanc"
   ],
   [
    "fa",
    4,
    "Nurse",
    "Noir"
   ],
   [
    "sol",
    6,
    "Nurse",
    "Blanc"
   ],
   [
    "fa",
    8,
    "Nurse",
    "Noir"
   ]
  ],
  "interactive": true,
  "move": [
   "mi",
   3
  ],
  "sequence": [
   {
    "dest": [
     "sol",
     5
    ],
    "text": "Saut en DIAGONALE par-dessus fa4, jusqu'en sol5."
   },
   {
    "dest": [
     "sol",
     7
    ],
    "text": "Saut tout DROIT par-dessus sol6, jusqu'en sol7."
   },
   {
    "dest": [
     "mi",
     "out"
    ],
    "text": "Dernier saut, en DIAGONALE par-dessus fa8 : l'Héritier SORT du plateau et rejoint son ralliement !"
   }
  ],
  "text_select": "L'Héritier peut lui aussi enchaîner les sauts, droits ou diagonaux, et même FUGUER en sautant. Clique sur l'Héritier.",
  "text_done": "Fugue réussie ! L'Héritier a atteint son ralliement : VICTOIRE !"
 },
 {
  "title": "Les unités",
  "pieces": [
   [
    "do",
    2,
    "Soldat",
    "Blanc"
   ],
   [
    "ré",
    2,
    "Garde",
    "Blanc"
   ],
   [
    "mi",
    2,
    "Soldat",
    "Blanc"
   ],
   [
    "fa",
    3,
    "Garde",
    "Blanc"
   ],
   [
    "sol",
    6,
    "Garde",
    "Blanc"
   ],
   [
    "la",
    6,
    "Soldat",
    "Blanc"
   ]
  ],
  "framed_ok": [
   [
    "do",
    2
   ],
   [
    "ré",
    2
   ],
   [
    "mi",
    2
   ],
   [
    "fa",
    3
   ]
  ],
  "framed_blue": [
   [
    "sol",
    6
   ],
   [
    "la",
    6
   ]
  ],
  "links": [
   {
    "pairs": [
     [
      [
       "do",
       2
      ],
      [
       "ré",
       2
      ]
     ],
     [
      [
       "ré",
       2
      ],
      [
       "mi",
       2
      ]
     ],
     [
      [
       "mi",
       2
      ],
      [
       "fa",
       3
      ]
     ]
    ],
    "color": [
     0.18,
     0.72,
     0.3
    ]
   },
   {
    "pairs": [
     [
      [
       "sol",
       6
      ],
      [
       "la",
       6
      ]
     ]
    ],
    "color": [
     0.92,
     0.55,
     0.12
    ]
   }
  ],
  "interactive": true,
  "maneuver": true,
  "leader": [
   "do",
   2
  ],
  "group_add": [
   [
    "ré",
    2
   ],
   [
    "fa",
    3
   ]
  ],
  "move_to": [
   "do",
   3
  ],
  "done_frame": [
   "fa",
   4
  ],
  "text_select": "Les pièces carrées d'un même camp qui se touchent, même en diagonale, forment une UNITÉ. Plusieurs pièces de la même unité peuvent se déplacer en même temps, dans la même direction. Déplaçons plusieurs pièces de l'unité en vert ; clique sur do2, qui sera la meneuse.",
  "text_group": "Ajoute ré2 puis fa3 à la sélection (on laisse mi2 de côté : tu n'es pas obligé de tout prendre).",
  "text_move": "L'unité se déplace selon la meneuse. Clique en do3 pour monter les pièces choisies d'une case.",
  "text_validate": "Clique sur la meneuse pour valider ton coup.",
  "text_done": "En montant, la pièce en fa s'est retrouvée seule (encadrée) ! Une manœuvre peut donc IMMOBILISER une pièce : fa n'a plus aucune carrée à côté."
 },
 {
  "title": "La poussée : le Garde",
  "pieces": [
   [
    "mi",
    3,
    "Garde",
    "Blanc"
   ],
   [
    "mi",
    2,
    "Soldat",
    "Blanc"
   ],
   [
    "sol",
    4,
    "Soldat",
    "Noir"
   ],
   [
    "la",
    4,
    "Garde",
    "Noir"
   ],
   [
    "si",
    4,
    "Soldat",
    "Noir"
   ]
  ],
  "interactive": true,
  "push": true,
  "leader": [
   "mi",
   3
  ],
  "move_to": [
   "fa",
   4
  ],
  "push_to": [
   "sol",
   4
  ],
  "text_select": "Le GARDE (croix ×) se déplace en diagonale et POUSSE en ligne droite. Clique sur le Garde.",
  "text_move": "Déplace le Garde en diagonale, jusqu'en fa4.",
  "text_push": "Maintenant POUSSE : clique en sol4. Toute la ligne est repoussée d'une case, et la pièce du bord tombe du plateau (éliminée) !",
  "text_validate": "Clique sur le Garde pour valider ton coup.",
  "text_done": "Bravo ! Le Garde a poussé la ligne et éliminé une pièce. C'est le SEUL moyen d'éliminer une pièce : la pousser hors du plateau. Et tu peux même éliminer tes PROPRES pièces !"
 },
 {
  "title": "La poussée : le Soldat",
  "pieces": [
   [
    "do",
    3,
    "Soldat",
    "Blanc"
   ],
   [
    "do",
    2,
    "Soldat",
    "Blanc"
   ],
   [
    "ré",
    5,
    "Nurse",
    "Noir"
   ]
  ],
  "interactive": true,
  "push": true,
  "leader": [
   "do",
   3
  ],
  "move_to": [
   "do",
   4
  ],
  "push_to": [
   "ré",
   5
  ],
  "done_frame": [
   "do",
   4
  ],
  "text_select": "Le SOLDAT (croix +) se déplace en ligne droite et POUSSE en diagonale. Clique sur le Soldat.",
  "text_move": "Déplace le Soldat tout droit, en do4.",
  "text_push": "POUSSE en diagonale : clique en ré5 pour repousser la pièce.",
  "text_validate": "Clique sur le Soldat pour valider ton coup.",
  "text_done": "Attention : en se déplaçant, le Soldat s'est éloigné de son allié et n'a plus de carrée à côté, il est maintenant BLOQUÉ (encadré) jusqu'à ce qu'une carrée le rejoigne."
 },
 {
  "title": "Pousser plusieurs directions",
  "pieces": [
   [
    "mi",
    3,
    "Garde",
    "Blanc"
   ],
   [
    "mi",
    2,
    "Soldat",
    "Blanc"
   ],
   [
    "fa",
    5,
    "Nurse",
    "Noir"
   ],
   [
    "sol",
    4,
    "Soldat",
    "Noir"
   ],
   [
    "fa",
    3,
    "Soldat",
    "Noir"
   ]
  ],
  "interactive": true,
  "push": true,
  "leader": [
   "mi",
   3
  ],
  "move_to": [
   "fa",
   4
  ],
  "pushes": [
   {
    "push_to": [
     "fa",
     5
    ],
    "text": "Pousse une 1re direction : clique en fa5 (vers le haut)."
   },
   {
    "push_to": [
     "sol",
     4
    ],
    "text": "Tu peux pousser une AUTRE direction ! Clique en sol4 (vers la droite)."
   }
  ],
  "text_select": "Après s'être déplacée, une carrée peut pousser dans PLUSIEURS directions, autant que tu veux. Clique sur le Garde.",
  "text_move": "Déplace le Garde en diagonale, en fa4.",
  "text_validate": "Clique sur le Garde pour valider ton coup.",
  "text_done": "Bravo ! Tu as poussé en haut et à droite. Remarque : fa3 (en bas) pouvait aussi être poussée, mais on l'a laissée, c'est toi qui choisis quelles directions pousser."
 },
 {
  "title": "Fuguer en poussant",
  "pieces": [
   [
    "mi",
    6,
    "Garde",
    "Blanc"
   ],
   [
    "mi",
    5,
    "Soldat",
    "Blanc"
   ],
   [
    "fa",
    8,
    "Héritier",
    "Blanc"
   ]
  ],
  "interactive": true,
  "push": true,
  "leader": [
   "mi",
   6
  ],
  "move_to": [
   "fa",
   7
  ],
  "push_to": [
   "fa",
   8
  ],
  "win": true,
  "text_select": "On peut aussi POUSSER son propre Héritier ! Clique sur le Garde.",
  "text_move": "Déplace le Garde en diagonale, en fa7 (sous l'Héritier).",
  "text_push": "POUSSE vers le haut : clique en fa8. L'Héritier est poussé dans son ralliement !",
  "text_done": "Fugue ! Tu as poussé ton Héritier dans son ralliement : VICTOIRE !"
 },
 {
  "title": "Mater en poussant",
  "pieces": [
   [
    "sol",
    6,
    "Garde",
    "Blanc"
   ],
   [
    "sol",
    5,
    "Soldat",
    "Blanc"
   ],
   [
    "la",
    8,
    "Héritier",
    "Noir"
   ]
  ],
  "interactive": true,
  "push": true,
  "leader": [
   "sol",
   6
  ],
  "move_to": [
   "la",
   7
  ],
  "push_to": [
   "la",
   8
  ],
  "win": true,
  "text_select": "Enfin, pousser l'Héritier ADVERSE hors du plateau le met MAT. Clique sur le Garde.",
  "text_move": "Déplace le Garde en diagonale, en la7 (sous l'Héritier adverse).",
  "text_push": "POUSSE vers le haut : clique en la8. L'Héritier adverse est éjecté du plateau !",
  "text_done": "Mat ! Tu as poussé l'Héritier adverse hors du plateau : VICTOIRE !"
 },
 {
  "title": "Le Chevalier",
  "pieces": [
   [
    "fa",
    3,
    "Chevalier",
    "Blanc"
   ],
   [
    "fa",
    6,
    "Chevalier",
    "Noir"
   ]
  ],
  "framed_blue": [
   [
    "fa",
    3
   ],
   [
    "fa",
    6
   ]
  ],
  "text": "Le CHEVALIER (l'hexagone) est une pièce à part, avec deux pouvoirs. INÉBRANLABLE : il ne peut jamais être poussé, une poussée s'arrête net sur lui. INDÉPENDANT : il peut se déplacer même s'il ne touche aucune pièce de sa forme (il n'a pas besoin de voisine pour bouger)."
 },
 {
  "title": "Le Chevalier bloque",
  "pieces": [
   [
    "mi",
    2,
    "Garde",
    "Noir"
   ],
   [
    "fa",
    4,
    "Chevalier",
    "Blanc"
   ],
   [
    "fa",
    5,
    "Héritier",
    "Blanc"
   ],
   [
    "fa",
    6,
    "Nurse",
    "Blanc"
   ]
  ],
  "framed_blue": [
   [
    "fa",
    4
   ]
  ],
  "arrows": [
   [
    [
     "mi",
     2
    ],
    [
     "fa",
     3
    ]
   ]
  ],
  "text": "Puisqu'il ne peut être poussé, le Chevalier sert de MUR : il bloque les poussées. Ici, même si le Garde adverse s'avance en fa3 pour pousser vers le haut, le Chevalier (fa4) arrête tout : l'Héritier (fa5) est protégé."
 },
 {
  "title": "Fins de partie",
  "banner": "MOTIFS DE\nFIN DE PARTIE",
  "pieces": [],
  "text": "Voici toutes les façons dont une partie peut se terminer, et combien de points chacune rapporte."
 },
 {
  "title": "Fin : la fugue",
  "pieces": [
   [
    "ré",
    8,
    "Héritier",
    "Blanc"
   ],
   [
    "mi",
    8,
    "Nurse",
    "Blanc"
   ],
   [
    "sol",
    5,
    "Chevalier",
    "Noir"
   ],
   [
    "la",
    6,
    "Chevalier",
    "Blanc"
   ],
   [
    "la",
    4,
    "Nurse",
    "Noir"
   ],
   [
    "do",
    3,
    "Garde",
    "Blanc"
   ],
   [
    "fa",
    2,
    "Héritier",
    "Noir"
   ]
  ],
  "arrows": [
   [
    [
     "ré",
     8
    ],
    [
     "mi",
     "out"
    ]
   ]
  ],
  "text": "FUGUE (+2 points). Ton Héritier atteint son ralliement (la flèche) : tu gagnes la partie ! C'est la victoire la plus valorisée. Une Nurse à son contact lui permet de bouger."
 },
 {
  "title": "Fin : la double fugue",
  "pieces": [
   [
    "fa",
    8,
    "Héritier",
    "Blanc"
   ],
   [
    "mi",
    8,
    "Nurse",
    "Blanc"
   ],
   [
    "fa",
    1,
    "Héritier",
    "Noir"
   ],
   [
    "mi",
    1,
    "Nurse",
    "Noir"
   ],
   [
    "sol",
    4,
    "Chevalier",
    "Blanc"
   ],
   [
    "do",
    4,
    "Chevalier",
    "Noir"
   ]
  ],
  "arrows": [
   [
    [
     "fa",
     8
    ],
    [
     "fa",
     "out"
    ]
   ],
   [
    [
     "fa",
     1
    ],
    [
     "fa",
     0
    ]
   ]
  ],
  "text": "DOUBLE FUGUE (0 point). Quand les Blancs fuguent, les Noirs ont droit à un DERNIER coup pour égaliser. Si les deux Héritiers rejoignent leur ralliement, la partie est nulle. Ici, c'est aux Blancs de jouer, et les deux Héritiers peuvent fuguer (flèches)."
 },
 {
  "title": "Fin : le mat",
  "pieces": [
   [
    "si",
    6,
    "Garde",
    "Blanc"
   ],
   [
    "si",
    5,
    "Soldat",
    "Blanc"
   ],
   [
    "la",
    8,
    "Héritier",
    "Noir"
   ],
   [
    "mi",
    4,
    "Chevalier",
    "Blanc"
   ],
   [
    "do",
    7,
    "Chevalier",
    "Noir"
   ],
   [
    "do",
    5,
    "Nurse",
    "Noir"
   ],
   [
    "fa",
    6,
    "Nurse",
    "Blanc"
   ]
  ],
  "arrows": [
   [
    [
     "si",
     6
    ],
    [
     "la",
     7
    ]
   ],
   [
    [
     "la",
     8
    ],
    [
     "la",
     "out"
    ]
   ]
  ],
  "text": "MAT (+1 point). Le Garde (si6) se déplace en la7, puis pousse l'Héritier adverse (la8) hors du plateau : il est éjecté, tu gagnes."
 },
 {
  "title": "Fin : la guillotine",
  "pieces": [
   [
    "la",
    8,
    "Héritier",
    "Blanc"
   ],
   [
    "si",
    6,
    "Garde",
    "Blanc"
   ],
   [
    "si",
    5,
    "Soldat",
    "Blanc"
   ],
   [
    "fa",
    1,
    "Héritier",
    "Noir"
   ],
   [
    "sol",
    1,
    "Nurse",
    "Noir"
   ],
   [
    "mi",
    4,
    "Chevalier",
    "Blanc"
   ],
   [
    "do",
    5,
    "Chevalier",
    "Noir"
   ]
  ],
  "arrows": [
   [
    [
     "si",
     6
    ],
    [
     "la",
     7
    ]
   ],
   [
    [
     "la",
     8
    ],
    [
     "la",
     "out"
    ]
   ],
   [
    [
     "fa",
     1
    ],
    [
     "fa",
     0
    ]
   ]
  ],
  "text": "GUILLOTINE. L'adversaire va fuguer (son Héritier fa1, mobile grâce à sa Nurse, atteint son ralliement en bas : +2 pour lui). Pour limiter la casse, ton Garde (si6 vers la7) pousse TON PROPRE Héritier (la8) hors du plateau : c'est un mat sur toi-même, l'adversaire ne prend que +1 au lieu de +2."
 },
 {
  "title": "Fin : la papatte",
  "pieces": [
   [
    "do",
    8,
    "Chevalier",
    "Noir"
   ],
   [
    "si",
    8,
    "Héritier",
    "Noir"
   ],
   [
    "do",
    7,
    "Garde",
    "Blanc"
   ],
   [
    "ré",
    7,
    "Soldat",
    "Blanc"
   ],
   [
    "ré",
    8,
    "Garde",
    "Blanc"
   ],
   [
    "fa",
    3,
    "Héritier",
    "Blanc"
   ],
   [
    "mi",
    5,
    "Nurse",
    "Blanc"
   ],
   [
    "sol",
    5,
    "Chevalier",
    "Blanc"
   ]
  ],
  "framed": [
   [
    "do",
    8
   ],
   [
    "si",
    8
   ]
  ],
  "text": "PAPATTE (+1 point). C'est à l'adversaire de jouer, mais il n'a AUCUN coup légal : son Chevalier (do8) est coincé, et son Héritier (si8) est isolé (aucune ronde à côté). Il perd. Très rare !"
 },
 {
  "title": "Fin : la trêve",
  "pieces": [
   [
    "do",
    4,
    "Nurse",
    "Blanc"
   ],
   [
    "do",
    5,
    "Héritier",
    "Blanc"
   ],
   [
    "si",
    4,
    "Nurse",
    "Noir"
   ],
   [
    "si",
    5,
    "Héritier",
    "Noir"
   ],
   [
    "fa",
    1,
    "Soldat",
    "Blanc"
   ],
   [
    "fa",
    8,
    "Garde",
    "Noir"
   ],
   [
    "mi",
    6,
    "Chevalier",
    "Blanc"
   ],
   [
    "la",
    5,
    "Chevalier",
    "Noir"
   ]
  ],
  "framed": [
   [
    "fa",
    1
   ],
   [
    "fa",
    8
   ]
  ],
  "text": "TRÊVE (0 point). Quand plus AUCUN joueur n'a de carrée qui peut bouger (peu importe à qui c'est de jouer), la partie est nulle : sans carrée mobile, plus aucune poussée n'est possible. Ici, les deux carrées (encadrées) sont isolées."
 },
 {
  "title": "Fin : nulle par accord",
  "pieces": [
   [
    "mi",
    5,
    "Héritier",
    "Blanc"
   ],
   [
    "fa",
    4,
    "Nurse",
    "Blanc"
   ],
   [
    "ré",
    6,
    "Héritier",
    "Noir"
   ],
   [
    "sol",
    5,
    "Nurse",
    "Noir"
   ],
   [
    "do",
    3,
    "Garde",
    "Blanc"
   ],
   [
    "la",
    6,
    "Soldat",
    "Noir"
   ],
   [
    "fa",
    7,
    "Chevalier",
    "Noir"
   ],
   [
    "si",
    5,
    "Chevalier",
    "Blanc"
   ]
  ],
  "mock_ui": [
   {
    "text": "½",
    "fx": 0.5,
    "fy": 0.09,
    "fw": 0.11,
    "fh": 0.055,
    "bg": [
     0.2,
     0.45,
     0.75
    ],
    "circle": true
   }
  ],
  "text": "NULLE PAR ACCORD (0 point). Pendant une partie, tu peux proposer la nulle avec le bouton « ½ » (entouré) ; si l'adversaire accepte, la partie est nulle. RÉPÉTITION : si la même position revient 4 fois, la nulle est automatique."
 },
 {
  "title": "Fin : abandon, temps, déco",
  "pieces": [
   [
    "mi",
    4,
    "Héritier",
    "Blanc"
   ],
   [
    "fa",
    5,
    "Nurse",
    "Blanc"
   ],
   [
    "sol",
    4,
    "Héritier",
    "Noir"
   ],
   [
    "ré",
    5,
    "Nurse",
    "Noir"
   ],
   [
    "la",
    3,
    "Garde",
    "Blanc"
   ],
   [
    "do",
    6,
    "Soldat",
    "Noir"
   ],
   [
    "fa",
    3,
    "Chevalier",
    "Blanc"
   ],
   [
    "si",
    5,
    "Chevalier",
    "Noir"
   ]
  ],
  "mock_ui": [
   {
    "text": "0:00",
    "fx": 0.19,
    "fy": 0.93,
    "fw": 0.17,
    "fh": 0.06,
    "bg": [
     0.55,
     0.12,
     0.12
    ],
    "circle": true
   },
   {
    "text": "Joueur 1 deconnecte",
    "fx": 0.63,
    "fy": 0.93,
    "fw": 0.5,
    "fh": 0.06,
    "bg": [
     0.2,
     0.22,
     0.28
    ],
    "circle": true
   },
   {
    "text": "X",
    "fx": 0.3,
    "fy": 0.07,
    "fw": 0.11,
    "fh": 0.055,
    "bg": [
     0.6,
     0.2,
     0.2
    ],
    "circle": true
   }
  ],
  "text": "ABANDON / TEMPS / DÉCONNEXION (+2 points chacun). Trois façons de gagner sans jouer : si l'adversaire ABANDONNE (le bouton « X »), si son TEMPS tombe à 0:00 (la pendule), ou s'il se DÉCONNECTE. Dans les trois cas, tu gagnes +2 points."
 }
]
''';
