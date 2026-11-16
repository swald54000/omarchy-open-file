import QtQuick
import QtMultimedia

// Pré-écoute d'un fichier audio depuis le volet d'aperçu. Chargé à la demande par
// OpenFile.qml, détruit dès que la sélection change ou que le panneau se ferme : le son
// s'arrête alors de lui-même.
Item {
  id: root

  // Adresse file:// du morceau.
  property string source: ""
  readonly property bool enLecture: lecteur.playbackState === MediaPlayer.PlayingState
  readonly property int position: lecteur.position
  readonly property int duree: lecteur.duration

  MediaPlayer {
    id: lecteur
    source: root.source
    audioOutput: AudioOutput {}
    onSourceChanged: if (root.source) play()
    Component.onCompleted: if (root.source) play()
  }
}
