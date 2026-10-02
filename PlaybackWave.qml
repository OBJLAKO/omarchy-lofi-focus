import QtQuick
import QtQuick.Window

// An ongoing playback-status motif, not a measurement of the audio signal.
// Three predetermined stems update at 8 Hz; no render-frame animation runs
// between updates. Pause, hidden windows and reduced motion stop the timer.
Item {
  id: root
  property bool active: false
  property bool animate: true
  property color ink: "white"
  property int phase: 0
  property int frameCount: 0
  readonly property int updateInterval: 125
  readonly property var hostWindow: root.Window.window
  readonly property bool presented: visible && (!hostWindow || (hostWindow.visible && hostWindow.visibility !== Window.Minimized))
  readonly property bool moving: pulse.running
  onMovingChanged: if (!moving) phase = 0

  function stemScale(index) {
    if (!root.active) return 0.25
    var rest = [0.55, 0.68, 0.42][index]
    if (!root.moving) return rest
    return rest + 0.18 * Math.sin((root.phase + index * 4) * Math.PI / 6)
  }

  Timer {
    id: pulse
    objectName: "playbackPulse"
    interval: root.updateInterval
    repeat: true
    running: root.active && root.animate && root.presented
    onTriggered: {
      root.phase = (root.phase + 1) % 12
      root.frameCount++
    }
  }
  Row {
    anchors.fill: parent
    spacing: Math.max(1, root.width / 9)
    Repeater {
      model: 3
      Rectangle {
        id: stem
        required property int index
        objectName: "playbackStem-" + index
        width: (root.width - 2 * parent.spacing) / 3
        height: root.height
        radius: width / 2
        color: root.ink
        opacity: root.active ? 0.9 : 0.4
        transform: Scale {
          origin.x: stem.width / 2
          origin.y: stem.height / 2
          yScale: root.stemScale(stem.index)
        }
      }
    }
  }
}
