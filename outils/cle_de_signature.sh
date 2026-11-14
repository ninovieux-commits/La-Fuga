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
#      taille que Google demande ;
#   3. il en écrit la version base64 dans un fichier, lisible par lui seul.
#
# IL N'AFFICHE RIEN DE SECRET. La première version imprimait le base64 à
# l'écran, « à coller dans GitHub » : une copie d'écran, un copier-coller de
# terminal, et la clé se retrouve dans une conversation. Une consigne ne
# protège pas contre ça — il faut que le secret ne passe pas par l'écran.
# C'est `deposer_la_cle.sh` qui l'envoie à GitHub, sans le montrer.
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

B64="$SORTIE.b64"
base64 -w0 "$SORTIE" > "$B64"
chmod 600 "$B64"

echo
echo "Clé écrite : $SORTIE"
echo "Version base64 : $B64  ($(wc -c < "$B64") octets)"
echo
echo "SAUVEGARDE LA CLÉ. Google garde la vraie clé de signature de son côté,"
echo "donc celle-ci se remplace en cas de perte — mais par une demande à"
echo "Google, et on s'en passera volontiers."
echo
echo "Rien de secret n'a été affiché. La suite dépose la clé dans GitHub"
echo "sans la montrer :"
echo
echo "  curl -fsSLO https://raw.githubusercontent.com/ninovieux-commits/La-Fuga/main/outils/deposer_la_cle.sh"
echo "  bash ~/deposer_la_cle.sh"
