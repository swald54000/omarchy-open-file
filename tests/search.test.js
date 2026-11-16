// node --test tests/ — charge Search.js (fonctions globales, comme dans Quickshell).
const { test } = require('node:test')
const assert = require('node:assert/strict')
const { readFileSync } = require('node:fs')
const vm = require('node:vm')
const path = require('node:path')

const R = {}
vm.createContext(R)
vm.runInContext(readFileSync(path.join(__dirname, '../Search.js'), 'utf8'), R)

const liste = [
  '500\t10\tnotes.txt\t~',
  '400\t2073402\tIMG_0042.HEIC\t~/Downloads',
  '300\t20\tgrimg-test.png\t~/Pictures',
  '200\t30\trapport.pdf\t~/Documents/img',
  '100\t40\timg_ancien.jpg\t~/Pictures',
  '90\t50\tÉvénement.odt\t~/Documents'
].join('\n') + '\n'
const entrees = R.lire(liste)
// Tableaux recopiés : ceux du contexte vm ne sont pas « égaux » à ceux du test.
const noms = (r) => Array.from(r.lignes, (e) => e.nom)

test('lire : une entrée par ligne valide, lignes mal formées ignorées', () => {
  assert.equal(entrees.length, 6)
  assert.equal(R.lire('abc\n1\t2\tnom\n\n1\t2\t\t~\n').length, 0)
  assert.equal(entrees[1].nom, 'IMG_0042.HEIC')
  assert.equal(entrees[1].taille, 2073402)
  assert.equal(entrees[1].dossier, '~/Downloads')
})

test('filtrer : sans recherche, les plus récents dans l’ordre de la liste', () => {
  const r = R.filtrer(entrees, '  ', 3)
  assert.deepEqual(noms(r), ['notes.txt', 'IMG_0042.HEIC', 'grimg-test.png'])
  assert.equal(r.total, 6)
})

test('filtrer : « img » donne d’abord les noms qui commencent par img, sans tenir compte de la casse', () => {
  const r = R.filtrer(entrees, 'img', 50)
  assert.deepEqual(noms(r), ['IMG_0042.HEIC', 'img_ancien.jpg', 'grimg-test.png', 'rapport.pdf'])
  assert.equal(r.total, 4)
})

test('filtrer : un fichier ancien qui commence par la recherche passe avant un récent qui la contient', () => {
  const r = R.filtrer(entrees, 'IMG', 50)
  assert.ok(noms(r).indexOf('img_ancien.jpg') < noms(r).indexOf('grimg-test.png'))
})

test('filtrer : tous les mots doivent correspondre, dans le nom ou le dossier', () => {
  assert.deepEqual(noms(R.filtrer(entrees, 'img downloads', 50)), ['IMG_0042.HEIC'])
  assert.deepEqual(noms(R.filtrer(entrees, 'img pictures', 50)), ['img_ancien.jpg', 'grimg-test.png'])
  assert.equal(R.filtrer(entrees, 'img introuvable', 50).total, 0)
})

test('filtrer : les accents ne comptent pas', () => {
  assert.deepEqual(noms(R.filtrer(entrees, 'evenement', 50)), ['Événement.odt'])
  assert.deepEqual(noms(R.filtrer(entrees, 'ÉVÉ', 50)), ['Événement.odt'])
})

test('filtrer : la limite coupe la liste mais pas le total, et garde les meilleurs', () => {
  const r = R.filtrer(entrees, 'img', 2)
  assert.deepEqual(noms(r), ['IMG_0042.HEIC', 'img_ancien.jpg'])
  assert.equal(r.total, 4)
})

test('filtrer : un texte en forme de balise est cherché tel quel', () => {
  const e = R.lire('1\t1\t<img src=x>.txt\t~\n')
  assert.deepEqual(noms(R.filtrer(e, '<img', 5)), ['<img src=x>.txt'])
})

test('chemin : dossier personnel et sous-dossier', () => {
  assert.equal(R.chemin(entrees[0], '/maison/u'), '/maison/u/notes.txt')
  assert.equal(R.chemin(entrees[1], '/maison/u'), '/maison/u/Downloads/IMG_0042.HEIC')
})

test('genre : d’après l’extension, sans tenir compte de la casse', () => {
  assert.equal(R.genre('IMG_0042.HEIC'), 'image')
  assert.equal(R.genre('a.b.PDF'), 'pdf')
  assert.equal(R.genre('IMG_0043.mov'), 'video')
  assert.equal(R.genre('Main Theme.opus'), 'audio')
  assert.equal(R.genre('a.MP3'), 'audio')
  assert.equal(R.genre('notes.txt'), 'autre')
  assert.equal(R.genre('sans-extension'), 'autre')
  assert.equal(R.genre('.png'), 'autre')
})

test('icone : un glyphe par genre', () => {
  const vus = new Set(['image', 'pdf', 'video', 'audio', 'autre'].map(R.icone))
  assert.equal(vus.size, 5)
  assert.equal(R.icone('inconnu'), R.icone('autre'))
})

test('taille : valeur arrondie, décimales et rang de l’unité', () => {
  const t = (o) => { const r = R.taille(o); return [r.valeur, r.decimales, r.rang] }
  assert.deepEqual(t(12), [12, 0, 0])
  assert.deepEqual(t(564427), [564, 0, 1])
  assert.deepEqual(t(2073402), [2.1, 1, 2])
  assert.deepEqual(t(205657398), [206, 0, 2])
  assert.deepEqual(t(-5), [0, 0, 0])
})

test('aMiniature et seLit : image et PDF en miniature, vidéo les deux, audio lu seulement', () => {
  assert.deepEqual(['image', 'pdf', 'video', 'audio', 'autre'].map(R.aMiniature), [true, true, true, false, false])
  assert.deepEqual(['image', 'pdf', 'video', 'audio', 'autre'].map(R.seLit), [false, false, true, true, false])
})

test('dureeLisible', () => {
  assert.equal(R.dureeLisible(0), '0:00')
  assert.equal(R.dureeLisible(7400), '0:07')
  assert.equal(R.dureeLisible(225000), '3:45')
  assert.equal(R.dureeLisible(3723000), '1:02:03')
  assert.equal(R.dureeLisible(-1), '0:00')
})
