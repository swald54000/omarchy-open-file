#!/bin/bash

# Auxiliaire du greffon swald.files : liste des fichiers, miniatures, ouverture.
# Appelé par OpenFile.qml, jamais directement par l'utilisateur.
#
#   open-file.sh --list              liste tous les fichiers du dossier personnel, du plus
#                                    récent au plus ancien :
#                                    date (s) TAB taille (octets) TAB nom TAB dossier (~/…)
#   open-file.sh --preview <fichier> affiche le chemin d'une miniature PNG (image, PDF,
#                                    vidéo), ou rien si le fichier n'en a pas
#   open-file.sh --open <fichier>    ouvre le fichier avec son application
#   open-file.sh --reveal <fichier>  ouvre le dossier du fichier dans le gestionnaire de fichiers

set -euo pipefail

# Dossiers ignorés partout où ils apparaissent (les dossiers cachés le sont déjà).
noms_exclus=(node_modules target __pycache__ build dist venv)

# Chemins ignorés en plus, relatifs au dossier personnel, un par ligne ; les lignes vides
# et celles qui commencent par # sont sautées.
fichier_exclusions="${XDG_CONFIG_HOME:-$HOME/.config}/swald.files/exclude"

cache="${XDG_CACHE_HOME:-$HOME/.cache}/swald.files"
cote_miniature=640
delai_miniature=15

liste() {
  local exclusions=(-name '.*') nom chemin
  for nom in "${noms_exclus[@]}"; do
    exclusions+=(-o -name "$nom")
  done
  if [[ -r $fichier_exclusions ]]; then
    while IFS= read -r chemin || [[ -n $chemin ]]; do
      chemin=${chemin#"${chemin%%[![:space:]]*}"}
      chemin=${chemin%"${chemin##*[![:space:]]}"}
      chemin=${chemin#./}
      chemin=${chemin%/}
      [[ -z $chemin || $chemin == \#* ]] && continue
      exclusions+=(-o -path "./$chemin")
    done <"$fichier_exclusions"
  fi

  # Les miniatures de plus d'un mois sont refaites à la demande.
  [[ -d $cache ]] && find "$cache" -type f -mtime +30 -delete 2>/dev/null &

  cd "$HOME"
  # find sort en erreur dès qu'un dossier est illisible : la liste reste bonne.
  { find . -mindepth 1 \( "${exclusions[@]}" \) -prune -o -type f -printf '%T@\t%s\t%f\t%h\n' 2>/dev/null || true; } |
    sort -rn |
    LC_ALL=C awk -F'\t' '
      # Un nom contenant une tabulation ou un saut de ligne casserait le format.
      NF != 4 { next }
      {
        sub(/\..*/, "", $1)
        dossier = ($4 == ".") ? "~" : "~/" substr($4, 3)
        print $1 "\t" $2 "\t" $3 "\t" dossier
      }'
}

# Fabrique la miniature de $1 dans $2 ; le genre est celui de l'extension.
fabriquer() {
  local fichier=$1 sortie=$2 extension
  extension=${fichier##*.}
  extension=${extension,,}

  case $extension in
    jpg | jpeg | png | gif | webp | bmp | tif | tiff | svg | heic | heif | avif | jxl)
      # vipsthumbnail redresse la photo d'après son orientation EXIF.
      timeout "$delai_miniature" vipsthumbnail "$fichier" -s "${cote_miniature}x${cote_miniature}" -o "$sortie" ||
        timeout "$delai_miniature" magick "${fichier}[0]" -auto-orient -thumbnail "${cote_miniature}x${cote_miniature}" "$sortie"
      ;;
    pdf)
      timeout "$delai_miniature" pdftoppm -png -singlefile -f 1 -l 1 -scale-to "$cote_miniature" "$fichier" "${sortie%.png}"
      ;;
    mp4 | mov | mkv | webm | avi | m4v)
      timeout "$delai_miniature" ffmpegthumbnailer -i "$fichier" -o "$sortie" -s "$cote_miniature"
      ;;
    *)
      return 1
      ;;
  esac
}

apercu() {
  local fichier=$1 cle miniature provisoire
  [[ -f $fichier && -r $fichier ]] || return 0

  # La clé change avec le contenu : un fichier modifié reçoit une nouvelle miniature.
  cle=$(stat -c '%n|%Y|%s' -- "$fichier" | sha1sum | cut -d' ' -f1)
  miniature="$cache/$cle.png"
  if [[ -s $miniature ]]; then
    printf '%s\n' "$miniature"
    return 0
  fi

  mkdir -p "$cache"
  provisoire="$cache/.$cle.$$.png"
  if fabriquer "$fichier" "$provisoire" >/dev/null 2>&1 && [[ -s $provisoire ]]; then
    mv -f "$provisoire" "$miniature"
    printf '%s\n' "$miniature"
  else
    rm -f "$provisoire"
  fi
}

ouvrir() {
  local fichier=$1
  if [[ ! -f $fichier ]]; then
    notify-send "Open a file" "Not found: $fichier"
    return 1
  fi
  xdg-open "$fichier" || notify-send "Open a file" "No application could open: $fichier"
}

# Ouvre le dossier qui contient $1 avec l'application des dossiers (Files sous Omarchy).
montrer() {
  local dossier
  dossier=$(dirname -- "$1")
  if [[ ! -d $dossier ]]; then
    notify-send "Open a file" "Not found: $dossier"
    return 1
  fi
  xdg-open "$dossier" || notify-send "Open a file" "No application could open: $dossier"
}

case ${1:-} in
  --list)
    liste
    ;;
  --preview)
    apercu "${2:?missing file}"
    ;;
  --open)
    ouvrir "${2:?missing file}"
    ;;
  --reveal)
    montrer "${2:?missing file}"
    ;;
  *)
    echo "Usage: open-file.sh --list | --preview <file> | --open <file> | --reveal <file>" >&2
    exit 2
    ;;
esac
