#!/usr/bin/env bash
# Dépose la clé de signature dans les secrets du dépôt GitHub.
#
# LE SECRET NE PASSE NI PAR L'ÉCRAN NI PAR UN COPIER-COLLER. `gh` lit le
# fichier base64 et l'envoie chiffré ; le mot de passe est tapé sans être
# affiché et part de la même façon. Rien de ce que le terminal montre n'est
# confidentiel, donc une copie d'écran ne coûte rien.
#
#   bash deposer_la_cle.sh
set -euo pipefail

DEPOT="ninovieux-commits/La-Fuga"
B64="${1:-$HOME/lafuga-upload.jks.b64}"
ALIAS="upload"

if ! command -v gh >/dev/null 2>&1; then
  echo "L'outil GitHub manque. Installe-le :" >&2
  echo "  sudo apt install -y gh" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Ton serveur n'est pas encore connecté à GitHub. Lance :" >&2
  echo "  gh auth login --hostname github.com --git-protocol https --web" >&2
  echo "puis relance ce script." >&2
  exit 1
fi

if [ ! -s "$B64" ]; then
  echo "Fichier introuvable ou vide : $B64" >&2
  echo "Refais la clé avec cle_de_signature.sh." >&2
  exit 1
fi

printf 'Mot de passe de la clé (il ne s’affichera pas) : '
read -rs MDP
echo
if [ -z "$MDP" ]; then
  echo "Mot de passe vide : rien n'a été envoyé." >&2
  exit 1
fi

gh secret set CLE_SIGNATURE_ALIAS  --repo "$DEPOT" --body "$ALIAS"
printf '%s' "$MDP" | gh secret set CLE_SIGNATURE_MDP --repo "$DEPOT"
gh secret set CLE_SIGNATURE_BASE64 --repo "$DEPOT" < "$B64"
unset MDP

# Le base64 n'a plus de raison d'exister : la clé elle-même reste, et c'est
# elle qu'il faut sauvegarder.
shred -u "$B64" 2>/dev/null || rm -f "$B64"

echo
echo "Les trois secrets sont déposés sur $DEPOT :"
gh secret list --repo "$DEPOT" | sed 's/^/  /'
echo
echo "Le fichier base64 a été effacé. La clé reste dans ~/lafuga-upload.jks."
