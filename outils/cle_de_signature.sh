#!/usr/bin/env bash
# Fabrique LA CLÉ qui signe La Fuga pour le Play Store.
#
# À lancer UNE SEULE FOIS, sur une machine à toi. La clé qui en sort
# t'appartient : elle ne doit figurer ni dans le dépôt — il est public — ni
# dans une conversation. Son mot de passe non plus : il ne se tape qu'ici et
# dans la page des secrets de GitHub.
#
# Ce que le script fait :
#   1. il demande un mot de passe, sans l'afficher ;
#   2. il fabrique `lafuga-upload.jks`, valable cent ans — RSA 2048, la
#      taille que Google demande, et un pavé base64 deux fois plus court à
#      recopier qu'avec une clé de 4096 ;
#   3. il affiche le fichier encodé en base64, à coller dans un secret GitHub.
#
# Ce qu'il n'écrit nulle part : le mot de passe.
#
#   bash cle_de_signature.sh
set -euo pipefail

SORTIE="${1:-$HOME/lafuga-upload.jks}"
ALIAS="upload"

if ! command -v keytool >/dev/null 2>&1; then
  echo "keytool est introuvable. Installe un JDK :" >&2
  echo "  sudo apt update && sudo apt install -y default-jre-headless" >&2
  exit 1
fi

if [ -e "$SORTIE" ]; then
  echo "ATTENTION : $SORTIE existe déjà." >&2
  echo "Une clé publiée ne se remplace pas : si c'est la bonne, garde-la." >&2
  exit 1
fi

printf 'Mot de passe de la clé (il ne s’affichera pas) : '
read -rs MDP
echo
printf 'Le même, pour être sûr : '
read -rs MDP2
echo
if [ "$MDP" != "$MDP2" ]; then
  echo "Les deux saisies diffèrent. Rien n'a été écrit." >&2
  exit 1
fi
if [ "${#MDP}" -lt 8 ]; then
  echo "Huit caractères au moins : Java refuse plus court." >&2
  exit 1
fi

keytool -genkeypair \
  -alias "$ALIAS" \
  -keyalg RSA -keysize 2048 -validity 36500 \
  -keystore "$SORTIE" \
  -storetype PKCS12 \
  -storepass "$MDP" -keypass "$MDP" \
  -dname "CN=La Fuga, OU=La Fuga, O=La Fuga, L=, ST=, C=FR" >/dev/null

unset MDP MDP2
chmod 600 "$SORTIE"

echo
echo "Clé écrite : $SORTIE"
echo "SAUVEGARDE-LA. Perdue, elle ne se refabrique pas, et une application"
echo "publiée ne peut plus être mise à jour sans elle."
echo
echo "Dans GitHub → Settings → Secrets and variables → Actions, ajoute :"
echo
echo "  CLE_SIGNATURE_ALIAS      = $ALIAS"
echo "  CLE_SIGNATURE_MDP        = (le mot de passe que tu viens de taper)"
echo "  CLE_SIGNATURE_BASE64     = (le pavé ci-dessous, en entier)"
echo
echo "----- début du pavé base64 -----"
base64 -w0 "$SORTIE"
echo
echo "----- fin du pavé base64 -----"
