import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Search.js" as Recherche

// Panneau « Ouvrir un fichier » : recherche dans tous les fichiers du dossier personnel, liste
// à gauche, aperçu à droite. La liste, les miniatures et l'ouverture passent par le script
// open-file.sh ; le filtre et le classement sont dans Search.js.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string maison: Quickshell.env("HOME")
  readonly property string script: decodeURIComponent(Qt.resolvedUrl("open-file.sh").toString().replace(/^file:\/\//, ""))
  readonly property int limite: 200

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0

  // Tous les fichiers (relus à chaque ouverture), puis ceux que la recherche garde.
  property var entrees: []
  property bool listeLue: false
  property var lignes: []
  property int total: 0
  readonly property var selection: selectedIndex >= 0 && selectedIndex < lignes.length ? lignes[selectedIndex] : null
  readonly property string cheminSelection: selection ? Recherche.chemin(selection, maison) : ""
  readonly property string genreSelection: selection ? Recherche.genre(selection.nom) : "autre"

  // Miniature du fichier sélectionné : vide tant qu'elle n'est pas prête ou s'il n'y en a pas.
  property string apercuSource: ""
  property string apercuPour: ""
  property bool apercuEnAttente: false
  // Vidéo ou morceau lu dans le volet d'aperçu : vide tant que Tab ne l'a pas demandé.
  property string lecturePour: ""
  property string lectureGenre: ""
  readonly property bool videoEnLecture: genreSelection === "video" && lecteur.item !== null && lecteur.item.enLecture
  readonly property bool audioEnLecture: genreSelection === "audio" && lecteur.item !== null && lecteur.item.enLecture

  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int rowHeight: Style.font.title + Style.font.body + Style.spacing.controlPaddingY * 2 + Style.space(6)
  property int cardWidth: Math.min(Style.space(1040), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(620), panel.height - Style.gapsOut * 2)

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.rebuildDisplay()
    lecture.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "swald.files")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function charger(texte) {
    root.entrees = Recherche.lire(texte)
    root.listeLue = true
    if (root.opened) root.rebuildDisplay()
  }

  function rebuildDisplay() {
    var resultat = Recherche.filtrer(root.entrees, root.filterText, root.limite)
    root.lignes = resultat.lignes
    root.total = resultat.total

    displayModel.clear()
    for (var i = 0; i < resultat.lignes.length; i++) {
      var e = resultat.lignes[i]
      displayModel.append({ nom: e.nom, dossier: e.dossier, glyphe: Recherche.icone(Recherche.genre(e.nom)) })
    }

    if (selectedIndex >= displayModel.count) selectedIndex = Math.max(0, displayModel.count - 1)
    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
    root.demanderApercu()
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.rebuildDisplay()
  }

  function select(delta) {
    if (displayModel.count === 0) return
    var next = selectedIndex + delta
    if (Math.abs(delta) === 1) next = (next + displayModel.count) % displayModel.count
    else next = Math.max(0, Math.min(displayModel.count - 1, next))
    selectedIndex = next
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function activateIndex(index) {
    if (index < 0 || index >= root.lignes.length) return
    var chemin = Recherche.chemin(root.lignes[index], root.maison)
    root.dismiss()
    Quickshell.execDetached(["bash", root.script, "--open", chemin])
  }

  // Ouvre le gestionnaire de fichiers dans le dossier du fichier, sans ouvrir le fichier.
  function revealIndex(index) {
    if (index < 0 || index >= root.lignes.length) return
    var chemin = Recherche.chemin(root.lignes[index], root.maison)
    root.dismiss()
    Quickshell.execDetached(["bash", root.script, "--reveal", chemin])
  }

  onCheminSelectionChanged: demanderApercu()
  // Le panneau reste chargé une fois fermé : la lecture ne doit pas continuer derrière.
  onOpenedChanged: if (!opened) demanderApercu()

  // L'aperçu suit la sélection avec un court délai : parcourir la liste au clavier ne lance
  // pas une miniature par ligne traversée.
  function demanderApercu() {
    root.apercuSource = ""
    root.lecturePour = ""
    delaiApercu.stop()
    if (!root.opened || !root.cheminSelection) return
    if (Recherche.aMiniature(root.genreSelection)) delaiApercu.restart()
  }

  // Lance ou arrête la lecture de la vidéo ou du morceau sélectionné. Rien n'est lu sans
  // cette demande : le lecteur tourne dans le shell lui-même, hors de tout bac à sable, et
  // ne doit pas décoder un fichier que l'utilisateur n'a fait que survoler.
  function basculerLecture() {
    if (root.lecturePour !== "") {
      root.lecturePour = ""
    } else if (root.opened && root.cheminSelection && Recherche.seLit(root.genreSelection)) {
      root.lectureGenre = root.genreSelection
      root.lecturePour = root.cheminSelection
    }
  }

  function adresse(chemin) {
    return "file://" + String(chemin).split("/").map(encodeURIComponent).join("/")
  }

  function lancerApercu() {
    if (!root.opened || !root.cheminSelection || !Recherche.aMiniature(root.genreSelection)) return
    if (miniature.running) {
      root.apercuEnAttente = true
      return
    }
    root.apercuEnAttente = false
    root.apercuPour = root.cheminSelection
    miniature.command = ["bash", root.script, "--preview", root.apercuPour]
    miniature.running = true
  }

  // Une miniature arrivée après un changement de sélection n'est pas affichée.
  function apercuRecu(texte) {
    var chemin = String(texte || "").split("\n")[0]
    if (root.apercuPour === root.cheminSelection && chemin.charAt(0) === "/")
      root.apercuSource = root.adresse(chemin)
  }

  function dateLisible(secondes) {
    return Qt.locale(Commons.I18n.formatLocale).toString(new Date(secondes * 1000), "d MMM yyyy, HH:mm")
  }

  // « 1 fichier », « 37 fichiers », « 200 sur 14 431 fichiers », dans la langue d'Omarchy.
  function decompte(affiches, total) {
    if (total === 0) return strings.t("count.none")
    if (affiches < total)
      return strings.t("count.partial").arg(Commons.I18n.formatNumber(affiches, 0)).arg(Commons.I18n.formatNumber(total, 0))
    return strings.tn("count.files", total).arg(Commons.I18n.formatNumber(total, 0))
  }

  // « 2,1 Mo » ou « 2.1 MB » : unités et séparateur décimal de la langue.
  function tailleLisible(octets) {
    var t = Recherche.taille(octets)
    return Commons.I18n.formatNumber(t.valeur, t.decimales) + " " + strings.t("size.units").split(",")[t.rang]
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  ListModel { id: displayModel }

  Process {
    id: lecture
    command: ["bash", root.script, "--list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.charger(text)
    }
  }

  Process {
    id: miniature
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.apercuRecu(text)
    }
    onRunningChanged: if (!running && root.apercuEnAttente) root.lancerApercu()
  }

  Timer {
    id: delaiApercu
    interval: 70
    onTriggered: root.lancerApercu()
  }

  component Texte: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideMiddle
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "open-file"

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            root.basculerLecture()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
            var page = Math.max(2, Math.floor(resultList.height / root.rowHeight))
            root.select(event.key === Qt.Key_PageUp ? -page : page)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) root.revealIndex(root.selectedIndex)
            else root.activateIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        // Recherche à gauche, nombre de fichiers à droite.
        Item {
          width: parent.width
          height: root.headerHeight

          Texte {
            anchors.left: parent.left
            anchors.right: compte.left
            anchors.rightMargin: root.contentSpacing
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || strings.t("search.placeholder")
            opacity: root.filterText ? 1 : 0.58
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          Texte {
            id: compte
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.listeLue ? root.decompte(root.lignes.length, root.total) : strings.t("list.loading")
            opacity: 0.58
          }
        }

        Row {
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing
          spacing: root.contentSpacing

          Item {
            id: listPane
            width: Math.round((parent.width - parent.spacing) * 0.56)
            height: parent.height

            ListView {
              id: resultList
              anchors.fill: parent
              model: displayModel
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              delegate: Rectangle {
                id: row
                required property int index
                required property string nom
                required property string dossier
                required property string glyphe

                readonly property bool hasCursor: index === root.selectedIndex

                width: resultList.width
                height: root.rowHeight
                radius: root.cornerRadius
                color: hasCursor ? root.selectedBackground : "transparent"

                Text {
                  id: icon
                  textFormat: Text.PlainText
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.font.heading + Style.space(6)
                  text: row.glyphe
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: row.hasCursor ? 1 : 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  horizontalAlignment: Text.AlignHCenter
                }

                Column {
                  anchors.left: icon.right
                  anchors.leftMargin: Style.spacing.md
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Texte {
                    width: parent.width
                    text: row.nom
                    color: row.hasCursor ? root.selectedText : root.foreground
                    font.pixelSize: Style.font.title
                  }

                  Texte {
                    width: parent.width
                    text: row.dossier
                    color: row.hasCursor ? root.selectedText : root.foreground
                    opacity: 0.62
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  // Un vrai déplacement du pointeur, pas la liste qui défile dessous.
                  onPositionChanged: root.selectedIndex = row.index
                  onClicked: root.activateIndex(row.index)
                }
              }
            }

            Texte {
              anchors.centerIn: parent
              width: parent.width - 2 * root.contentMargin
              visible: root.listeLue && displayModel.count === 0
              text: strings.t("list.noMatch").arg(root.filterText)
              opacity: 0.7
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
            }
          }

          // Aperçu du fichier sélectionné : miniature ou icône, puis nom, taille, date, dossier.
          Item {
            id: previewPane
            width: parent.width - listPane.width - parent.spacing
            height: parent.height
            visible: root.selection !== null

            Column {
              id: details
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              spacing: Style.space(4)

              Texte {
                width: parent.width
                text: root.selection ? root.selection.nom : ""
                font.pixelSize: Style.font.title
                horizontalAlignment: Text.AlignHCenter
              }

              Texte {
                width: parent.width
                text: root.selection
                  ? root.tailleLisible(root.selection.taille) + "  ·  " + root.dateLisible(root.selection.date)
                  : ""
                opacity: 0.62
                horizontalAlignment: Text.AlignHCenter
              }

              Texte {
                width: parent.width
                text: root.selection ? root.selection.dossier : ""
                opacity: 0.62
                horizontalAlignment: Text.AlignHCenter
              }

              Texte {
                width: parent.width
                topPadding: Style.space(6)
                text: Recherche.seLit(root.genreSelection) ? strings.t("hint.keysPlayable") : strings.t("hint.keys")
                opacity: 0.4
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
              }
            }

            Item {
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: details.top
              anchors.bottomMargin: root.contentSpacing

              Image {
                id: thumbnail
                anchors.fill: parent
                source: root.apercuSource
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
                smooth: true
                visible: status === Image.Ready && !root.videoEnLecture
              }

              Loader {
                id: lecteur
                anchors.fill: parent
                active: root.lecturePour !== ""
                source: root.lectureGenre === "audio" ? "AudioPreview.qml" : "VideoPreview.qml"
                onLoaded: item.source = root.adresse(root.lecturePour)
              }

              Text {
                anchors.centerIn: parent
                id: bigIcon
                textFormat: Text.PlainText
                visible: !thumbnail.visible && !root.videoEnLecture
                text: Recherche.icone(root.genreSelection)
                color: root.foreground
                opacity: root.audioEnLecture ? 0.9 : 0.35
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge * 2
              }

              // Pré-écoute en cours : position et durée du morceau.
              Texte {
                anchors.top: bigIcon.bottom
                anchors.topMargin: root.contentSpacing
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.audioEnLecture
                text: root.audioEnLecture
                  ? Recherche.dureeLisible(lecteur.item.position) + " / " + Recherche.dureeLisible(lecteur.item.duree)
                  : ""
                opacity: 0.7
              }
            }
          }
        }
      }
    }
  }
}
