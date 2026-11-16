#!/bin/bash

# Tests de open-file.sh sur un dossier personnel factice. Lancer : tests/test_script.sh

set -uo pipefail

ici=$(cd "$(dirname "$0")" && pwd)
script="$ici/../open-file.sh"
echecs=0

verifier() {
  local titre=$1
  shift
  if "$@"; then
    echo "ok   $titre"
  else
    echo "ÉCHEC $titre"
    echecs=$((echecs + 1))
  fi
}

maison=$(mktemp -d)
trap 'rm -rf "$maison"' EXIT
export HOME="$maison" XDG_CACHE_HOME="$maison/.cache" XDG_CONFIG_HOME="$maison/.config"

mkdir -p "$maison"/{Downloads,Documents/sous,.secret,Jeux/jeu,projet/node_modules/x,Sources/noyau,illisible,.config/swald.files}
printf '# chemins exclus\n\nJeux\n  ./Sources/noyau/  \n' >"$maison/.config/swald.files/exclude"
touch -d '2026-01-01 10:00' "$maison/Documents/sous/ancien.txt"
touch -d '2026-06-01 10:00' "$maison/Downloads/IMG_0001.HEIC"
touch -d '2026-09-01 10:00' "$maison/racine.md"
printf 'abc' >"$maison/Documents/trois octets.txt"
touch -d '2026-03-01 10:00' "$maison/Documents/trois octets.txt"
touch "$maison/.secret/cache.txt" "$maison/.bashrc" "$maison/Jeux/jeu/gros.bin" \
  "$maison/projet/node_modules/x/index.js" "$maison/Sources/noyau/Makefile" "$maison/Sources/gardé.c"
touch -d '2026-02-01 10:00' "$maison/Sources/gardé.c"
touch "$maison/Documents/$(printf 'avec\ttab.txt')"
chmod 000 "$maison/illisible"

sortie=$("$script" --list)
code=$?
chmod 755 "$maison/illisible"

verifier "liste : réussit malgré un dossier illisible" test "$code" -eq 0
verifier "liste : du plus récent au plus ancien" test "$(cut -f3 <<<"$sortie" | paste -sd,)" = "racine.md,IMG_0001.HEIC,trois octets.txt,gardé.c,ancien.txt"
verifier "liste : dossier personnel noté ~" grep -q $'\tracine.md\t~$' <<<"$sortie"
verifier "liste : sous-dossier noté ~/…" grep -q $'\tancien.txt\t~/Documents/sous$' <<<"$sortie"
verifier "liste : taille en octets" grep -q $'\t3\ttrois octets.txt\t' <<<"$sortie"
verifier "liste : date en secondes entières" grep -Eq $'^[0-9]+\t0\tIMG_0001.HEIC\t~/Downloads$' <<<"$sortie"
verifier "liste : dossiers cachés, exclus (par nom ou par le fichier exclude) et noms à tabulation absents" test "$(wc -l <<<"$sortie")" -eq 5

# Miniatures : une image, un PDF, un fichier sans aperçu.
magick -size 800x400 xc:red "$maison/Downloads/rouge.png"
magick -size 300x300 xc:blue "$maison/Downloads/page.pdf"
echo "texte" >"$maison/Downloads/notes.txt"

miniature=$("$script" --preview "$maison/Downloads/rouge.png")
verifier "apercu : image → un PNG dans le cache" test -s "$miniature"
verifier "apercu : miniature rangée dans le cache" test "${miniature#"$XDG_CACHE_HOME/swald.files/"}" != "$miniature"
verifier "apercu : réduite à 640 de large" test "$(magick identify -format '%wx%h' "$miniature")" = "640x320"
verifier "apercu : la même au second appel" test "$("$script" --preview "$maison/Downloads/rouge.png")" = "$miniature"

magick -size 100x100 xc:green "$maison/Downloads/rouge.png"
verifier "apercu : fichier modifié → nouvelle miniature" test "$("$script" --preview "$maison/Downloads/rouge.png")" != "$miniature"

verifier "apercu : PDF → un PNG" test -s "$("$script" --preview "$maison/Downloads/page.pdf")"
verifier "apercu : fichier sans aperçu → rien" test -z "$("$script" --preview "$maison/Downloads/notes.txt")"
verifier "apercu : fichier absent → rien, sans erreur" test -z "$("$script" --preview "$maison/absent.png")"

echo "pas une image" >"$maison/Downloads/faux.png"
verifier "apercu : image illisible → rien" test -z "$("$script" --preview "$maison/Downloads/faux.png")"
verifier "apercu : aucun fichier provisoire laissé" test -z "$(find "$XDG_CACHE_HOME/swald.files" -name '.*' -type f)"

if command -v heif-enc >/dev/null; then
  heif-enc -o "$maison/Downloads/IMG_9999.HEIC" "$miniature" >/dev/null 2>&1
  verifier "apercu : HEIC → un PNG" test -s "$("$script" --preview "$maison/Downloads/IMG_9999.HEIC")"
else
  echo "saut apercu : HEIC (heif-enc absent)"
fi

"$script" --inconnu >/dev/null 2>&1
verifier "option inconnue → code 2" test $? -eq 2
"$script" >/dev/null 2>&1
verifier "sans option → code 2" test $? -eq 2

echo
if ((echecs)); then
  echo "$echecs échec(s)"
  exit 1
fi
echo "Tout passe."
