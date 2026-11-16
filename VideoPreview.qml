import QtQuick
import QtMultimedia

// Lecture muette et en boucle d'une vidéo dans le volet d'aperçu. Chargé à la demande par
// OpenFile.qml : si QtMultimedia manque ou si la vidéo est illisible, la miniature reste.
Item {
  id: root

  // Adresse file:// de la vidéo.
  property string source: ""
  // Vrai dès que des images arrivent : OpenFile.qml masque alors la miniature.
  readonly property bool enLecture: lecteur.playbackState === MediaPlayer.PlayingState && lecteur.hasVideo
    && lecteur.position > 0

  MediaPlayer {
    id: lecteur
    source: root.source
    videoOutput: sortie
    // Pas de sortie audio : l'aperçu ne fait aucun bruit.
    loops: MediaPlayer.Infinite
    onSourceChanged: if (root.source) play()
    Component.onCompleted: if (root.source) play()
  }

  // Les vidéos HDR sortent avec une transparence partielle, qui laisserait voir le bureau
  // derrière le panneau : l'image est composée sur un fond noir opaque, à sa taille exacte.
  Item {
    anchors.centerIn: parent
    width: sortie.contentRect.width
    height: sortie.contentRect.height
    visible: root.enLecture
    layer.enabled: true

    Rectangle {
      anchors.fill: parent
      color: "black"
    }

    VideoOutput {
      id: sortie
      anchors.centerIn: parent
      width: root.width
      height: root.height
      fillMode: VideoOutput.PreserveAspectFit
    }
  }
}
