import QtQuick

// Small state indicator, deliberately not presented as measured audio data.
Item {
  id: root
  property bool active: false
  property bool animate: true
  property color ink: "white"
  readonly property bool moving: active && animate && visible
  Row {
    anchors.fill: parent
    spacing: Math.max(1, root.width / 9)
    Repeater {
      model: 3
      Rectangle {
        required property int index
        width: (root.width - 2 * parent.spacing) / 3
        height: root.height
        radius: width / 2
        color: root.ink
        opacity: root.active ? 0.85 : 0.4
        transform: Scale {
          id: barScale
          origin.x: root.width / 6; origin.y: root.height / 2
          yScale: root.active ? [0.55, 0.85, 0.4][index] : 0.25
        }
        SequentialAnimation {
          running: root.moving
          loops: Animation.Infinite
          NumberAnimation { target: barScale; property: "yScale"; to: [0.9, 0.45, 0.7][index]; duration: 700 + index * 130; easing.type: Easing.InOutSine }
          NumberAnimation { target: barScale; property: "yScale"; to: [0.35, 0.8, 0.4][index]; duration: 780 + index * 100; easing.type: Easing.InOutSine }
        }
      }
    }
  }
}
