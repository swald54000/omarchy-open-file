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

# Les miniatures se font sur des fichiers venus de n'importe où (téléchargements, pièces
# jointes), dès qu'une ligne est sélectionnée, et les outils décodent d'après le contenu,
# pas l'extension. ImageMagick (seul ou appelé par vips) suit donc les règles de
# magick/policy.xml : formats d'image attendus seulement, aucun programme externe.
export MAGICK_CONFIGURE_PATH
MAGICK_CONFIGURE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/magick"

# Bac à sable des outils de miniature, préparé par cloisonner ; vide s'il n'y en a pas.
cloison=()

# Enferme les outils de miniature avec bubblewrap : pas de réseau, le système en lecture
# seule, et du dossier personnel rien d'autre que le fichier $1 (en lecture) et le cache.
# Un fichier piégé qui prendrait la main sur un décodeur n'atteint ni les autres fichiers
# ni l'extérieur. Sans bwrap, ou s'il ne peut pas tourner ici, les outils sont lancés tels
# quels.
cloisonner() {
  local fichier=$1 dossier
  local essai=(bwrap --unshare-all --die-with-parent --new-session --cap-drop ALL
    --ro-bind /usr /usr --ro-bind /etc /etc --ro-bind-try /nix /nix
    --proc /proc --dev /dev --tmpfs /tmp)

  cloison=()
  command -v bwrap >/dev/null || return 0
  for dossier in /bin /sbin /lib /lib32 /lib64; do
    if [[ -L $dossier ]]; then
      essai+=(--symlink "$(readlink "$dossier")" "$dossier")
    elif [[ -d $dossier ]]; then
      essai+=(--ro-bind "$dossier" "$dossier")
    fi
  done
  essai+=(--ro-bind "$MAGICK_CONFIGURE_PATH" "$MAGICK_CONFIGURE_PATH"
    --ro-bind "$fichier" "$fichier" --bind "$cache" "$cache")
  if "${essai[@]}" true 2>/dev/null; then
    cloison=("${essai[@]}")
  fi
}

# Lance un outil de miniature dans le bac à sable, avec arrêt forcé s'il ignore le délai.
borner() {
  timeout -k 2 "$delai_miniature" "${cloison[@]}" "$@"
}

liste() {
  # Un nom contenant un saut de ligne pourrait se faire passer pour une autre entrée.
  local exclusions=(-name '.*' -o -name $'*\n*') nom chemin
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
    svg)
      # rsvg-convert ne lit que du SVG ; à défaut, vips avec tous ses décodeurs.
      borner rsvg-convert --keep-aspect-ratio -w "$cote_miniature" -h "$cote_miniature" -o "$sortie" -- "$fichier" ||
        borner vipsthumbnail "$fichier" -s "${cote_miniature}x${cote_miniature}" -o "$sortie"
      ;;
    jpg | jpeg | png | gif | webp | bmp | tif | tiff | heic | heif | avif | jxl)
      # vipsthumbnail redresse la photo d'après son orientation EXIF. VIPS_BLOCK_UNTRUSTED
      # écarte ses décodeurs peu sûrs (CSV, FITS, PDF, ImageMagick…) ; ce qu'il refuse
      # alors, le JPEG XL par exemple, revient à ImageMagick.
      VIPS_BLOCK_UNTRUSTED=1 borner vipsthumbnail "$fichier" -s "${cote_miniature}x${cote_miniature}" -o "$sortie" ||
        borner magick "${fichier}[0]" -auto-orient -thumbnail "${cote_miniature}x${cote_miniature}" "$sortie"
      ;;
    pdf)
      borner pdftoppm -png -singlefile -f 1 -l 1 -scale-to "$cote_miniature" "$fichier" "${sortie%.png}"
      ;;
    mp4 | mov | mkv | webm | avi | m4v)
      borner ffmpegthumbnailer -i "$fichier" -o "$sortie" -s "$cote_miniature"
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
  cle=$(stat -c '%n|%Y|%s' -- "$fichier" | sha256sum | cut -d' ' -f1)
  miniature="$cache/$cle.png"
  if [[ -s $miniature ]]; then
    printf '%s\n' "$miniature"
    return 0
  fi

  # Une miniature montre le contenu du fichier : le cache reste fermé aux autres
  # utilisateurs, y compris s'il a été créé ouvert par une version précédente.
  umask 077
  mkdir -p "$cache"
  chmod 700 "$cache" || return 0
  cloisonner "$fichier"
  provisoire="$cache/.$cle.$$.png"
  if fabriquer "$fichier" "$provisoire" >/dev/null 2>&1 && [[ -s $provisoire ]]; then
    mv -f "$provisoire" "$miniature"
    printf '%s\n' "$miniature"
  else
    rm -f "$provisoire"
  fi
}

# Le corps d'une notification est lu comme du balisage : un nom de fichier n'y écrit pas
# de lien ni de mise en forme.
prevenir() {
  local texte=$1
  # Entre guillemets, « & » reste un « & » et non le texte trouvé.
  texte=${texte//&/"&amp;"}
  texte=${texte//</"&lt;"}
  texte=${texte//>/"&gt;"}
  notify-send "Open a file" "$texte"
}

ouvrir() {
  local fichier=$1
  if [[ ! -f $fichier ]]; then
    prevenir "Not found: $fichier"
    return 1
  fi
  xdg-open "$fichier" || prevenir "No application could open: $fichier"
}

# Ouvre le dossier qui contient $1 avec l'application des dossiers (Files sous Omarchy).
montrer() {
  local dossier
  dossier=$(dirname -- "$1")
  if [[ ! -d $dossier ]]; then
    prevenir "Not found: $dossier"
    return 1
  fi
  xdg-open "$dossier" || prevenir "No application could open: $dossier"
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
