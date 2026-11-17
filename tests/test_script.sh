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
# Nom forgé pour ressembler à une entrée de plus, datée dans le futur.
touch "$maison/Documents/$(printf 'x\n9999999999\t1\tintrus.txt')"
mkdir -p "$maison/Documents/$(printf 'sous\nfaux')" && touch "$maison/Documents/$(printf 'sous\nfaux')/dedans.txt"
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
verifier "liste : un nom à saut de ligne ne forge pas d'entrée" test -z "$(grep -E 'intrus|dedans' <<<"$sortie")"
verifier "liste : dossiers cachés, exclus (par nom ou par le fichier exclude) et noms à tabulation absents" test "$(wc -l <<<"$sortie")" -eq 5

# Miniatures : une image, un PDF, un fichier sans aperçu.
magick -size 800x400 xc:red "$maison/Downloads/rouge.png"
magick -size 300x300 xc:blue "$maison/Downloads/page.pdf"
echo "texte" >"$maison/Downloads/notes.txt"

# Un cache laissé ouvert par une version précédente doit être refermé.
mkdir -p -m 755 "$XDG_CACHE_HOME/swald.files"
miniature=$(umask 022 && "$script" --preview "$maison/Downloads/rouge.png")
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
verifier "apercu : cache réservé à l'utilisateur" test "$(stat -c '%a' "$XDG_CACHE_HOME/swald.files")" = "700"
verifier "apercu : miniatures réservées à l'utilisateur" test -z "$(find "$XDG_CACHE_HOME/swald.files" -type f -perm /077)"
verifier "apercu : aucun fichier provisoire laissé" test -z "$(find "$XDG_CACHE_HOME/swald.files" -name '.*' -type f)"

# Un PostScript ou un PDF déguisé en image ne doit lancer aucun programme externe.
espion="$maison/.espion"
mkdir -p "$espion"
printf '#!/bin/bash\ntouch "$HOME/.espion/appele"\nexit 1\n' >"$espion/gs"
cp "$espion/gs" "$espion/inkscape"
chmod +x "$espion/gs" "$espion/inkscape"
printf '%%!PS\n10 10 moveto showpage\n' >"$maison/Downloads/postscript.jpg"
cp "$maison/Downloads/page.pdf" "$maison/Downloads/pdf.png"
PATH="$espion:$PATH" "$script" --preview "$maison/Downloads/postscript.jpg" >/dev/null
PATH="$espion:$PATH" "$script" --preview "$maison/Downloads/pdf.png" >/dev/null
verifier "apercu : image déguisée → aucun programme externe lancé" test ! -e "$espion/appele"

printf '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="100"><rect width="400" height="100" fill="red"/></svg>' >"$maison/Downloads/dessin.svg"
verifier "apercu : SVG → un PNG" test -s "$("$script" --preview "$maison/Downloads/dessin.svg")"

if command -v ffmpeg >/dev/null && command -v ffmpegthumbnailer >/dev/null; then
  ffmpeg -loglevel error -f lavfi -i testsrc=duration=2:size=320x240:rate=10 "$maison/Downloads/film.mp4"
  verifier "apercu : vidéo → un PNG" test -s "$("$script" --preview "$maison/Downloads/film.mp4")"
else
  echo "saut apercu : vidéo (ffmpeg ou ffmpegthumbnailer absent)"
fi

# Bac à sable : un SVG peut d'ordinaire inclure une image voisine ; enfermé, l'outil ne voit
# que le fichier demandé.
if bwrap --unshare-all --ro-bind / / true 2>/dev/null; then
  magick -size 100x100 xc:red "$maison/Downloads/voisin.png"
  printf '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><image href="voisin.png" width="100" height="100"/></svg>' >"$maison/Downloads/curieux.svg"
  curieux=$("$script" --preview "$maison/Downloads/curieux.svg")
  verifier "bac à sable : la miniature est faite" test -s "$curieux"
  verifier "bac à sable : le fichier voisin n'est pas lu" test "$(magick "$curieux" -format '%[fx:int(255*p{50,50}.a)]' info:)" = "0"
else
  echo "saut bac à sable (bwrap absent ou inutilisable)"
fi

if command -v heif-enc >/dev/null; then
  heif-enc -o "$maison/Downloads/IMG_9999.HEIC" "$miniature" >/dev/null 2>&1
  verifier "apercu : HEIC → un PNG" test -s "$("$script" --preview "$maison/Downloads/IMG_9999.HEIC")"
else
  echo "saut apercu : HEIC (heif-enc absent)"
fi

# Ouverture : faux xdg-open et notify-send qui notent leurs arguments.
faux="$maison/.faux"
mkdir -p "$faux"
printf '#!/bin/bash\nprintf "%%s\\n" "$@" >>"$HOME/.faux/xdg-open.log"\n' >"$faux/xdg-open"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >>"$HOME/.faux/notify.log"\n' >"$faux/notify-send"
chmod +x "$faux/xdg-open" "$faux/notify-send"

PATH="$faux:$PATH" "$script" --open "$maison/Documents/trois octets.txt"
verifier "open : le fichier est passé à xdg-open" test "$(tail -1 "$faux/xdg-open.log")" = "$maison/Documents/trois octets.txt"
PATH="$faux:$PATH" "$script" --reveal "$maison/Documents/trois octets.txt"
verifier "reveal : c'est le dossier du fichier qui est ouvert" test "$(tail -1 "$faux/xdg-open.log")" = "$maison/Documents"
PATH="$faux:$PATH" "$script" --reveal "$maison/racine.md"
verifier "reveal : fichier à la racine → dossier personnel" test "$(tail -1 "$faux/xdg-open.log")" = "$maison"
lignes=$(wc -l <"$faux/xdg-open.log")
PATH="$faux:$PATH" "$script" --reveal "$maison/disparu/fichier.txt" >/dev/null 2>&1
verifier "reveal : dossier disparu → code d'erreur" test $? -ne 0
verifier "reveal : dossier disparu → rien d'ouvert, une notification" test "$(wc -l <"$faux/xdg-open.log")" -eq "$lignes" -a -s "$faux/notify.log"

PATH="$faux:$PATH" "$script" --open "$maison/<b>a&b</b>.txt" >/dev/null 2>&1
verifier "notification : le nom du fichier n'y écrit pas de balisage" grep -qF '&lt;b&gt;a&amp;b&lt;/b&gt;.txt' "$faux/notify.log"

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
