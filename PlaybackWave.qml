import QtQuick

// Status feedback, not an invented audio meter. A short response when playback
// starts settles into a static mark; an open radio panel does not animate forever.
Item {
  id: root
  property bool active: false
  property bool animate: true
  property color ink: "white"
  property real emphasis: 0
  readonly property bool moving: feedback.running
  function respond() {
    feedback.stop()
    emphasis = 0
    if (active && animate && visible) feedback.restart()
  }
  onActiveChanged: respond()
  onAnimateChanged: if (!animate) { feedback.stop(); emphasis = 0 }
  onVisibleChanged: if (!visible) { feedback.stop(); emphasis = 0 }
  Component.onCompleted: respond()
  SequentialAnimation {
    id: feedback
    objectName: "playbackFeedback"
    NumberAnimation { target: root; property: "emphasis"; from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "emphasis"; to: 0; duration: 220; easing.type: Easing.OutCubic }
  }
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
          origin.x: root.width / 6; origin.y: root.height / 2
          yScale: root.active ? [0.55, 0.85, 0.4][index] + root.emphasis * [0.25, 0.12, 0.3][index] : 0.25
        }
      }
    }
  }
}
