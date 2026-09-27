import QtQuick

// A decorative playback indicator, not an audio spectrum analyser.
Item {
  id: root
  property bool active: false
  property bool animate: true
  property color ink: "white"
  readonly property bool moving: active && animate && visible
  Row {
    anchors.fill: parent
    spacing: 3
    Repeater {
      model: 28
      Rectangle {
        required property int index
        width: Math.max(1, (root.width - 27 * 3) / 28)
        height: root.height
        anchors.verticalCenter: parent.verticalCenter
        radius: width / 2
        color: root.ink
        opacity: root.active ? 0.3 + (index % 4) * 0.14 : 0.18
        scale: root.active ? 0.3 + (index * 7 % 11) / 16 : 0.12
        transformOrigin: Item.Center
        SequentialAnimation on scale {
          running: root.moving
          loops: Animation.Infinite
          NumberAnimation { to: 0.25 + (index * 3 % 8) / 11; duration: 480 + (index % 5) * 110; easing.type: Easing.InOutSine }
          NumberAnimation { to: 0.15 + (index * 7 % 9) / 12; duration: 560 + (index % 3) * 150; easing.type: Easing.InOutSine }
        }
      }
    }
  }
}
