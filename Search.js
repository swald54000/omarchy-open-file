// Logique pure du panneau swald.files (pas d'accès aux fichiers ni à Qt) : lecture de la
// liste écrite par « open-file.sh --list », filtre et classement, genres et tailles.
// Testé sous node par tests/search.test.js.

// Minuscules sans accents : « Événement » et « evenement » se trouvent l'un l'autre.
function normaliser(texte) {
  return String(texte || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "")
}

// Une ligne par fichier : date (secondes) TAB taille (octets) TAB nom TAB dossier (« ~ » ou « ~/… »),
// du plus récent au plus ancien. Les lignes mal formées sont ignorées.
function lire(texte) {
  var lignes = String(texte || "").split("\n")
  var entrees = []
  for (var i = 0; i < lignes.length; i++) {
    var champs = lignes[i].split("\t")
    if (champs.length !== 4 || !champs[2] || !champs[3]) continue
    entrees.push({
      date: parseInt(champs[0], 10) || 0,
      taille: parseInt(champs[1], 10) || 0,
      nom: champs[2],
      dossier: champs[3],
      cleNom: normaliser(champs[2]),
      cleDossier: normaliser(champs[3])
    })
  }
  return entrees
}

// Fichiers correspondant à la recherche, limités à « limite » lignes ; « total » compte tous
// ceux qui correspondent. Chaque mot doit figurer dans le nom ou le dossier. Classement : les
// noms qui commencent par le premier mot, puis ceux qui le contiennent, puis ceux trouvés par
// leur dossier ; dans chaque groupe l'ordre de la liste (le plus récent d'abord) est gardé.
// Sans recherche : les fichiers les plus récents.
function filtrer(entrees, recherche, limite) {
  var mots = normaliser(recherche).split(/\s+/).filter(function(m) { return m })
  if (mots.length === 0) return { lignes: entrees.slice(0, limite), total: entrees.length }

  var groupes = [[], [], []]
  var total = 0
  for (var i = 0; i < entrees.length; i++) {
    var e = entrees[i]
    var garde = true
    for (var j = 0; j < mots.length && garde; j++)
      garde = e.cleNom.indexOf(mots[j]) >= 0 || e.cleDossier.indexOf(mots[j]) >= 0
    if (!garde) continue
    total++
    var place = e.cleNom.indexOf(mots[0])
    var rang = place === 0 ? 0 : place > 0 ? 1 : 2
    if (groupes[rang].length < limite) groupes[rang].push(e)
  }
  return { lignes: groupes[0].concat(groupes[1], groupes[2]).slice(0, limite), total: total }
}

// Chemin complet d'une entrée, « maison » étant le dossier personnel.
function chemin(entree, maison) {
  var dossier = entree.dossier === "~" ? maison : maison + entree.dossier.slice(1)
  return dossier + "/" + entree.nom
}

function extension(nom) {
  var point = String(nom).lastIndexOf(".")
  return point > 0 ? String(nom).slice(point + 1).toLowerCase() : ""
}

var IMAGES = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "tif", "tiff", "svg", "heic", "heif", "avif", "jxl"]
var VIDEOS = ["mp4", "mov", "mkv", "webm", "avi", "m4v"]
var AUDIOS = ["opus", "mp3", "flac", "ogg", "oga", "m4a", "aac", "wav", "wma", "mka"]

// Genre d'un fichier d'après son extension : « image », « pdf », « video », « audio » ou
// « autre ». Les trois premiers ont une miniature (voir « open-file.sh --preview ») ; la
// vidéo et l'audio sont lus dans le panneau.
function genre(nom) {
  var ext = extension(nom)
  if (IMAGES.indexOf(ext) >= 0) return "image"
  if (ext === "pdf") return "pdf"
  if (VIDEOS.indexOf(ext) >= 0) return "video"
  if (AUDIOS.indexOf(ext) >= 0) return "audio"
  return "autre"
}

// Glyphe de la police d'icônes pour un genre.
function icone(nomGenre) {
  var points = { image: 0xF02E9, pdf: 0xF0226, video: 0xF0567, audio: 0xF075A, autre: 0xF0214 }
  return String.fromCodePoint(points[nomGenre] || points.autre)
}

// Taille arrondie pour l'affichage : valeur, nombre de décimales et rang de l'unité
// (0 = octets, 1 = kilo, 2 = méga…). 2073402 → { valeur: 2.1, decimales: 1, rang: 2 }.
function taille(octets) {
  var valeur = Math.max(0, Number(octets) || 0)
  var rang = 0
  while (valeur >= 1000 && rang < 4) { valeur /= 1000; rang++ }
  var decimales = rang === 0 || valeur >= 100 ? 0 : 1
  var facteur = decimales ? 10 : 1
  return { valeur: Math.round(valeur * facteur) / facteur, decimales: decimales, rang: rang }
}

function aMiniature(nomGenre) {
  return nomGenre === "image" || nomGenre === "pdf" || nomGenre === "video"
}

function seLit(nomGenre) {
  return nomGenre === "video" || nomGenre === "audio"
}

// Durée en millisecondes → « 0:07 », « 3:45 », « 1:02:03 ».
function dureeLisible(millisecondes) {
  var s = Math.max(0, Math.floor((Number(millisecondes) || 0) / 1000))
  var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), reste = s % 60
  var deux = function(n) { return (n < 10 ? "0" : "") + n }
  return h > 0 ? h + ":" + deux(m) + ":" + deux(reste) : m + ":" + deux(reste)
}
